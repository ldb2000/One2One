import Foundation
import AppKit

/// Photo search helpers for collaborator profiles.
///
/// - `openLinkedInSearch`: opens LinkedIn people search in the browser.
/// - `pasteImageFromClipboard`: reads NSPasteboard image bytes (copy/paste flow).
/// - `searchImages`: returns photo candidates from DuckDuckGo by default,
///   or Google Custom Search Engine when API key + CSE ID are set.
enum LinkedInPhotoSearch {

    // MARK: - Browser open

    static func openLinkedInSearch(name: String) {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.linkedin.com/search/results/people/?keywords=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func pasteImageFromClipboard() -> Data? {
        let pb = NSPasteboard.general
        if let types = pb.types {
            for t in types {
                if let data = pb.data(forType: t), NSImage(data: data) != nil { return data }
            }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls {
                if let data = try? Data(contentsOf: url), NSImage(data: data) != nil { return data }
            }
        }
        return nil
    }

    // MARK: - Public types

    struct ImageResult: Identifiable, Hashable {
        let id: String
        let thumbnailURL: URL
        let contentURL: URL
        let hostPageURL: URL?
        let provider: Provider
    }

    enum Provider: String {
        case duckDuckGo = "DuckDuckGo"
        case googleCSE = "Google CSE"
    }

    enum SearchError: Error, LocalizedError {
        case invalidResponse
        case httpStatus(Int, String?)
        case missingVQDToken
        case missingGoogleConfig

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Réponse de recherche inattendue."
            case .httpStatus(let code, let body):
                if let body, !body.isEmpty { return "HTTP \(code): \(body)" }
                return "HTTP \(code)."
            case .missingVQDToken: return "Token DuckDuckGo introuvable (le service a changé). Configure Google CSE en Préférences."
            case .missingGoogleConfig: return "Clé Google API + CSE ID requis."
            }
        }
    }

    /// Routes to Google CSE if both fields are set, otherwise DuckDuckGo.
    static func searchImages(name: String,
                              googleAPIKey: String,
                              googleCSEID: String,
                              limit: Int = 24) async throws -> [ImageResult] {
        let trimmedKey = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCx = googleCSEID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty && !trimmedCx.isEmpty {
            return try await googleCSEImageSearch(name: name, apiKey: trimmedKey, cseId: trimmedCx, limit: limit)
        }
        return try await duckDuckGoImageSearch(name: name, limit: limit)
    }

    // MARK: - DuckDuckGo (no key, unofficial endpoint)

    /// DDG image search is a two-step dance: fetch the HTML SERP to extract
    /// the `vqd` token, then hit the JSON endpoint.
    /// **Unofficial** — DDG can break this at any time.
    static func duckDuckGoImageSearch(name: String, limit: Int = 24) async throws -> [ImageResult] {
        let query = "\(name) LinkedIn"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SearchError.invalidResponse
        }

        // Step 1: fetch the HTML SERP to obtain the vqd token.
        guard let htmlURL = URL(string: "https://duckduckgo.com/?q=\(encoded)&iax=images&ia=images") else {
            throw SearchError.invalidResponse
        }
        var htmlReq = URLRequest(url: htmlURL)
        htmlReq.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (htmlData, htmlResponse) = try await URLSession.shared.data(for: htmlReq)
        guard let httpHtml = htmlResponse as? HTTPURLResponse, httpHtml.statusCode == 200 else {
            throw SearchError.httpStatus((htmlResponse as? HTTPURLResponse)?.statusCode ?? -1, nil)
        }
        guard let html = String(data: htmlData, encoding: .utf8) else { throw SearchError.invalidResponse }
        guard let vqd = extractVQD(from: html) else { throw SearchError.missingVQDToken }

        // Step 2: JSON request.
        guard var comps = URLComponents(string: "https://duckduckgo.com/i.js") else { throw SearchError.invalidResponse }
        comps.queryItems = [
            URLQueryItem(name: "l", value: "fr-fr"),
            URLQueryItem(name: "o", value: "json"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "vqd", value: vqd),
            URLQueryItem(name: "f", value: ",,,,,"),
            URLQueryItem(name: "p", value: "1")
        ]
        guard let jsonURL = comps.url else { throw SearchError.invalidResponse }
        var jsonReq = URLRequest(url: jsonURL)
        jsonReq.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        jsonReq.setValue("application/json", forHTTPHeaderField: "Accept")
        jsonReq.setValue("https://duckduckgo.com/", forHTTPHeaderField: "Referer")

        let (jsonData, jsonResponse) = try await URLSession.shared.data(for: jsonReq)
        guard let httpJson = jsonResponse as? HTTPURLResponse, httpJson.statusCode == 200 else {
            let body = String(data: jsonData, encoding: .utf8)
            throw SearchError.httpStatus((jsonResponse as? HTTPURLResponse)?.statusCode ?? -1, body)
        }

        struct DDGResponse: Decodable {
            struct Item: Decodable {
                let image: String?
                let thumbnail: String?
                let url: String?
            }
            let results: [Item]?
        }

        let decoded = try JSONDecoder().decode(DDGResponse.self, from: jsonData)
        let items = decoded.results ?? []
        return items.prefix(limit).compactMap { item in
            guard let imageStr = item.image, let content = URL(string: imageStr) else { return nil }
            let thumb = URL(string: item.thumbnail ?? imageStr) ?? content
            return ImageResult(
                id: imageStr,
                thumbnailURL: thumb,
                contentURL: content,
                hostPageURL: item.url.flatMap(URL.init(string:)),
                provider: .duckDuckGo
            )
        }
    }

    /// Extracts DuckDuckGo's `vqd` token from the HTML SERP. This per-search
    /// nonce is required as a query param by the `i.js` JSON endpoint; without
    /// it the request is rejected. Tries several quoting forms; `nil` if absent.
    private static func extractVQD(from html: String) -> String? {
        // Forms seen in DDG HTML: vqd="3-...." or vqd='3-....' or vqd=3-....&
        let patterns = [
            #"vqd="([^"]+)""#,
            #"vqd='([^']+)'"#,
            #"vqd=([^&"'\s]+)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    // MARK: - Google Custom Search Engine

    static func googleCSEImageSearch(name: String, apiKey: String, cseId: String, limit: Int = 10) async throws -> [ImageResult] {
        let query = "\(name) LinkedIn"
        guard var comps = URLComponents(string: "https://www.googleapis.com/customsearch/v1") else {
            throw SearchError.invalidResponse
        }
        // Google CSE caps `num` at 10 per request.
        comps.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "cx", value: cseId),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "searchType", value: "image"),
            URLQueryItem(name: "num", value: String(min(limit, 10))),
            URLQueryItem(name: "safe", value: "active")
        ]
        guard let url = comps.url else { throw SearchError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard http.statusCode == 200 else {
            throw SearchError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        struct GoogleResponse: Decodable {
            struct Item: Decodable {
                struct Image: Decodable {
                    let thumbnailLink: String?
                    let contextLink: String?
                }
                let link: String?
                let image: Image?
            }
            let items: [Item]?
        }

        let decoded = try JSONDecoder().decode(GoogleResponse.self, from: data)
        let items = decoded.items ?? []
        return items.compactMap { item in
            guard let linkStr = item.link, let content = URL(string: linkStr) else { return nil }
            let thumb = URL(string: item.image?.thumbnailLink ?? linkStr) ?? content
            return ImageResult(
                id: linkStr,
                thumbnailURL: thumb,
                contentURL: content,
                hostPageURL: item.image?.contextLink.flatMap(URL.init(string:)),
                provider: .googleCSE
            )
        }
    }

    // MARK: - Download

    static func downloadImage(at url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SearchError.httpStatus(http.statusCode, nil)
        }
        guard NSImage(data: data) != nil else { throw SearchError.invalidResponse }
        return data
    }

    /// User-Agent Safari usurpé : DuckDuckGo sert une page/JSON différente (ou
    /// bloque) selon le client. Se faire passer pour un navigateur de bureau
    /// garantit la présence du token `vqd` et de l'endpoint images attendus.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
