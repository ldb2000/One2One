import Foundation

/// Tout ce que la bande de captures **décide** (spec §5.3, capture 4a) : ordre
/// des vignettes, légende `mm:ss · auto|⌘⇧S|2 min`, titre d'une capture, invite
/// de bande vide, lignes de la colonne d'état.
///
/// Fonctions pures, hors de la vue : une légende qui annoncerait `auto` sur une
/// capture manuelle est un défaut invisible à la relecture d'un `switch` noyé
/// dans du dessin.
@MainActor
enum CaptureStripModel {

    /// Les captures dans l'ordre du temps : par `t` quand il existe, par index
    /// sinon. L'ordre d'une relation SwiftData n'est pas garanti, et deux vues
    /// qui trient chacune de leur côté finissent par trier différemment.
    static func sorted(_ captures: [SlideCapture]) -> [SlideCapture] {
        captures.sorted { gauche, droite in
            switch (gauche.t, droite.t) {
            case let (tg?, td?) where tg != td: return tg < td
            case (.some, .none): return true
            case (.none, .some): return false
            default: return gauche.index < droite.index
            }
        }
    }

    /// La légende sous la vignette : `04:12 · auto`, `12:08 · ⌘⇧S`,
    /// `08:55 · 2 min`.
    ///
    /// Le cas périodique affiche l'**intervalle réel** plutôt que le mot
    /// « périodique » : la bande est la seule à connaître le réglage.
    /// Sans `t`, le timecode est `--:--` : une capture faite hors
    /// enregistrement n'a pas eu lieu à `00:00`.
    static func legend(for capture: SlideCapture, interval: Duration?) -> String {
        let timecode = capture.t.map { MeetingPlayhead.mmss($0) } ?? "--:--"
        return "\(timecode) · \(triggerLabel(for: capture, interval: interval))"
    }

    /// Le mot du déclencheur : `auto`, `⌘⇧S`, ou l'intervalle réel.
    static func triggerLabel(for capture: SlideCapture, interval: Duration?) -> String {
        guard capture.trigger == .interval else { return capture.trigger.label }
        guard let interval else { return capture.trigger.label }
        let minutes = Int(interval.components.seconds) / 60
        return minutes > 0 ? "\(minutes) min" : "\(Int(interval.components.seconds)) s"
    }

    /// Le titre d'une capture, tel que la carte insérée dans une note et la
    /// colonne d'état l'affichent : `Capture 12:08 — tableau de chiffrage`.
    ///
    /// La partie descriptive vient de la **première ligne d'OCR**, tronquée :
    /// c'est ce que la capture 4a montre, et c'est la seule description dont on
    /// dispose sans demander à l'utilisateur de nommer chaque vignette.
    static func title(for capture: SlideCapture, maxLength: Int = 40) -> String {
        let base = capture.t.map { "Capture \(MeetingPlayhead.mmss($0))" } ?? "Capture \(capture.index)"
        guard let premiere = firstOCRLine(of: capture) else { return base }
        return "\(base) — \(truncate(premiere, to: maxLength))"
    }

    /// La première ligne utile de l'OCR, `nil` si l'OCR n'a rien donné (la
    /// capture reste utilisable sans texte, spec §5.3).
    static func firstOCRLine(of capture: SlideCapture) -> String? {
        capture.ocrText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// Le texte extrait, en une phrase, pour la carte de note : `Texte
    /// extrait : « … »`.
    static func extractedTextLine(of capture: SlideCapture, maxLength: Int = 80) -> String? {
        guard let premiere = firstOCRLine(of: capture) else { return nil }
        return "Texte extrait : « \(truncate(premiere, to: maxLength)) »"
    }

    private static func truncate(_ texte: String, to maxLength: Int) -> String {
        guard texte.count > maxLength else { return texte }
        return texte.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Colonne d'état

    /// Une ligne de la colonne d'état, à droite des vignettes (capture 4a :
    /// `✓ Texte extrait et cherchable`, `✓ Rattaché au timecode de la note`,
    /// `○ Joindre au rapport`).
    struct StatusLine: Identifiable, Equatable, Sendable {
        enum Mark: Equatable, Sendable {
            /// `✓` — le fait est acquis.
            case done
            /// `○` — une case à cocher, l'utilisateur décide.
            case toggle
            /// `–` — le fait n'est pas acquis et ne dépend pas de l'utilisateur.
            case missing
        }
        var id: String { label }
        let mark: Mark
        let label: String
    }

    /// L'état de la capture sélectionnée. Chaque ligne dit la **vérité** : une
    /// capture dont l'OCR n'a rien rendu n'annonce pas un texte cherchable, et
    /// une capture sans `t` n'annonce pas un rattachement au timecode.
    static func statusLines(for capture: SlideCapture?) -> [StatusLine] {
        guard let capture else { return [] }
        let aDuTexte = firstOCRLine(of: capture) != nil
        return [
            StatusLine(mark: aDuTexte ? .done : .missing,
                       label: aDuTexte ? "Texte extrait et cherchable" : "Aucun texte extrait"),
            StatusLine(mark: capture.t != nil ? .done : .missing,
                       label: capture.t != nil
                           ? "Rattaché au timecode de la note"
                           : "Aucun timecode (capture hors séance)"),
            StatusLine(mark: capture.includeInReport ? .done : .toggle,
                       label: "Joindre au rapport")
        ]
    }

    // MARK: - Bande vide

    /// L'invite d'une bande vide, **par type de réunion** : « jamais un écran
    /// vide » (spec §1.1), et l'attente n'est pas la même selon que la
    /// détection tourne ou non.
    static func emptyInvite(kind: MeetingKind, detectsAutomatically: Bool, hasSource: Bool) -> String {
        guard hasSource else {
            return "Aucune capture — choisissez la fenêtre à lire, puis ⌘⇧S."
        }
        guard detectsAutomatically else {
            return "Aucune capture — ⌘⇧S capture ce qui est à l'écran. \(kind.captureHint)"
        }
        switch kind {
        case .workshop:
            return "Aucune capture — la planche est capturée toutes les 2 minutes, ou à la demande avec ⌘⇧S."
        case .work:
            return "Aucune capture — la première arrive dès qu'un schéma se stabilise."
        default:
            return "Aucune capture — la première arrive dès qu'un partage se stabilise."
        }
    }
}
