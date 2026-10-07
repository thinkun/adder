import Combine
import CoreLocation
import Foundation
import ImageIO
import UIKit
import Vision

@MainActor
final class CaptureContext: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var capturedAt = Date()
    @Published var photos: [UIImage] = []
    @Published private(set) var locationDescription: String?
    @Published private(set) var locationStatus = "Location optional"

    private let manager = CLLocationManager()
    private var pendingLocation: CheckedContinuation<String?, Never>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func resetCapture() {
        finishLocation(nil, status: "Location optional")
        capturedAt = Date()
        photos = []
        locationDescription = nil
    }

    func addPhoto(_ image: UIImage) { photos.append(image) }

    func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
    }

    /// One real device fix, including accuracy and measurement time. No reverse
    /// geocoder or invented venue name; coordinates also work without network.
    func captureLocation() async -> String? {
        guard pendingLocation == nil else { return locationDescription }
        guard CLLocationManager.locationServicesEnabled() else {
            locationStatus = "Location Services are off"
            return nil
        }
        locationStatus = "Getting current location…"
        return await withCheckedContinuation { continuation in
            pendingLocation = continuation
            requestAuthorizedLocation()
        }
    }

    private func requestAuthorizedLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            locationStatus = "Allow location to record where you captured this"
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationStatus = "Getting current location…"
            if timeout == nil {
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    self?.finishLocation(nil, status: "No location fix available; continue without it")
                }
            }
            manager.requestLocation()
        case .denied, .restricted:
            finishLocation(nil, status: "Location permission unavailable; continue without it")
        @unknown default:
            finishLocation(nil, status: "Location unavailable")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingLocation != nil else { return }
        requestAuthorizedLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard pendingLocation != nil else { return }
        guard let fix = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) <= 120
        }) else { finishLocation(nil, status: "No recent location fix available"); return }
        let measuredAt = ISO8601DateFormatter().string(from: fix.timestamp)
        let coordinates = String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), fix.coordinate.latitude, fix.coordinate.longitude)
        let detail = "Device capture location: \(coordinates) (accuracy ±\(Int(fix.horizontalAccuracy.rounded())) m; measured \(measuredAt)). This is capture context, not an inferred meeting venue."
        locationDescription = detail
        finishLocation(detail, status: "Location captured · ±\(Int(fix.horizontalAccuracy.rounded())) m")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard pendingLocation != nil else { return }
        finishLocation(nil, status: "Location unavailable; continue without it")
    }

    private func finishLocation(_ value: String?, status: String) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        locationStatus = status
        let continuation = pendingLocation
        pendingLocation = nil
        continuation?.resume(returning: value)
    }
}

enum PhotoTextError: LocalizedError {
    case unreadableImage(Int)
    var errorDescription: String? {
        switch self { case .unreadableImage(let number): return "Photo \(number) could not be read. Choose another image." }
    }
}

enum PhotoTextExtractor {
    /// Runs Vision locally, preserving separate photo evidence and disabling
    /// language correction so proper names and URL spelling are not rewritten.
    static func extract(_ images: [UIImage]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var blocks: [String] = []
            for (index, image) in images.enumerated() {
                try Task.checkCancellation()
                let block = try autoreleasepool { () throws -> String in
                    guard let cgImage = image.cgImage else { throw PhotoTextError.unreadableImage(index + 1) }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    request.automaticallyDetectsLanguage = true
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.imageOrientation.visionOrientation, options: [:])
                    try handler.perform([request])
                    let observations = (request.results ?? []).sorted { lhs, rhs in
                        let delta = lhs.boundingBox.midY - rhs.boundingBox.midY
                        return abs(delta) > 0.02 ? delta > 0 : lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.isEmpty ? "No readable text detected. This photo supplies an image only; do not invent names or event details from it." : lines.joined(separator: "\n")
                    return "Photo \(index + 1) — locally recognized text (may contain OCR mistakes):\n\(text)"
                }
                blocks.append(block)
            }
            return blocks.joined(separator: "\n\n")
        }.value
    }
}

private extension UIImage.Orientation {
    var visionOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
