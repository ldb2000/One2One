import Foundation
import Vision

enum OCRService {
    static func recognize(imageAt url: URL,
                          languages: [String] = ["fr-FR", "en-US"]) async throws -> String {
        let handler = VNImageRequestHandler(url: url)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    static func recognize(cgImage: CGImage,
                          languages: [String] = ["fr-FR", "en-US"]) async throws -> String {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
