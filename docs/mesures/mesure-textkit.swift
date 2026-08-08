import AppKit

let storage = NSTextStorage(string: "Intro\ngraph TD\nA-->B\n")
let lm = NSLayoutManager()
let tc = NSTextContainer(size: NSSize(width: 700, height: 1e6))
tc.lineFragmentPadding = 0
storage.addLayoutManager(lm); lm.addTextContainer(tc)
storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13),
                     range: NSRange(location: 0, length: storage.length))

let ns = storage.string as NSString
let intro = ns.range(of: "Intro")
let first = ns.range(of: "graph TD")

// Amont : paragraphSpacing de 28 (l'écart carte de la tâche 1)
let up = NSMutableParagraphStyle(); up.paragraphSpacing = 28
storage.addAttribute(.paragraphStyle, value: up, range: intro)

// Bloc ouvert : paragraphSpacingBefore = 33 (header) + 264 (bande) + 10
let open = NSMutableParagraphStyle(); open.paragraphSpacingBefore = 33 + 264 + 10
storage.addAttribute(.paragraphStyle, value: open, range: first)

lm.ensureLayout(for: tc)
for (label, r) in [("Intro", intro), ("graph TD", first)] {
    let g = lm.glyphIndexForCharacter(at: r.location)
    let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
    let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
    print(String(format: "%-9@ frag.minY=%7.1f h=%7.1f | used.minY=%7.1f h=%6.1f",
                 label as NSString, frag.minY, frag.height, used.minY, used.height))
}

// Second cas : le bloc mermaid est le PREMIER paragraphe du conteneur
let s2 = NSTextStorage(string: "graph TD\nA-->B\n")
let lm2 = NSLayoutManager(); let tc2 = NSTextContainer(size: NSSize(width: 700, height: 1e6))
tc2.lineFragmentPadding = 0
s2.addLayoutManager(lm2); lm2.addTextContainer(tc2)
s2.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: NSRange(location: 0, length: s2.length))
s2.addAttribute(.paragraphStyle, value: open, range: (s2.string as NSString).range(of: "graph TD"))
lm2.ensureLayout(for: tc2)
let f2 = lm2.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
print(String(format: "1er paragraphe du conteneur, spacingBefore=307 -> frag.minY=%.1f h=%.1f", f2.minY, f2.height))
