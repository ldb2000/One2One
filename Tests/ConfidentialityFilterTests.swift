import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Un porteur de visibilité minimal : la règle ne dépend que de `visibility`,
/// pas du modèle qui la porte. Éviter d'instancier un `@Model` ici garde la
/// suite des règles indépendante de SwiftData.
private struct LigneTest: Confidential {
    let visibility: Visibility
}

@Suite("Confidentialité — la règle unique d'exportabilité")
struct ConfidentialityFilterTests {

    private func ligne(_ v: Visibility) -> LigneTest { LigneTest(visibility: v) }

    @Test("Une ligne privée ne sort que pour moi")
    func priveePourMoiSeulement() {
        let item = ligne(.private)
        #expect(ConfidentialityFilter.isExportable(item, for: .me))
        #expect(!ConfidentialityFilter.isExportable(item, for: .collaborator))
        #expect(!ConfidentialityFilter.isExportable(item, for: .manager))
        #expect(!ConfidentialityFilter.isExportable(item, for: .projectTeam))
        #expect(!ConfidentialityFilter.isExportable(item, for: .hr))
    }

    @Test("Une ligne partagée sort pour tout le monde sauf les RH")
    func partageeSaufRH() {
        let item = ligne(.shared)
        #expect(ConfidentialityFilter.isExportable(item, for: .me))
        #expect(ConfidentialityFilter.isExportable(item, for: .collaborator))
        #expect(ConfidentialityFilter.isExportable(item, for: .manager))
        #expect(ConfidentialityFilter.isExportable(item, for: .projectTeam))
        #expect(!ConfidentialityFilter.isExportable(item, for: .hr))
    }

    @Test("Une ligne escaladée sort pour moi, le manager et les RH")
    func escaladeeVersHierarchie() {
        let item = ligne(.escalated)
        #expect(ConfidentialityFilter.isExportable(item, for: .me))
        #expect(ConfidentialityFilter.isExportable(item, for: .manager))
        #expect(ConfidentialityFilter.isExportable(item, for: .hr))
        #expect(!ConfidentialityFilter.isExportable(item, for: .collaborator))
        #expect(!ConfidentialityFilter.isExportable(item, for: .projectTeam))
    }

    @Test("Seules les lignes privées échappent à l'indexation RAG")
    func indexationHorsPrive() {
        #expect(!ConfidentialityFilter.isIndexable(ligne(.private)))
        #expect(ConfidentialityFilter.isIndexable(ligne(.shared)))
        #expect(ConfidentialityFilter.isIndexable(ligne(.escalated)))
    }

    @Test("L'audience d'une réunion se déduit de son type")
    func audienceParType() {
        #expect(ConfidentialityFilter.audience(for: .oneToOne) == .collaborator)
        #expect(ConfidentialityFilter.audience(for: .manager) == .manager)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(ConfidentialityFilter.audience(for: kind) == .projectTeam)
        }
    }

    @Test("Les valeurs brutes de visibilité sont celles de la spécification")
    func valeursBrutes() {
        #expect(Visibility.private.rawValue == "private")
        #expect(Visibility.shared.rawValue == "shared")
        #expect(Visibility.escalated.rawValue == "escalated")
        #expect(Visibility.allCases.count == 3)
    }
}

@Suite("Chaîne de citation — SourceRef sur trois colonnes plates")
@MainActor
struct SourceRefTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("Les valeurs brutes des types de source sont celles de la spécification")
    func valeursBrutes() {
        #expect(SourceRef.Kind.transcript.rawValue == "transcript")
        #expect(SourceRef.Kind.note.rawValue == "note")
        #expect(SourceRef.Kind.capture.rawValue == "capture")
        #expect(SourceRef.Kind.board.rawValue == "board")
    }

    @Test("Écrit puis relu, un sourceRef d'action traverse les trois colonnes")
    func allerRetourSurAction() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = ActionTask(title: "Rappeler le prestataire")
        context.insert(task)

        #expect(task.sourceRef == nil)

        let id = UUID()
        task.sourceRef = SourceRef(kind: .transcript, stableID: id, t: 252)
        try context.save()

        #expect(task.sourceKindRaw == "transcript")
        #expect(task.sourceStableID == id)
        #expect(task.sourceT == 252)
        #expect(task.sourceRef == SourceRef(kind: .transcript, stableID: id, t: 252))

        task.sourceRef = nil
        #expect(task.sourceKindRaw == nil)
        #expect(task.sourceStableID == nil)
        #expect(task.sourceT == nil)
    }

    @Test("Une note horodatée porte le même accesseur")
    func allerRetourSurNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let note = MeetingNote(t: 12, text: "Cité depuis la capture")
        context.insert(note)

        let id = UUID()
        note.sourceRef = SourceRef(kind: .capture, stableID: id, t: nil)
        try context.save()

        #expect(note.sourceRef?.kind == .capture)
        #expect(note.sourceRef?.t == nil)
        #expect(note.sourceStableID == id)
    }
}

