import Foundation

/// La chaîne de citation, côté rendu (spec §8 : « tout élément dérivé
/// conserve `sourceRef` avec son `t` ; le rapport rend ces références
/// cliquables »).
///
/// **Post-traitement pur, appliqué aux seuls fragments que l'app écrit
/// elle-même** — le bloc de notes, les pièces, les captures, les planches, le
/// plan d'actions. Jamais au corps markdown produit par le modèle : « le point
/// est reporté à 14:30 » est un horaire, pas une position dans
/// l'enregistrement, et le transformer en lien enverrait la tête de lecture à
/// la 870ᵉ seconde d'une séance qui n'en compte peut-être pas tant.
///
/// La reconnaissance porte donc sur le **balisage** de l'app
/// (`<code>mm:ss</code>`) et non sur le texte nu : le motif reste sûr sans
/// dépendre de l'endroit où on l'applique, et un `<code>P25_110</code>` ou un
/// `<code>12:345</code>` ne sont pas des timecodes.
enum CitationLinker {

    enum Mode {
        /// Aperçu dans l'app : liens `onetoone://` cliquables, interceptés par
        /// le délégué de navigation de `MeetingReportPreview`.
        case internalLinks(meetingStableID: UUID)
        /// PDF, mail, Apple Notes : le timecode reste du texte. Le schéma est
        /// privé — il ne vaut que sur cette machine, et un lien mort dans un
        /// compte-rendu envoyé serait pire que pas de lien.
        case plainText
    }

    /// `onetoone://meeting/<uuid>?t=252[&note=<uuid>]`
    static func url(meetingStableID: UUID, t: Double, noteStableID: UUID? = nil) -> String {
        var out = "onetoone://meeting/\(meetingStableID.uuidString)?t=\(Int(t.rounded()))"
        if let noteStableID { out += "&note=\(noteStableID.uuidString)" }
        return out
    }

    /// `04:12` → 252 ; `1:02:33` → 3753 ; autre chose → `nil`.
    ///
    /// Minutes et secondes s'écrivent sur deux chiffres et restent sous 60 ;
    /// seule la tête (heures, ou minutes en `mm:ss`) est libre. Sans cette
    /// contrainte, `12:345` passerait pour un temps.
    static func seconds(fromTimecode s: String) -> Double? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0
        for (index, part) in parts.enumerated() {
            guard let value = Int(part), value >= 0 else { return nil }
            if index > 0, part.count != 2 || value >= 60 { return nil }
            total = total * 60 + value
        }
        return Double(total)
    }

    private static let motif: NSRegularExpression = {
        // <code>, éventuellement porteur de data-note, puis mm:ss ou h:mm:ss,
        // puis </code> et une flèche déjà posée qu'on absorbe pour ne pas la
        // doubler.
        try! NSRegularExpression(
            pattern: #"<code(?:\s+data-note="([0-9A-Fa-f-]{36})")?>(\d{1,2}(?::\d{2}){1,2})</code>(\s*↗)?"#)
    }()

    /// Rend cliquables les timecodes du fragment.
    ///
    /// En `plainText`, le `<code>` disparaît avec son contenu conservé : une
    /// balise de code dans un corps de mail n'apporte rien, et les clients
    /// mail la rendent de façon imprévisible.
    static func link(_ html: String, mode: Mode) -> String {
        let ns = html as NSString
        let matches = motif.matches(in: html,
                                    range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }
        var out = html
        // À rebours : chaque substitution décale ce qui suit.
        for match in matches.reversed() {
            let courant = out as NSString
            let timecode = courant.substring(with: match.range(at: 2))
            guard let t = seconds(fromTimecode: timecode) else { continue }
            let remplacement: String
            switch mode {
            case .plainText:
                remplacement = timecode
            case .internalLinks(let meetingStableID):
                var note: UUID? = nil
                if match.range(at: 1).location != NSNotFound {
                    note = UUID(uuidString: courant.substring(with: match.range(at: 1)))
                }
                let href = url(meetingStableID: meetingStableID, t: t, noteStableID: note)
                remplacement = "<a class=\"tc\" href=\"\(href)\">\(timecode) ↗</a>"
            }
            out = courant.replacingCharacters(in: match.range, with: remplacement)
        }
        return out
    }
}
