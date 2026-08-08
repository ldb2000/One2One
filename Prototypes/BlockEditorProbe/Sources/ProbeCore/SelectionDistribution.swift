import Foundation

/// Traduit une sélection traversante en une plage par bloc, prête à être
/// posée sur les `NSTextView`.
///
/// C'est la moitié calculable du mécanisme n°1 de la sonde ; l'autre moitié —
/// le dessin du surlignage sur un bloc qui n'a pas le focus — se vérifie à
/// l'écran.
public enum SelectionDistribution {

    /// Pour chaque index de bloc touché, la plage à surligner. Les blocs
    /// intermédiaires reçoivent leur texte entier ; les extrêmes, leur part.
    public static func ranges(for selection: ProbeSelection,
                              in document: ProbeDocument) -> [Int: NSRange] {
        let start = document.clamped(selection.start)
        let end = document.clamped(selection.end)

        if start.blockIndex == end.blockIndex {
            return [start.blockIndex: NSRange(location: start.offset,
                                              length: end.offset - start.offset)]
        }

        var ranges: [Int: NSRange] = [:]
        ranges[start.blockIndex] = NSRange(
            location: start.offset,
            length: document.blocks[start.blockIndex].length - start.offset)
        for index in (start.blockIndex + 1)..<end.blockIndex {
            ranges[index] = NSRange(location: 0, length: document.blocks[index].length)
        }
        ranges[end.blockIndex] = NSRange(location: 0, length: end.offset)
        return ranges
    }
}
