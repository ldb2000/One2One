import Foundation

/// `Joindre au rapport` de l'encart de clôture de 6b (spec §7.3) : un geste,
/// et tout ce que la séance a produit part dans le rapport.
///
/// Deux colonnes sont concernées, et une seule fonction les coche :
/// `Board.includeInReport` (lot 18) et `SlideCapture.includeInReport` (lot 7).
/// La règle est **idempotente** — un second clic ne change rien — et le compte
/// rendu est celui des lignes réellement modifiées, pour que l'écran sache s'il
/// doit enregistrer.
///
/// N'enregistre pas : le point d'appel a le contexte.
@MainActor
enum WorkshopReportAttachment {

    /// Le bouton primaire teal de la capture.
    static let attachLabel = "Joindre au rapport"

    /// Son état une fois tout coché. La coche fait partie du libellé : c'est le
    /// seul retour visible que le geste a porté.
    static let attachedLabel = "Joint au rapport ✓"

    /// Coche tout ce que la séance a produit et rend le nombre de lignes
    /// **changées** (`0` au second appel).
    @discardableResult
    static func attachAll(meeting: Meeting) -> Int {
        var changees = 0
        for planche in meeting.boards where !planche.includeInReport {
            planche.includeInReport = true
            changees += 1
        }
        for capture in meeting.attachments.flatMap(\.slides) where !capture.includeInReport {
            capture.includeInReport = true
            changees += 1
        }
        return changees
    }

    /// Vrai quand il y a quelque chose à joindre **et** que tout l'est.
    ///
    /// Un atelier vide n'est pas « joint » : afficher `Joint au rapport ✓` sur
    /// une séance qui n'a rien produit promettrait un contenu inexistant.
    static func isFullyAttached(meeting: Meeting) -> Bool {
        let planches = meeting.boards
        let captures = meeting.attachments.flatMap(\.slides)
        guard !planches.isEmpty || !captures.isEmpty else { return false }
        return planches.allSatisfy(\.includeInReport) && captures.allSatisfy(\.includeInReport)
    }

    /// Ce que le bouton doit afficher.
    static func buttonLabel(meeting: Meeting) -> String {
        isFullyAttached(meeting: meeting) ? attachedLabel : attachLabel
    }
}
