import SwiftUI

extension MeetingKPI.Level {
    /// Teinte canonique d'un niveau de risque, pour les quatre écrans qui en
    /// dessinent un point : bandeau d'indicateurs (spec §2.3), onglet Risques
    /// du rail, fiche projet (§4.3), nav du mode Relire.
    ///
    /// La maquette n'emploie que deux accents : `report` pour ce qui alerte,
    /// `warn` pour ce qui se surveille. Le faible n'est pas un accent, c'est un
    /// neutre — `ink/4`. Et le bleu `action` est la couleur des **actions** :
    /// l'employer pour un risque modéré, comme le faisait `MeetingKPIBand`,
    /// faisait lire un risque comme une action (écart (c) n° 6 de la recette
    /// des vagues 1–4, où le bandeau sortait « rouge, rouge, orange, bleu,
    /// gris » là où la maquette n'a que du rouge et de l'orange).
    ///
    /// Une seule table : `MeetingKPIBand.teinte(_:)`, `ActionsRailRisks.teinte(_:)`
    /// et `ProjectCardPanel.color(for:)` n'en sont plus que des façades — leurs
    /// appelants ne changent pas, et `Tests/RefonteFinitionsTests.swift`
    /// vérifie qu'ils rendent bien la même couleur.
    var teinte: Color {
        switch self {
        case .critique, .eleve: return One2OneToken.report
        case .modere:           return One2OneToken.warn
        case .faible:           return One2OneToken.ink4
        }
    }
}
