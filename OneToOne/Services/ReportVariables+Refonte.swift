import Foundation
import SwiftData

/// Les cinq variables de gabarit du lot 15 (plan §5, spec §8) :
/// `{{pieces_epinglees}}`, `{{captures_jointes}}`, `{{planches}}`,
/// `{{engagements}}` et `{{fiche_projet.maj}}`.
///
/// Séparées de `TemplateVariableResolver` parce qu'elles ont une dépendance que
/// les autres n'ont pas : l'**audience**, qui décide de ce que le bloc des
/// engagements laisse sortir. Les faire cohabiter aurait obligé à passer
/// l'audience à trente variables qui n'en ont que faire.
///
/// Les cases du pied du tiroir Ressources (`AttachmentReportOptions`) et la
/// case `Joindre au rapport` d'une capture pilotent l'inclusion : une variable
/// qui rendrait tout ce que la base contient, quelles que soient les cases,
/// ferait mentir le pied du tiroir.
enum RefonteReportVariables {

    /// Les noms exposés dans la palette de l'éditeur de gabarits.
    static let names: [String] = [
        "pieces_epinglees",
        "captures_jointes",
        "planches",
        "engagements",
        "fiche_projet.maj"
    ]

    /// Les blocs à appender en queue de prompt quand le corps du gabarit ne les
    /// nomme pas — avec le titre sous lequel les présenter au modèle. Même
    /// patron que les autres replis d'`assembleTemplatePrompt` : un gabarit
    /// d'avant le lot 15 doit voir les pièces épinglées de sa séance sans
    /// devoir être réédité.
    static let fallbackTitles: [(name: String, title: String)] = [
        ("pieces_epinglees", "Pièces épinglées de la séance"),
        ("captures_jointes", "Captures jointes au rapport"),
        ("planches", "Planches de la séance"),
        ("engagements", "Engagements pris dans cette séance"),
        ("fiche_projet.maj", "Mises à jour de fiche projet acceptées")
    ]

    /// Résout une des cinq variables. `nil` pour tout autre nom, ce qui laisse
    /// `TemplateVariableResolver` conclure « variable inconnue » et garder le
    /// placeholder littéral — comportement historique, à ne pas casser.
    @MainActor
    static func resolve(name: String,
                        meeting: Meeting,
                        context: ModelContext,
                        audience: Audience) -> String? {
        switch name {
        case "pieces_epinglees":
            // La case `Joindre les pièces épinglées` du pied du tiroir
            // (spec §4.1) décide : décochée, le bloc est vide, et le rapport
            // ne cite pas des pièces que l'utilisateur a écartées.
            guard meeting.reportAttachmentOptions.attachPinned else { return "" }
            return ReportOptionalBlocks.pinnedMarkdown(
                ReportOptionalBlocks.pinnedPieces(of: meeting))

        case "captures_jointes":
            return ReportOptionalBlocks.capturesMarkdown(
                ReportOptionalBlocks.captures(of: meeting))

        case "planches":
            return ReportOptionalBlocks.boardsMarkdown(
                ReportOptionalBlocks.boards(of: meeting))

        case "engagements":
            let entrees = ReportOptionalBlocks.commitments(of: meeting, in: context,
                                                            audience: audience)
            return ReportOptionalBlocks.commitmentsMarkdown(entrees)

        case "fiche_projet.maj":
            return ReportOptionalBlocks.cardUpdatesMarkdown(
                ReportOptionalBlocks.cardUpdates(of: meeting))

        default:
            return nil
        }
    }
}
