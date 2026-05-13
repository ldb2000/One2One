import Foundation
import AppKit

/// Two-mode helper for finding a collaborator's photo:
/// - `openLinkedInSearch`: launches the LinkedIn people-search URL in the
///   default browser; user can copy a photo and paste it back into the app
///   via `pasteImageFromClipboard`.
/// - `braveImageSearch`: hits the Brave Search API images endpoint for
///   "<name> LinkedIn" and returns thumbnail URLs the UI can present.
///   Replaces the retired Bing Search v7.
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

    /// Reads an NSImage from the pasteboard (image data or file URLs).
    static func pasteImageFromClipboard() -> Data? {
        let pb = NSPasteboard.general

        if let types = pb.types {
            for t in types {
                if let data = pb.data(forType: t), NSImage(data: data) != nil {
                    return data
                }
            }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls {
                if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                    return data
                }
            }
        }
        return nil
    }

    // MARK: - Mode A: Brave Image Search

    struct ImageResult: Identifiable, Hashable {
        let id: String
        let thumbnailURL: URL
        let contentURL: URL
        let hostPageURL: URL?
    }

    enum SearchError: Error, LocalizedError {
        case missingKey
        case invalidResponse
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Clé Brave Search manquante dans les Préférences."
            case .invalidResponse: return "Réponse Brave inattendue."
            case .httpStatus(let code, let body):
                if let body, !body.isEmpty { return "Brave HTTP \(code): \(body)" }
                return "Brave HTTP \(code)."
            }
        }
    }

    /// Calls the Brave Search images endpoint for "<name> LinkedIn".
    /// Endpoint: GET https://api.search.brave.com/res/v1/images/search
    /// Auth: header `X-Subscription-Token: <key>`.
    /// Free plan: 2000 requests/month, 1 query/sec rate limit.
    static func braveImageSearch(name: String, key: String, limit: Int = 24) async throws -> [ImageResult] {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.missingKey }

        let q = "\(name) LinkedIn"
        guard var comps = URLComponents(string: "https://api.search.brave.com/res/v1/images/search") else {
            throw SearchError.invalidResponse
        }
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "count", value: String(min(limit, 100))),
            URLQueryItem(name: "safesearch", value: "strict"),
            URLQueryItem(name: "search_lang", value: "fr")
        ]
        guard let url = comps.url else { throw SearchError.invalidResponse }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        req.setValue(trimmedKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw SearchError.httpStatus(http.statusCode, body)
        }

        struct BraveResponse: Decodable {
            struct Result: Decodable {
                struct Thumbnail: Decodable { let src: String? }
                struct Properties: Decodable { let url: String? }
                let url: String?
                let thumbnail: Thumbnail?
                let properties: Properties?
            }
            let results: [Result]?
        }

        let decoded = try JSONDecoder().decode(BraveResponse.self, from: data)
        let results = decoded.results ?? []
        return results.compactMap { r in
            guard let thumbStr = r.thumbnail?.src, let thumb = URL(string: thumbStr) else { return nil }
            let contentStr = r.properties?.url ?? r.url ?? thumbStr
            guard let content = URL(string: contentStr) else { return nil }
            return ImageResult(
                id: contentStr,
                thumbnailURL: thumb,
                contentURL: content,
                hostPageURL: r.url.flatMap(URL.init(string:))
            )
        }
    }

    /// Downloads the full-resolution image for a chosen search result.
    static func downloadImage(at url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SearchError.httpStatus(http.statusCode, nil)
        }
        guard NSImage(data: data) != nil else { throw SearchError.invalidResponse }
        return data
    }
}