/// **Critère d'acceptation du chantier 2, n° 1** (spec) : « une note privée
/// n'apparaît dans aucun export, rapport, récap ou réponse d'assistant : test
/// automatisé obligatoire ».
///
/// Cinq lecteurs de texte existent dans l'app, écrits à cinq endroits
/// différents. Ce test les appelle **tous les cinq** sur la même réunion : un
/// sixième lecteur ajouté sans passer par `ConfidentialityFilter` ne serait pas
/// couvert ici, mais tout changement dans l'un de ces cinq le sera.
/// Aucun appel réseau ni MLX : les cinq seams sont des fonctions pures ou des
/// constructeurs de chaîne.
@Suite("Confidentialité — une note privée ne sort par aucun des cinq flux")
@MainActor
struct NotePriveeHorsDesCinqFluxTests {

    // Deux textes **sans caractère échappable** (ni apostrophe, ni chevron) :
    // le flux HTML échappe le contenu, un `contains` sur une chaîne
    // apostrophée échouerait pour une raison qui n'a rien à voir avec la
    // confidentialité.
    private static let textePrive = "Salaire : augmentation refusée par la DRH"
    private static let textePartage = "Point architecture sur le socle CI-CD"

    private func makeReunion(kind: MeetingKind = .oneToOne) throws -> (Meeting, ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let reunion = Meeting(title: "1:1 Awa Diallo", date: Date(timeIntervalSince1970: 1_700_000_000))
        reunion.kind = kind
        reunion.summary = "Compte-rendu généré."
        reunion.mergedTranscript = "Transcription de la séance."
        context.insert(reunion)

        let privee = MeetingNote(t: 30, text: Self.textePrive, kind: .note, visibility: .private)
        privee.meeting = reunion
        context.insert(privee)

        let partagee = MeetingNote(t: 252, text: Self.textePartage, kind: .decision, visibility: .shared)
        partagee.meeting = reunion
        context.insert(partagee)

        try context.save()
        return (reunion, context)
    }

    @Test("1. Le prompt de génération de rapport")
    func fluxPromptDeRapport() throws {
        let (reunion, context) = try makeReunion()
        let prompt = AIReportService.assembleTemplatePrompt(meeting: reunion, in: context)
        #expect(prompt.contains(Self.textePartage))
        #expect(!prompt.contains(Self.textePrive))
    }

    @Test("2. Le rapport HTML")
    func fluxHTML() throws {
        let (reunion, _) = try makeReunion()
        let html = ReportHTMLBuilder.build(meeting: reunion, template: nil, includeTranscript: true)
        #expect(html.contains(Self.textePartage))
        #expect(!html.contains(Self.textePrive))
    }

    @Test("3. L'export markdown")
    func fluxExportMarkdown() throws {
        let (reunion, _) = try makeReunion()
        let markdown = ExportService().exportMeetingMarkdown(meeting: reunion)
        #expect(markdown.contains(Self.textePartage))
        #expect(!markdown.contains(Self.textePrive))
    }

    @Test("4. Le texte source de l'indexation RAG")
    func fluxIndexationRAG() throws {
        let (reunion, _) = try makeReunion()
        let source = RAGIndexer.sourceText(for: reunion)
        #expect(source.contains(Self.textePartage))
        #expect(!source.contains(Self.textePrive))
    }

    @Test("5. Le contexte du chat de réunion")
    func fluxChatDeReunion() throws {
        let (reunion, _) = try makeReunion()
        let prompt = MeetingChatView(meeting: reunion)
            .makePrompt(question: "Que retenir ?", historicalContext: "", history: "")
        #expect(prompt.contains(Self.textePartage))
        #expect(!prompt.contains(Self.textePrive))
    }

    @Test("5 bis. Le contexte de base du chatbot général")
    func fluxContexteChatbot() throws {
        let (reunion, _) = try makeReunion()
        let bloc = MeetingNoteStore.contextBlock(for: reunion, audience: .projectTeam)
        #expect(bloc.contains(Self.textePartage))
        #expect(!bloc.contains(Self.textePrive))
        // `ChatbotView.buildDatabaseContext` assemble ses lignes de réunion à
        // partir de ce bloc : le vérifier ici garde le test sans environnement
        // SwiftUI complet (la vue exige des `@Query`).
        #expect(ChatbotView.meetingNotesContext(for: reunion).contains(Self.textePartage))
        #expect(!ChatbotView.meetingNotesContext(for: reunion).contains(Self.textePrive))
    }

    /// Une ligne escaladée n'est pas une ligne partagée : elle ne doit pas
    /// atterrir dans le récap destiné au collaborateur.
    @Test("Une ligne escaladée reste hors du rapport d'un 1:1 côté manager")
    func ligneEscaladeeHorsRecapCollaborateur() throws {
        let (reunion, context) = try makeReunion()
        let escaladee = MeetingNote(t: 400, text: "À remonter aux RH", visibility: .escalated)
        escaladee.meeting = reunion
        context.insert(escaladee)
        try context.save()

        let prompt = AIReportService.assembleTemplatePrompt(meeting: reunion, in: context)
        #expect(!prompt.contains("À remonter aux RH"))
        #expect(ConfidentialityFilter.audience(for: .oneToOne) == .collaborator)
    }

    /// Sur une réunion projet, l'audience est l'équipe : les notes partagées
    /// sortent, les privées non — la règle ne dépend pas du type de réunion.
    @Test("Sur une réunion projet, seule la ligne partagée sort")
    func reunionProjet() throws {
        let (reunion, context) = try makeReunion(kind: .project)
        let prompt = AIReportService.assembleTemplatePrompt(meeting: reunion, in: context)
        #expect(prompt.contains(Self.textePartage))
        #expect(!prompt.contains(Self.textePrive))
    }
}
