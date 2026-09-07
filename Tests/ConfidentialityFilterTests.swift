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
