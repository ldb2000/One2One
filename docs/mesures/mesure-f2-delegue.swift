import AppKit
let BAND: CGFloat = 307

final class ZeroElsewhere: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ lm: NSLayoutManager, paragraphSpacingBeforeGlyphAt g: Int,
                       withProposedLineFragmentRect r: NSRect) -> CGFloat { 0 }
}
final class PassThrough: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ lm: NSLayoutManager, paragraphSpacingBeforeGlyphAt g: Int,
                       withProposedLineFragmentRect r: NSRect) -> CGFloat {
        guard let s = lm.textStorage else { return 0 }
        let c = lm.characterIndexForGlyph(at: g)
        guard c < s.length,
              let p = s.attribute(.paragraphStyle, at: c, effectiveRange: nil) as? NSParagraphStyle
        else { return 0 }
        return p.paragraphSpacingBefore
    }
}
let zero = ZeroElsewhere(), pass = PassThrough()

// « Intro » puis un bloc mermaid : le bloc N'EST PAS en tête.
func run(_ label: String, delegate: NSLayoutManagerDelegate?) {
    let s = NSTextStorage(string: "Intro\ngraph TD\n")
    let lm = NSLayoutManager(); let tc = NSTextContainer(size: NSSize(width: 700, height: 1e6))
    tc.lineFragmentPadding = 0
    s.addLayoutManager(lm); lm.addTextContainer(tc)
    s.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: NSRange(location: 0, length: s.length))
    let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = BAND
    let r = (s.string as NSString).range(of: "graph TD")
    s.addAttribute(.paragraphStyle, value: p, range: r)
    lm.delegate = delegate
    lm.ensureLayout(for: tc)
    let g = lm.glyphIndexForCharacter(at: r.location)
    let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
    let intro = lm.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
    print(String(format: "%-42@ bande réservée = %6.1f", label as NSString, used.minY - intro.maxY))
}
run("aucun délégué (attribut seul)", delegate: nil)
run("délégué renvoyant 0 ailleurs", delegate: zero)
run("délégué passe-plat (relit l'attribut)", delegate: pass)
