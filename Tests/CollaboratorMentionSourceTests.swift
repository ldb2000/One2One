import XCTest
import SwiftData
@testable import OneToOne

/// Caractérise `CollaboratorMentionSource` : la traduction `Collaborator`
/// (SwiftData) ↔ `MentionCandidate` (structure plate du module markdown)
/// utilisée par `MarkdownNoteEditor`/`MarkdownEditorView` pour
/// `markdownMentions(search:create:)`. Seule couche de cette fonctionnalité
/// qui touche réellement SwiftData — le reste (`MentionController`/
/// `MentionCatalog`) en est délibérément indépendant.
@MainActor
final class CollaboratorMentionSourceTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Collaborator.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - `search`

    func test_search_filtersByName_caseAndAccentInsensitive() throws {
        let context = ModelContext(try makeContainer())
        let helene = Collaborator(name: "Hélène Noël")
        let marc = Collaborator(name: "Marc Martin")
        context.insert(helene)
        context.insert(marc)

        let results = CollaboratorMentionSource.search("helene", in: [helene, marc])

        XCTAssertEqual(results.map(\.name), ["Hélène Noël"])
    }

    func test_search_emptyQuery_returnsAllProvidedCollaborators() throws {
        let context = ModelContext(try makeContainer())
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice)
        context.insert(bob)

        let results = CollaboratorMentionSource.search("", in: [alice, bob])

        XCTAssertEqual(Set(results.map(\.name)), ["Alice", "Bob"])
    }

    /// Épinglés d'abord (`pinLevel` décroissant), puis alphabétique — même
    /// tri que `SearchPopover`/`OwnerPickerMenu`.
    func test_search_sortsPinnedFirst_thenAlphabetically() throws {
        let context = ModelContext(try makeContainer())
        let zoe = Collaborator(name: "Zoé") // pinLevel 0
        let alice = Collaborator(name: "Alice") // pinLevel 0
        let marc = Collaborator(name: "Marc")
        marc.pinLevel = 2
        [zoe, alice, marc].forEach(context.insert)

        let results = CollaboratorMentionSource.search("", in: [zoe, alice, marc])

        XCTAssertEqual(results.map(\.name), ["Marc", "Alice", "Zoé"],
                       "Marc (épinglé) doit passer devant, puis ordre alphabétique entre Alice et Zoé")
    }

    func test_search_capsResultsAtEight() throws {
        let context = ModelContext(try makeContainer())
        let collaborators = (0..<20).map { Collaborator(name: "Collab \($0)") }
        collaborators.forEach(context.insert)

        let results = CollaboratorMentionSource.search("Collab", in: collaborators)

        XCTAssertEqual(results.count, 8)
    }

    /// `CollaboratorMentionSource.search` ne filtre pas lui-même les
    /// archivés : c'est le `@Query` de l'appelant (`MarkdownNoteEditor`/
    /// `MarkdownEditorView`, prédicat `!$0.isArchived`) qui en a la charge.
    /// Documente cette frontière de responsabilité plutôt que de la
    /// supposer : si un appelant futur oublie ce prédicat, ce test rend le
    /// comportement explicite (les archivés reçus sont bien renvoyés) plutôt
    /// que de le masquer par un filtrage redondant ici.
    func test_search_doesNotItselfExcludeArchivedCollaborators() throws {
        let context = ModelContext(try makeContainer())
        let archived = Collaborator(name: "Ancien Collab", isArchived: true)
        context.insert(archived)

        let results = CollaboratorMentionSource.search("Ancien", in: [archived])

        XCTAssertEqual(results.map(\.name), ["Ancien Collab"])
    }

    /// Mesure directe du caveat de migration SwiftData documenté par
    /// `Collaborator.ensuredStableID` (voir aussi la mémoire projet
    /// « SwiftData non-Optional UUID default = bombe migration ») : un
    /// collaborateur dont `stableID` est `nil` (simulé ici, cas réel d'une
    /// ligne créée avant l'ajout du champ) doit tout de même produire un
    /// `MentionCandidate.id` non-nil, backfillé — pas un crash au cast
    /// optionnel.
    func test_search_backfillsAMissingStableID_viaEnsuredStableID() throws {
        let context = ModelContext(try makeContainer())
        let legacy = Collaborator(name: "Ancien")
        legacy.stableID = nil
        context.insert(legacy)

        let results = CollaboratorMentionSource.search("Ancien", in: [legacy])

        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(legacy.stableID, "ensuredStableID doit avoir backfillé un identifiant")
    }

    // MARK: - `create`

    func test_create_insertsANewCollaborator_andReturnsAMatchingCandidate() throws {
        let context = ModelContext(try makeContainer())

        let candidate = CollaboratorMentionSource.create("Nouveau Collab", in: context)

        XCTAssertEqual(candidate?.name, "Nouveau Collab")
        let inserted = try context.fetch(FetchDescriptor<Collaborator>())
        XCTAssertEqual(inserted.map(\.name), ["Nouveau Collab"])
        XCTAssertEqual(candidate?.id, inserted.first?.ensuredStableID)
    }

    func test_create_trimsWhitespace() throws {
        let context = ModelContext(try makeContainer())
        let candidate = CollaboratorMentionSource.create("  Espacé  ", in: context)
        XCTAssertEqual(candidate?.name, "Espacé")
    }

    /// Un nom vide (une fois trimé) ne doit rien créer — ni renvoyer de
    /// candidat, ni insérer de `Collaborator` dans le contexte.
    func test_create_blankName_returnsNil_andInsertsNothing() throws {
        let context = ModelContext(try makeContainer())

        let candidate = CollaboratorMentionSource.create("   ", in: context)

        XCTAssertNil(candidate)
        let inserted = try context.fetch(FetchDescriptor<Collaborator>())
        XCTAssertTrue(inserted.isEmpty, "aucun Collaborator ne doit avoir été inséré pour un nom vide")
    }
}
