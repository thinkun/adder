import AVFoundation
import Combine
import Foundation
import ZeticMLange

enum WhisperError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isReady = false
    @Published private(set) var status = "Whisper not loaded"
    private let worker = WhisperWorker()
    private var recorder: AVAudioRecorder?
    private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("adder-voice.wav")

    func prepare(personalKey: String, progress: @escaping @Sendable (String, Double) -> Void = { _, _ in }) async throws {
        status = "Loading Whisper Tiny…"
        try await worker.prepare(personalKey: personalKey, progress: progress)
        isReady = true
        status = "Whisper ready · record up to 30 seconds"
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func startRecording() throws {
        guard isReady else { throw WhisperError.message("Load Whisper before recording.") }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw WhisperError.message("Allow microphone access in Settings, then try recording again.")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        recorder = try AVAudioRecorder(url: recordingURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ])
        guard recorder?.record(forDuration: 30) == true else { throw WhisperError.message("Could not start the microphone.") }
        isRecording = true
        status = "Recording · tap Stop when finished"
    }

    func stopAndTranscribe() async throws -> String {
        guard isRecording else { throw WhisperError.message("No recording to transcribe.") }
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        status = "Transcribing locally with Whisper…"
        do {
            let result = try await worker.transcribe(url: recordingURL)
            status = "Whisper ready"
            return result
        } catch {
            status = "Whisper failed"
            throw error
        }
    }
}

