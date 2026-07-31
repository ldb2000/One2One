import Foundation

struct MarkdownEditResult: Equatable {
    var text: String
    var selectedRange: NSRange
}

enum MarkdownEditingCommands {
    static func wrapSelection(
        in text: String,
        range: NSRange,
        marker: String,
        placeholder: String
    ) -> MarkdownEditResult {
        let ns = text as NSString
        let safeRange = clamped(range, length: ns.length)

        if safeRange.length > 0,
           safeRange.location >= marker.utf16.count,
           safeRange.location + safeRange.length + marker.utf16.count <= ns.length {
            let beforeRange = NSRange(location: safeRange.location - marker.utf16.count, length: marker.utf16.count)
            let afterRange = NSRange(location: safeRange.location + safeRange.length, length: marker.utf16.count)
            if ns.substring(with: beforeRange) == marker,
               ns.substring(with: afterRange) == marker {
                let mutable = NSMutableString(string: text)
                mutable.deleteCharacters(in: afterRange)
                mutable.deleteCharacters(in: beforeRange)
                let selection = NSRange(
                    location: safeRange.location - marker.utf16.count,
                    length: safeRange.length
                )
                return MarkdownEditResult(text: mutable as String, selectedRange: selection)
            }
        }

        let selected = safeRange.length == 0 ? placeholder : ns.substring(with: safeRange)
        let replacement = marker + selected + marker
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: safeRange, with: replacement)
        let selection = NSRange(
            location: safeRange.location + marker.utf16.count,
            length: selected.utf16.count
        )
        return MarkdownEditResult(text: mutable as String, selectedRange: selection)
    }

    static func toggleLinePrefix(
        in text: String,
        range: NSRange,
        prefix: String,
        exclusivePrefixes: [String] = []
    ) -> MarkdownEditResult {
        let ns = text as NSString
        let safeRange = clamped(range, length: ns.length)
        let lineRanges = selectedLineRanges(in: ns, selection: safeRange)
        guard !lineRanges.isEmpty else {
            let newText = prefix + text
            return MarkdownEditResult(
                text: newText,
                selectedRange: NSRange(location: safeRange.location + prefix.utf16.count, length: safeRange.length)
            )
        }

        let lines = lineRanges.map { ns.substring(with: $0) }
        let shouldRemove = lines.allSatisfy { lineHasPrefix($0, prefix: prefix) }

        var deltaBeforeSelection = 0
        let mutable = NSMutableString(string: text)

        for lineRange in lineRanges.reversed() {
            let originalLine = ns.substring(with: lineRange)
            let lineStart = lineRange.location
            let replacement: String
            let delta: Int

            if shouldRemove, let removed = removePrefix(prefix, from: originalLine) {
                replacement = removed
                delta = replacement.utf16.count - originalLine.utf16.count
            } else {
                let stripped = removeFirstMatchingPrefix(exclusivePrefixes, from: originalLine) ?? originalLine
                replacement = prefix + stripped
                delta = replacement.utf16.count - originalLine.utf16.count
            }

            mutable.replaceCharacters(in: lineRange, with: replacement)
            if lineStart <= safeRange.location {
                deltaBeforeSelection += delta
            }
        }

        let newLocation = max(0, safeRange.location + deltaBeforeSelection)
        return MarkdownEditResult(
            text: mutable as String,
            selectedRange: NSRange(location: newLocation, length: safeRange.length)
        )
    }

    private static func selectedLineRanges(in text: NSString, selection: NSRange) -> [NSRange] {
        guard text.length > 0 else { return [] }

        let start = min(selection.location, text.length)
        let rawEnd = min(selection.location + selection.length, text.length)
        let end = selection.length > 0 && rawEnd > start ? rawEnd - 1 : rawEnd
        let coveredRange = NSRange(location: start, length: max(0, end - start + 1))
        let enclosing = text.lineRange(for: coveredRange)

        var ranges: [NSRange] = []
        var cursor = enclosing.location
        let enclosingEnd = min(enclosing.location + enclosing.length, text.length)
        while cursor < enclosingEnd {
            let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
            if lineRange.length == 0 { break }
            ranges.append(lineRange)
            cursor = lineRange.location + lineRange.length
        }
        return ranges
    }

    private static func lineHasPrefix(_ line: String, prefix: String) -> Bool {
        removePrefix(prefix, from: line) != nil
    }

    private static func removePrefix(_ prefix: String, from line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func removeFirstMatchingPrefix(_ prefixes: [String], from line: String) -> String? {
        for prefix in prefixes.sorted(by: { $0.count > $1.count }) {
            if let stripped = removePrefix(prefix, from: line) {
                return stripped
            }
        }
        return nil
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let end = min(max(location, range.location + range.length), length)
        return NSRange(location: location, length: end - location)
    }
}
