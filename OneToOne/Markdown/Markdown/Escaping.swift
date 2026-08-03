import Foundation

enum MarkdownEscaping {

    /// Characters that need a leading backslash when emitted as part of an
    /// inline text run so the serializer doesn't accidentally produce new
    /// markup. Conservative subset of the CommonMark spec — enough for round-trip
    /// of normal user content.
    private static let inlineSpecials: Set<Character> = [
        "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", "!"
    ]

    /// Escapes literal markdown characters inside a plain text run. Does NOT
    /// touch characters that are already part of a markup span (those are
    /// emitted by the serializer's structural code, not by this function).
    static func escapeInline(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if inlineSpecials.contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    /// Escapes a URL for use inside `[label](url)`. `URL.absoluteString` is
    /// already percent-encoded per RFC 3986 — re-running it through
    /// `addingPercentEncoding` would percent-encode the `%` signs themselves,
    /// stacking one extra layer of encoding at every round-trip. The only
    /// remaining risk for the markdown syntax is `(`/`)`, which are valid
    /// unescaped URL characters but would break `](…)`; those two are encoded
    /// by hand instead.
    static func escapeURL(_ url: String) -> String {
        url.replacingOccurrences(of: "(", with: "%28")
           .replacingOccurrences(of: ")", with: "%29")
    }
}
