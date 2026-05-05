//
//  ScreenshotTextRecognizer.swift
//  ScreenShotAtoZ
//

import UIKit
import Vision

enum ScreenshotTextRecognizer {
    /// Returns recognized text, empty string if none, or an error message on failure. `nil` if cancelled before completion.
    static func recognizeText(in image: UIImage, cancellation: @escaping @Sendable () -> Bool) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var resumed = false
                func resumeOnce(_ value: String?) {
                    if resumed { return }
                    resumed = true
                    continuation.resume(returning: value)
                }
                let request = VNRecognizeTextRequest { request, error in
                    if cancellation() {
                        resumeOnce(nil)
                        return
                    }
                    if let error {
                        resumeOnce(error.localizedDescription)
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let sorted = observations.sorted { lhs, rhs in
                        let yDiff = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                        if yDiff > 0.02 {
                            // Vision coordinates have origin at bottom-left.
                            return lhs.boundingBox.midY > rhs.boundingBox.midY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n")
                    resumeOnce(text.isEmpty ? "" : text)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    if cancellation() {
                        resumeOnce(nil)
                    } else {
                        resumeOnce(error.localizedDescription)
                    }
                }
            }
        }
    }
}
