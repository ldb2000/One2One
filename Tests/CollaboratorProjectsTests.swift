import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// « Chaque collaborateur a un rôle — Chef de Projet, Architecte Technique,
/// Développeur. Ils ont une implication dans les projets avec une
/// participation et des actions assignées. » — règle de l'auteur, 2026-08-13.
///
/// Le rôle est un attribut de **la personne**, pas une désignation par projet.
/// C'est pourquoi `Project.projectManager` et `Project.technicalArchitect` sont
/// vides sur 62 des 63 projets : ce n'est pas ainsi que l'organisation est
/// pensée. L'implication se lit donc sur les réunions et les actions.
@Suite("Projets d'un collaborateur — participation et actions assignées")
struct CollaboratorProjectsTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func projet(_ context: ModelContext, _ code: String) -> Project {
        let p = Project(code: code, name: "Projet \(code)", domain: "Courtage", phase: "Build")
        context.insert(p)
        return p
    }

    @Test("Une réunion de projet compte")
    func meetingCounts() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let p = projet(context, "P25_100")
        let m = Meeting(title: "Comité", date: Date())
        m.kind = .project
        m.project = p
        m.participants = [alice]
        context.insert(m)

        #expect(CollaboratorProjects.involved(in: alice).map(\.code) == ["P25_100"])
    }

    @Test("Une action assignée compte, même sans réunion")
    func assignedActionCounts() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let p = projet(context, "P25_200")
        let t = ActionTask(title: "Cadrer")
        t.collaborator = alice
        t.project = p
        context.insert(t)

        #expect(CollaboratorProjects.involved(in: alice).map(\.code) == ["P25_200"])
    }

    @Test("Un projet vu des deux côtés n'est compté qu'une fois")
    func noDuplicates() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let p = projet(context, "P25_300")
        let m = Meeting(title: "Comité", date: Date())
        m.project = p; m.participants = [alice]; context.insert(m)
        let t = ActionTask(title: "Suivre"); t.collaborator = alice; t.project = p
        context.insert(t)

        #expect(CollaboratorProjects.involved(in: alice).count == 1)
    }

    /// Le bloc n'affiche que quatre lignes : les plus récentes doivent y être.
    @Test("Les projets sortent du plus récemment fréquenté au plus ancien")
    func mostRecentFirst() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let vieux = projet(context, "P24_ANCIEN")
        let recent = projet(context, "P25_RECENT")
        for (p, jours) in [(vieux, 300.0), (recent, 3.0)] {
            let m = Meeting(title: "Point", date: Date(timeIntervalSinceNow: -jours * 86_400))
            m.project = p; m.participants = [alice]; context.insert(m)
        }

        #expect(CollaboratorProjects.involved(in: alice).map(\.code) == ["P25_RECENT", "P24_ANCIEN"])
    }

    /// Une note est une réunion avec soi-même : elle ne dit rien d'une
    /// implication dans un projet partagé.
    @Test("Une note rattachée à un projet ne vaut pas implication")
    func noteDoesNotCount() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let p = projet(context, "P25_400")
        let note = NoteFactory.make(body: "Pense-bête", project: p, collaborator: alice)
        context.insert(note)

        #expect(CollaboratorProjects.involved(in: alice).isEmpty)
    }
}
