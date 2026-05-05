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
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
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
