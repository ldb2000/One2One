import Foundation

/// Le résumé court d'une réunion (`meeting.shortSummary`), généré à la demande
/// par le modèle configuré dans les Réglages.
///
/// Ces deux fonctions vivaient dans `SummaryCard`, la carte « Résumé » du
/// dashboard. Le lot 19 retire ce dashboard, que plus aucun écran ne monte
/// depuis la refonte (décision D8) ; ses deux fonctions statiques, elles, sont
/// les seules définitions du « texte de la réunion » et du « résumé court » de
/// l'application — le mode Relire (`MeetingLiveSpace`, `OneSentenceCard`) et
/// `MeetingView` les appellent. Elles emménagent donc dans un service, plutôt
/// que de garder en vie une vue morte pour ses membres statiques.
///
/// `enum` sans cas : un espace de noms de fonctions pures, la convention de
/// `Services/` (cf. CLAUDE.md).
enum MeetingSummaryService {

    /// La source du résumé : transcript fusionné, sinon brut. Une seule
    /// définition pour toute l'application — deux finiraient par produire deux
    /// résumés différents. Pas de repli sur les notes live.
    static func transcriptSource(for meeting: Meeting) -> String {
        meeting.mergedTranscript.isEmpty ? meeting.rawTranscript : meeting.mergedTranscript
    }

    /// Écrit `meeting.shortSummary`. Ne sauvegarde pas : l'appelant décide
    /// quand persister.
    ///
    /// Sans texte à résumer, ne fait rien plutôt que d'appeler le modèle pour
    /// rien.
    @MainActor
    static func generate(meeting: Meeting, settings: AppSettings) async throws {
        let source = transcriptSource(for: meeting)
        guard !source.isEmpty else { return }
        let prompt = """
        Résume la réunion suivante en 10 lignes maximum, en français, sous forme de \
        puces concises. Va à l'essentiel : sujets abordés, décisions, actions à suivre. \
        Ne réponds qu'avec le résumé, sans préambule.

        \(source)
        """
        let result = try await AIClient.send(prompt: prompt, settings: settings)
        meeting.shortSummary = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
