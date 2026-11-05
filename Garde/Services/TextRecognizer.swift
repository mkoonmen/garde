import UIKit
import Vision

/// On-device OCR + image labeling with Apple's Vision framework. No network.
enum TextRecognizer {
    /// Reads all text in a photo (receipts, labels, expiration stamps), top-to-bottom.
    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                // Sort top-to-bottom, then left-to-right so receipt lines stay in order.
                let lines = obs.sorted {
                    abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                        ? $0.boundingBox.midY > $1.boundingBox.midY
                        : $0.boundingBox.minX < $1.boundingBox.minX
                }.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: image.cgOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Labels what's in a photo (e.g. "apple", "cheese") for fridge/haul photos.
    static func classify(_ image: UIImage, minConfidence: Float = 0.25) async throws -> [String] {
        guard let cg = image.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNClassifyImageRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let labels = ((req.results as? [VNClassificationObservation]) ?? [])
                    .filter { $0.confidence >= minConfidence }
                    .prefix(15)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                cont.resume(returning: Array(labels))
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: image.cgOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
            }
        }
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    /// Downscaled JPEG for storage so photos don't bloat the database.
    func storageJPEG(maxDimension: CGFloat = 1600) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
