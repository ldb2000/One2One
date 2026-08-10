import SwiftUI
import SwiftData

/// Tunnel « ajouter au rapport manager » depuis une note, de bout en bout :
/// classification de catégorie, élaboration IA du texte, puis écriture via
/// `ManagerReportService.add`.
///
/// **Pourquoi une vue autonome plutôt qu'un état recopié dans chaque liste.**
/// Le tunnel est ouvert depuis deux écrans — `AllNotesView` et `NotesSection`
/// (elle-même montée sur la fiche projet et sur la fiche collaborateur). Les
/// deux n'ont besoin de rien d'autre que d'un `@State private var note: Meeting?`
/// et d'un `.sheet(item:)` : tout l'état de classification et d'élaboration,
/// les deux tâches asynchrones et la confirmation vivent ici, une seule fois.
///
/// Ce que `MeetingView` fait de son côté (`startManagerReportFlow`) ne se
/// factorise pas avec ceci : là-bas l'extrait vient d'une sélection dans un
/// transcript, avec une `NSRange`, un nom de champ source et un contexte de
/// phrase extrait autour. Une note n'a rien de tout cela — d'où
/// `sourceMeeting: nil`, `sourceField: "note"`, une plage vide et des contextes
/// vides. C'est aussi ce qui permet cette forme-ci : l'élaboration de repli
/// étant `contexte + extrait` avec des contextes vides, elle se réduit à
/// l'extrait et se calcule de façon synchrone à l'ouverture, sans que
/// l'appelant ait à préparer quoi que ce soit avant de présenter la feuille.
struct NoteManagerReportSheet: View {

    /// Note à verser au rapport manager.
    let note: Meeting
    /// Appelé à l'annulation comme à la confirmation : l'appelant remet à `nil`
    /// l'élément qui présente cette feuille.
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    @State private var suggestedCategory: String?
    @State private var isClassifying = true
    @State private var suggestedElaboration: String?
    @State private var isElaborating = true
    @State private var elaborationFromAI = false
    @State private var elaborationFallbackReason = ""

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    /// Texte soumis à l'IA et affiché en aperçu : titre + corps de la note.
    private var snippet: String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        if body.isEmpty { return title }
        return "\(title)\n\n\(body)"
    }

    /// Nom du projet de la note, à défaut celui de son premier participant :
    /// sert de contexte au classifieur de catégorie.
    private var scopeName: String? {
        note.project?.name ?? note.participants.first?.name
    }

    /// Libellé de provenance passé à l'élaboration IA.
    private var sourceTitle: String {
        if let project = note.project { return "Note projet · \(project.name)" }
        if let collaborator = note.participants.first { return "Note collaborateur · \(collaborator.name)" }
        return "Note libre"
    }

    var body: some View {
        ManagerClassificationSheet(
            snippet: snippet,
            projectName: note.project?.name,
            categories: settings.managerCategories,
            suggestedCategory: suggestedCategory,
            suggestedElaboration: suggestedElaboration,
            // Repli déterministe affiché d'emblée : contextes vides, donc
            // l'extrait lui-même (cf. `ManagerSnippetElaborator.fallback`).
            initialElaboration: ManagerSnippetElaborator.fallback(
                contextBefore: "", snippet: snippet, contextAfter: ""
            ),
            isLoadingSuggestion: isClassifying,
            isLoadingElaboration: isElaborating,
            elaborationFromAI: elaborationFromAI,
            elaborationFallbackReason: elaborationFallbackReason,
            onCancel: onFinish,
            onConfirm: { category, tag, elaboratedText, aiSuggested in
                confirm(category: category, tag: tag,
                        elaboratedText: elaboratedText, aiSuggested: aiSuggested)
            }
        )
        // Deux tâches distinctes plutôt qu'une : la catégorie et l'élaboration
        // se débloquent indépendamment, chacune dès son propre retour.
        .task { await classify() }
        .task { await elaborate() }
    }

    private func classify() async {
        let suggestion = await ManagerCategoryClassifier.classify(
            snippet: snippet,
            projectName: scopeName,
            settings: settings
        )
        suggestedCategory = suggestion
        isClassifying = false
    }

    private func elaborate() async {
        let outcome = await ManagerSnippetElaborator.elaborate(
            snippet: snippet,
            contextBefore: "",
            contextAfter: "",
            projectName: note.project?.name,
            sourceMeetingTitle: sourceTitle,
            sourceMeetingDate: note.date,
            settings: settings
        )
        switch outcome {
        case .ai(let text):
            suggestedElaboration = text
            elaborationFromAI = true
            elaborationFallbackReason = ""
        case .fallback(let text, let reason):
            suggestedElaboration = text
            elaborationFromAI = false
            elaborationFallbackReason = reason
        }
        isElaborating = false
    }

    /// Écrit l'item puis referme. `sourceMeeting: nil` et `sourceField: "note"` :
    /// la note n'est pas une réunion tenue, et le marqueur typé permettra de
    /// filtrer les extraits par provenance. Une erreur est journalisée sans
    /// bloquer la fermeture.
    private func confirm(category: String, tag: String,
                         elaboratedText: String, aiSuggested: String?) {
        do {
            _ = try ManagerReportService.add(
                snippet: snippet,
                sourceField: "note",
                range: NSRange(location: 0, length: 0),
                sourceMeeting: nil,
                contextBefore: "",
                contextAfter: "",
                elaboratedText: elaboratedText,
                category: category,
                tag: tag,
                aiSuggestedCategory: aiSuggested,
                in: context
            )
            try context.save()
        } catch {
            print("[Notes] ajout au rapport manager impossible : \(error)")
        }
        onFinish()
    }
}
