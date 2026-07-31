import AppKit

/// Converts typed markdown delimiters into the editor's marker-free attributed
/// model. Example: typing `**gras**` leaves `gras` visible with `.mdBold`.
enum ShortcutDetector {
    static func apply(after insertion: String,
                      in textView: NSTextView,
                      cursor: Int,
                      features: Set<MarkdownFeature>) {
        guard insertion == "*" || insertion == "_" || insertion == "`" else { return }
        guard let storage = textView.textStorage else { return }

        if insertion == "*", features.contains(.bold),
           applyInlineShortcut(marker: "**", attribute: .mdBold, in: storage, cursor: cursor) {
            textView.setSelectedRange(NSRange(location: cursor - 4, length: 0))
            return
        }

        if insertion == "_", features.contains(.italic),
           applyInlineShortcut(marker: "_", attribute: .mdItalic, in: storage, cursor: cursor) {
            textView.setSelectedRange(NSRange(location: cursor - 2, length: 0))
            return
        }

        if insertion == "`", features.contains(.inlineCode),
           applyInlineShortcut(marker: "`", attribute: .mdInlineCode, in: storage, cursor: cursor) {
            textView.setSelectedRange(NSRange(location: cursor - 2, length: 0))
            return
        }
    }

    @discardableResult
    private static func applyInlineShortcut(marker: String,
                                            attribute: NSAttributedString.Key,
                                            in storage: NSTextStorage,
                                            cursor: Int) -> Bool {
        let ns = storage.string as NSString
        let markerLength = marker.utf16.count
        guard cursor >= markerLength * 2 else { return false }
        let closerRange = NSRange(location: cursor - markerLength, length: markerLength)
        guard ns.substring(with: closerRange) == marker else { return false }

        let searchRange = NSRange(location: 0, length: cursor - markerLength)
        let openerRange = ns.range(of: marker, options: [.backwards], range: searchRange)
        guard openerRange.location != NSNotFound else { return false }

        let innerStart = openerRange.location + markerLength
        let innerLength = closerRange.location - innerStart
        guard innerLength > 0 else { return false }
        let innerRange = NSRange(location: innerStart, length: innerLength)
        let inner = storage.attributedSubstring(from: innerRange).mutableCopy() as! NSMutableAttributedString
        inner.addAttribute(attribute, value: true, range: NSRange(location: 0, length: inner.length))

        let fullRange = NSRange(location: openerRange.location, length: cursor - openerRange.location)
        storage.replaceCharacters(in: fullRange, with: inner)
        return true
    }
}