private actor WhisperWorker {
    private var encoder: ZeticMLangeModel?
    private var decoder: ZeticMLangeModel?
    private var features: WhisperLogMel?
    private var vocabulary: [Int: String] = [:]
    private var byteDecoder: [UInt32: UInt8] = [:]
    private var prepared = false

    func prepare(personalKey: String, progress: @escaping @Sendable (String, Double) -> Void = { _, _ in }) async throws {
        if prepared { return }
        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "json"),
              let filtersURL = Bundle.main.url(forResource: "mel_filters_80", withExtension: "bin") else {
            throw WhisperError.message("Whisper vocabulary or mel filterbank is missing from the app bundle.")
        }
        let vocab = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: vocabURL))
        vocabulary = Dictionary(uniqueKeysWithValues: vocab.map { ($0.value, $0.key) })
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var scalars = bytes
        var extra = 0
        for byte in 0...255 where !bytes.contains(byte) {
            bytes.append(byte); scalars.append(256 + extra); extra += 1
        }
        byteDecoder = Dictionary(uniqueKeysWithValues: zip(scalars, bytes).map { (UInt32($0.0), UInt8($0.1)) })
        features = try WhisperLogMel(filterData: Data(contentsOf: filtersURL))
        encoder = try await ZeticMLangeModel(personalKey: personalKey, name: "OpenAI/whisper-tiny-encoder", version: 1, cacheHandlingPolicy: .KEEP_EXISTING, onDownload: { progress("Whisper encoder", Double($0)) })
        decoder = try await ZeticMLangeModel(personalKey: personalKey, name: "OpenAI/whisper-tiny-decoder", version: 1, cacheHandlingPolicy: .KEEP_EXISTING, onDownload: { progress("Whisper decoder", Double($0)) })
        guard encoder?.inputTensors.first?.shape == [1, 80, 3000],
              decoder?.inputTensors.count == 3,
              decoder?.inputTensors.first?.shape == [1, 448],
              decoder?.inputTensors[1].shape == [1, 1500, 384],
              decoder?.inputTensors[2].shape == [1, 448] else {
            throw WhisperError.message("Whisper library tensor shapes differ from the verified Tiny pipeline.")
        }
        prepared = true
    }

    func transcribe(url: URL) throws -> String {
        guard let encoder, let decoder, let features else { throw WhisperError.message("Whisper is not loaded.") }
        let file = try AVAudioFile(forReading: url)
        guard let audio = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw WhisperError.message("Could not read microphone audio.")
        }
        try file.read(into: audio)
        guard let channel = audio.floatChannelData?[0], audio.frameLength > 1600,
              file.processingFormat.sampleRate == 16000 else { throw WhisperError.message("Record at least a short sentence.") }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(audio.frameLength)))
        guard samples.contains(where: { abs($0) > 0.001 }) else {
            throw WhisperError.message("The recording is silent. Check microphone access and try again.")
        }
        let mel = features.compute(samples)
        let input = Tensor(data: mel.withUnsafeBufferPointer { Data(buffer: $0) }, dataType: BuiltinDataType.float32, shape: [1, 80, 3000])
        guard let hidden = try encoder.run(inputs: [input]).first else { throw WhisperError.message("Whisper encoder returned no output.") }
        // Respect the installed model metadata: published samples use Int32;
        // the current documentation's export recipe uses Int64.
        let tokenType = decoder.inputTensors[0].dtype
        let maskType = decoder.inputTensors[2].dtype
        var ids = [Int](repeating: 0, count: 448)
        var mask = [Int](repeating: 0, count: 448)
        let prefix = [50258, 50259, 50359, 50363] // English, transcribe, no timestamps.
        for (index, token) in prefix.enumerated() { ids[index] = token; mask[index] = 1 }
        var generated: [Int] = []
        var reachedEnd = false
        // Bound expensive full-sequence decoder runs. Never silently return a
        // truncated email, number, or meeting request when this limit is hit.
        let maxTokens = 160
        for position in 3..<(4 + maxTokens) {
            let next: Int = try autoreleasepool {
                let inputs = [try integerTensor(ids, dtype: tokenType), hidden, try integerTensor(mask, dtype: maskType)]
                guard let logits = try decoder.run(inputs: inputs).first else { throw WhisperError.message("Whisper decoder returned no output.") }
                let floatType = logits.dataType as? BuiltinDataType
                guard floatType == .float32 || floatType == .float16 else {
                    throw WhisperError.message("Unexpected Whisper decoder output dtype.")
                }
                let stride = logits.dataType.size
                guard logits.data.count % (448 * stride) == 0 else { throw WhisperError.message("Unexpected Whisper decoder output size.") }
                let vocabSize = logits.data.count / (448 * stride)
                return logits.data.withUnsafeBytes { raw in
                    var best = 50257
                    var bestValue = -Float.infinity
                    let row = position * vocabSize
                    for token in 0..<vocabSize {
                        if token >= 50258 || token == 50256 { continue }
                        if generated.isEmpty && token == 220 { continue }
                        let value: Float
                        if floatType == .float32 {
                            let bits = raw.loadUnaligned(fromByteOffset: (row + token) * stride, as: UInt32.self)
                            value = Float(bitPattern: UInt32(littleEndian: bits))
                        } else {
                            let bits = raw.loadUnaligned(fromByteOffset: (row + token) * stride, as: UInt16.self)
                            value = Float(Float16(bitPattern: UInt16(littleEndian: bits)))
                        }
                        if value > bestValue { best = token; bestValue = value }
                    }
                    return best
                }
            }
            if next == 50257 { reachedEnd = true; break }
            guard generated.count < maxTokens else {
                throw WhisperError.message("The transcription exceeded the demo's length limit. Record a shorter note so no details are lost.")
            }
            generated.append(next)
            ids[position + 1] = next
            mask[position + 1] = 1
            if generated.count >= 12 && Set(generated.suffix(12)).count == 1 {
                throw WhisperError.message("Whisper repeated itself. Try a shorter recording with less background noise.")
            }
        }
        guard reachedEnd else { throw WhisperError.message("Whisper did not finish the transcription. Record a shorter note.") }
        let bytes = generated.flatMap { token in
            (vocabulary[token] ?? "").unicodeScalars.compactMap { byteDecoder[$0.value] }
        }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WhisperError.message("No speech recognized. Try a clearer, longer recording.") }
        return text
    }

    private func integerTensor(_ values: [Int], dtype: any DataType) throws -> Tensor {
        let data: Data
        if let builtin = dtype as? BuiltinDataType, builtin == .int32 {
            data = values.map { Int32($0) }.withUnsafeBufferPointer { Data(buffer: $0) }
        } else if let builtin = dtype as? BuiltinDataType, builtin == .int64 {
            data = values.map { Int64($0) }.withUnsafeBufferPointer { Data(buffer: $0) }
        } else { throw WhisperError.message("Unsupported Whisper decoder integer dtype.") }
        return Tensor(data: data, dataType: dtype, shape: [1, 448])
    }
}
