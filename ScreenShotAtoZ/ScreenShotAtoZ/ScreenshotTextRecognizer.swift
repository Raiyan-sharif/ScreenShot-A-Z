//
//  ScreenshotTextRecognizer.swift
//  ScreenShotAtoZ
//

import UIKit
import Vision

enum ScreenshotTextRecognizer {
    struct RecognizedLine {
        let text: String
        let boundingBox: CGRect // normalized Vision coordinates
    }

    struct Result {
        let text: String
        let lines: [RecognizedLine]
    }

    /// Returns recognized text data, or nil if cancelled before completion.
    static func recognizeText(in image: UIImage, cancellation: @escaping @Sendable () -> Bool) async -> Result? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var resumed = false
                func resumeOnce(_ value: Result?) {
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
                        resumeOnce(Result(text: error.localizedDescription, lines: []))
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
                    let lines: [RecognizedLine] = sorted.compactMap {
                        guard let text = $0.topCandidates(1).first?.string else { return nil }
                        return RecognizedLine(text: text, boundingBox: $0.boundingBox)
                    }
                    let text = lines.map(\.text).joined(separator: "\n")
                    resumeOnce(Result(text: text, lines: lines))
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
                        resumeOnce(Result(text: error.localizedDescription, lines: []))
                    }
                }
            }
        }
    }
}
