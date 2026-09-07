import Foundation

/// Le fil d'Ariane de la barre du haut, **hors de la vue** — le support du
/// critère d'acceptation chantier 5 n° 1 : « le rôle est visible en permanence ;
/// on ne peut pas confondre un 1:1 mené et un 1:1 subi ».
///
/// Pourquoi un modèle et non une inspection de vue : la pilule `Je suis le
/// collaborateur` est **obligatoire** (D4). Une vérification à l'œil sur une
/// capture ne dit pas si elle est masquée quand la fenêtre rétrécit, ni si un
/// futur réglage peut l'éteindre. Ici la liste des segments se déduit du **seul
/// type de réunion** : aucune largeur, aucun état d'écran, aucun réglage
/// n'entre dans le calcul, et le test le prouve.
///
/// Les libellés ne sont pas recopiés : ils viennent des statiques de
/// `MeetingTopChromeBar`, celles-là même que la barre rend. Un modèle qui
/// porterait ses propres chaînes pourrait rester vert alors que l'écran a
/// changé.
enum CollaboratorTopBarModel {

    /// Les segments du fil d'Ariane, dans l'ordre d'affichage, `One2One`
    /// compris.
    ///
    /// Le segment projet n'y figure pas : un tête-à-tête n'a pas de projet, et
    /// la barre le rend depuis `meeting.project`, qui n'est pas une fonction du
    /// type.
    static func breadcrumbSegments(for kind: MeetingKind) -> [String] {
        var segments = ["One2One"]
        if let equipe = MeetingTopChromeBar.teamSegmentLabel(for: kind) {
            segments.append(equipe)
        }
        if let miens = MeetingTopChromeBar.myOneOnOnesSegmentLabel(for: kind) {
            segments.append(miens)
        }
        if let badge = MeetingTopChromeBar.typeBadge(for: kind) {
            segments.append(badge)
        }
        if let role = MeetingTopChromeBar.collaboratorPillLabel(for: kind) {
            segments.append(role)
        }
        return segments
    }
}
