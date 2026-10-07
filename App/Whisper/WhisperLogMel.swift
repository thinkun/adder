import Accelerate
import Foundation

// Swift port of Zetic's Apache-2.0 VoxScribe log_mel.dart pipeline.
// Periodic Hann, centered reflect padding, Slaney filters, and Whisper scaling.
final class WhisperLogMel {
    private let filters: [Float]
    private let window: [Float]
    private let cosine: [[Float]]
    private let sine: [[Float]]

    init(filterData: Data) throws {
        guard filterData.count == 80 * 201 * 4 else { throw WhisperError.message("Invalid Whisper mel filterbank.") }
        filters = filterData.withUnsafeBytes { raw in
            (0..<(80 * 201)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
        window = (0..<400).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / 400) }
        cosine = (0..<201).map { k in (0..<400).map { n in cos(-2 * Float.pi * Float(k * n) / 400) } }
        sine = (0..<201).map { k in (0..<400).map { n in sin(-2 * Float.pi * Float(k * n) / 400) } }
    }

    func compute(_ samples: [Float]) -> [Float] {
        var audio = Array(samples.prefix(480000))
        audio += [Float](repeating: 0, count: 480000 - audio.count)
        let padded = Array((1...200).reversed().map { audio[$0] }) + audio + (0..<200).map { audio[479998 - $0] }
        var output = [Float](repeating: -10, count: 80 * 3000)
        var maximum: Float = -10
        var segment = [Float](repeating: 0, count: 400)
        var power = [Float](repeating: 0, count: 201)
        for frame in 0..<3000 {
            let start = frame * 160
            var nonzero = false
            for n in 0..<400 { segment[n] = padded[start + n] * window[n]; nonzero = nonzero || segment[n] != 0 }
            if !nonzero { continue }
            for k in 0..<201 {
                var real: Float = 0
                var imaginary: Float = 0
                vDSP_dotpr(segment, 1, cosine[k], 1, &real, 400)
                vDSP_dotpr(segment, 1, sine[k], 1, &imaginary, 400)
                power[k] = real * real + imaginary * imaginary
            }
            filters.withUnsafeBufferPointer { bank in
                for mel in 0..<80 {
                    var energy: Float = 0
                    vDSP_dotpr(bank.baseAddress!.advanced(by: mel * 201), 1, power, 1, &energy, 201)
                    let value = log10(max(energy, 1e-10))
                    output[mel * 3000 + frame] = value
                    maximum = max(maximum, value)
                }
            }
        }
        let floor = maximum - 8
        return output.map { (max($0, floor) + 4) / 4 }
    }
}
