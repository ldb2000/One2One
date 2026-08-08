import AppKit

let BAND: CGFloat = 307

func measure(_ label: String, configure: (NSTextStorage, NSLayoutManager, NSTextContainer) -> Void) {
    let s = NSTextStorage(string: "graph TD\nA-->B\n")
    let lm = NSLayoutManager()
    let tc = NSTextContainer(size: NSSize(width: 700, height: 1e6))
    tc.lineFragmentPadding = 0
    s.addLayoutManager(lm); lm.addTextContainer(tc)
    s.addAttribute(.font, value: NSFont.systemFont(ofSize: 13),
                   range: NSRange(location: 0, length: s.length))
    configure(s, lm, tc)
    lm.ensureLayout(for: tc)
    let frag = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
    let used = lm.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
    print(String(format: "%-46@ frag.minY=%7.1f  used.minY=%7.1f  réservé=%6.1f",
                 label as NSString, frag.minY, used.minY, used.minY))
}

// Référence : ce que fait le code aujourd'hui
measure("1. paragraphSpacingBefore (code actuel)") { s, _, _ in
    let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = BAND
    s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: 8))
}

// Levier A : délégué du layout manager
final class Delegate: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ lm: NSLayoutManager,
                       paragraphSpacingBeforeGlyphAt glyphIndex: Int,
                       withProposedLineFragmentRect rect: NSRect) -> CGFloat {
        glyphIndex == 0 ? BAND : 0
    }
}
let keepAlive = Delegate()
measure("2. délégué paragraphSpacingBeforeGlyphAt") { _, lm, _ in
    lm.delegate = keepAlive
}

// Levier B : exclusionPath en haut du conteneur
measure("3. exclusionPath en haut du conteneur") { _, _, tc in
    tc.exclusionPaths = [NSBezierPath(rect: NSRect(x: 0, y: 0, width: 700, height: BAND))]
}

// Levier C : les deux combinés (délégué + style), au cas où
measure("4. délégué + paragraphSpacingBefore") { s, lm, _ in
    lm.delegate = keepAlive
    let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = BAND
    s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: 8))
}
