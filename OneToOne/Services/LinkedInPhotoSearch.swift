import Foundation
import AppKit

/// Two-mode helper for finding a collaborator's photo:
/// - `openLinkedInSearch`: launches the LinkedIn people-search URL in the
///   default browser; user can copy a photo and paste it back into the app
///   via `pasteFromClipboard`.
/// - `bingImageSearch`: hits Azure Bing Image Search for "<name> LinkedIn"
///   and returns thumbnail URLs the UI can present in a grid.
enum LinkedInPhotoSearch {

    // MARK: - Mode B: Browser open

    static func openLinkedInSearch(name: String) {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.linkedin.com/search/results/people/?keywords=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Reads an NSImage from the pasteboard (handles image data and file URLs).
    static func pasteImageFromClipboard() -> Data? {
        let pb = NSPasteboard.general

        // Direct image types.
        if let types = pb.types {
            for t in types {
                if let data = pb.data(forType: t), NSImage(data: data) != nil {
                    return data
                }
            }
        }

        // File URLs.
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls {
                if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                    return data
                }
            }
        }

        return nil
    }

    // MARK: - Mode A: Bing Image Search

    struct BingResult: Identifiable, Hashable {
        let id: String
        let thumbnailURL: URL
        let contentURL: URL
        let hostPageURL: URL?
    }

    enum BingError: Error, LocalizedError {
        case missingKey
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Clé Bing manquante dans les Préférences."
            case .invalidResponse: return "Réponse Bing inattendue."
            case .httpStatus(let code): return "Bing HTTP \(code)."
            }
        }
    }

    /// Searches Bing Image API for "<name> LinkedIn". Requires a valid
    /// Azure Cognitive Services key with Bing Search v7 access.
    static func bingImageSearch(name: String, key: String, limit: Int = 24) async throws -> [BingResult] {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw BingError.missingKey }

        let q = "\(name) LinkedIn"
        guard var comps = URLComponents(string: "https://api.bing.microsoft.com/v7.0/images/search") else {
            throw BingError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "count", value: String(limit)),
            URLQueryItem(name: "safeSearch", value: "Moderate"),
            URLQueryItem(name: "imageType", value: "Photo"),
            URLQueryItem(name: "size", value: "Medium")
        ]
        guard let url = comps.url else { throw BingError.invalidResponse }

        var req = URLRequest(url: url)
        req.setValue(trimmedKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BingError.invalidResponse }
        guard http.statusCode == 200 else { throw BingError.httpStatus(http.statusCode) }

        struct BingResponse: Decodable {
            struct Value: Decodable {
                let imageId: String?
                let thumbnailUrl: String
                let contentUrl: String
                let hostPageUrl: String?
            }
            let value: [Value]
        }

        let decoded = try JSONDecoder().decode(BingResponse.self, from: data)
        return decoded.value.compactMap { v in
            guard let thumb = URL(string: v.thumbnailUrl),
                  let content = URL(string: v.contentUrl) else { return nil }
            return BingResult(
                id: v.imageId ?? UUID().uuidString,
                thumbnailURL: thumb,
                contentURL: content,
                hostPageURL: v.hostPageUrl.flatMap(URL.init(string:))
            )
        }
    }

    /// Downloads the full-resolution image for a chosen Bing result.
    static func downloadImage(at url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BingError.httpStatus(http.statusCode)
        }
        guard NSImage(data: data) != nil else { throw BingError.invalidResponse }
        return data
    }
}
