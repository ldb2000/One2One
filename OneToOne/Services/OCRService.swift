import Foundation
import Vision

enum OCRService {
    /// Reconnaît le texte d'une image située à `url` via Vision.
    /// Reconnaissance `.accurate` avec correction linguistique ; les lignes
    /// détectées (meilleur candidat de chaque observation) sont jointes par "\n".
    static func recognize(imageAt url: URL,
                          languages: [String] = ["fr-FR", "en-US"]) async throws -> String {
        try await perform(handler: VNImageRequestHandler(url: url), languages: languages)
    }

    /// Reconnaît le texte d'un `CGImage` via Vision.
    /// Même configuration et même format de sortie que la variante `imageAt:`.
    static func recognize(cgImage: CGImage,
                          languages: [String] = ["fr-FR", "en-US"]) async throws -> String {
        try await perform(handler: VNImageRequestHandler(cgImage: cgImage), languages: languages)
    }

    /// Exécute une requête de reconnaissance de texte sur le handler fourni et
    /// renvoie les lignes détectées jointes par "\n".
    private static func perform(handler: VNImageRequestHandler,
                                languages: [String]) async throws -> String {
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
