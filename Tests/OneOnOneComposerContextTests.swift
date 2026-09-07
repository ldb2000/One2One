import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le composeur de la colonne centrale de la capture 2a
/// (`Écrire… /engagement /feedback /privé`) : les pilules visibles, et ce que
/// chaque ligne écrit réellement.
///
/// C'est le point que le lot 10 avait laissé ouvert (écart n° 5 : « le
/// catalogue n'est pas câblé dans le composeur »).
@Suite("Composeur 1:1 — pilules du catalogue et effets d'une ligne")
@MainActor
struct OneOnOneComposerContextTests {

    private struct Fixture {
        var thread: OneOnOneThread
        var meeting: Meeting
        var context: ModelContext
        var composer: OneOnOneComposerContext
    }

    private func fixture(role: OneOnOneSide = .manager,
                         section: NoteCommandParser.FeedbackSection = .given) throws -> Fixture {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let personne = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        context.insert(personne)
        let seance = Meeting(title: "1:1 — Laurent · 14",
                             date: RefonteDemoSeed.oneOnOneSeedDate, notes: "")
        seance.kind = OneOnOneThreadStore.meetingKind(for: role)
        context.insert(seance)
        seance.participants.append(personne)
        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))
        try context.save()

        return Fixture(thread: fil, meeting: seance, context: context,
                       composer: OneOnOneComposerContext(thread: fil, role: role,
                                                          section: section))
    }

    // MARK: - Pilules du catalogue

    @Test("Le composeur du manager affiche exactement /engagement /feedback /privé")
    func pilulesDuManager() {
        let pilules = NoteCommandCatalog.commands(for: .oneToOne, role: .manager).map(\.pill)
        #expect(pilules == ["/engagement", "/feedback", "/privé"])
    }

    @Test("Le composeur du collaborateur affiche /promesse /demande /preuve")
    func pilulesDuCollaborateur() {
        let pilules = NoteCommandCatalog.commands(for: .manager, role: .collaborator).map(\.pill)
        #expect(pilules == ["/promesse", "/demande", "/preuve"])
    }

    @Test("Les autres types gardent les quatre pilules du lot 2")
    func pilulesDesAutresTypes() {
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            let pilules = NoteCommandCatalog.commands(for: kind, role: nil).map(\.pill)
            #expect(pilules == ["/action", "/décision", "/risque", "/citer"])
        }
    }

    @Test("Le rôle prime sur le type : une réunion mal typée n'ouvre pas le composeur du manager")
    func rolePrimeSurLeType() {
        let pilules = NoteCommandCatalog.commands(for: .oneToOne, role: .collaborator).map(\.pill)
        #expect(pilules == ["/promesse", "/demande", "/preuve"])
    }

    // MARK: - Effets d'une ligne

    @Test("/engagement crée un engagement du manager, et aucune note")
    func ligneDEngagement() throws {
        let f = try fixture()
        let effet = f.composer.apply("/engagement Arbitrer renfort ou décalage du Webcast",
                                     at: 42, to: f.meeting, in: f.context)

        let engagement = try #require(effet.commitment)
        #expect(engagement.text == "Arbitrer renfort ou décalage du Webcast")
        #expect(engagement.ownerSide == .manager)
        #expect(engagement.thread?.persistentModelID == f.thread.persistentModelID)
        // Rattaché à la séance : c'est ce qui le fait apparaître dans
        // « ENGAGEMENTS DE CETTE SÉANCE » et nulle part ailleurs.
        #expect(engagement.promisedInMeeting?.persistentModelID == f.meeting.persistentModelID)
        // Aucune note : la carte du rail *est* la trace. Une note en double
        // ferait compter deux fois le même engagement dans le récap.
        #expect(effet.note == nil)
        #expect(f.meeting.timedNotes.isEmpty)
    }

    @Test("/feedback crée une note de feedback au côté de la carte")
    func ligneDeFeedback() throws {
        let f = try fixture()
        let mienne = f.composer.apply("/feedback Présentation COSUI très claire",
                                      at: 1_680, to: f.meeting, in: f.context)
        let note = try #require(mienne.note)
        #expect(note.kind == .feedback)
        #expect(note.authorSide == .me)
        #expect(note.t == 1_680)

        // La même commande dans l'autre carte attribue la parole à l'autre.
        var recu = f.composer
        recu.section = .received
        let sienne = recu.apply("/feedback Les arbitrages budget arrivent trop tard",
                                at: 1_700, to: f.meeting, in: f.context)
        #expect(sienne.note?.authorSide == .collaborator)
    }

    @Test("/privé crée une note privée, qui ne sortira d'aucun récap")
    func lignePrivee() throws {
        let f = try fixture()
        let effet = f.composer.apply("/privé Risque de départ si la mobilité n'avance pas",
                                     at: 1_050, to: f.meeting, in: f.context)
        let note = try #require(effet.note)
        #expect(note.visibility == .private)
        #expect(effet.togglesPrivacy)
        #expect(!ConfidentialityFilter.isExportable(note, for: .collaborator))
    }

    @Test("Une ligne nue prend la visibilité par défaut du rôle")
    func ligneNue() throws {
        let manager = try fixture(role: .manager)
        let partagee = manager.composer.apply("Deux migrations en parallèle",
                                              at: 160, to: manager.meeting, in: manager.context)
        // Côté manager, le récap est destiné au collaborateur : une note qu'il
        // ne verrait pas ne lui sert à rien (spec §3.2).
        #expect(partagee.note?.visibility == .shared)
        #expect(partagee.note?.kind == .note)

        let collaborateur = try fixture(role: .collaborator)
        let privee = collaborateur.composer.apply("Ce que je note pour moi", at: 10,
                                                  to: collaborateur.meeting,
                                                  in: collaborateur.context)
        #expect(privee.note?.visibility == .private)
    }

    @Test("/demande crée à la fois la note et le sujet suivi")
    func ligneDeDemande() throws {
        let f = try fixture(role: .collaborator)
        let effet = f.composer.apply("/demande Mobilité vers l'architecture", at: 300,
                                     to: f.meeting, in: f.context)
        #expect(effet.note?.kind == .request)
        let sujet = try #require(effet.agenda)
        #expect(sujet.kind == .request)
        #expect(sujet.thread?.persistentModelID == f.thread.persistentModelID)
        #expect(sujet.meeting?.persistentModelID == f.meeting.persistentModelID)
        #expect(sujet.requestedAt != nil)
    }

    @Test("Une commande sans texte n'écrit rien")
    func commandeSansTexte() throws {
        let f = try fixture()
        let effet = f.composer.apply("/engagement   ", at: 0, to: f.meeting, in: f.context)
        #expect(effet.commitment == nil)
        #expect(effet.note == nil)
        #expect(f.thread.commitments.isEmpty)
        #expect(f.meeting.timedNotes.isEmpty)

        let vide = f.composer.apply("    ", at: 0, to: f.meeting, in: f.context)
        #expect(vide.note == nil)
        #expect(f.meeting.timedNotes.isEmpty)
    }

    @Test("/action laisse la main au composeur d'actions, sans rien écrire")
    func ligneDAction() throws {
        let f = try fixture()
        let effet = f.composer.apply("/action Relire le dossier", at: 0,
                                     to: f.meeting, in: f.context)
        #expect(effet.opensActionComposer)
        #expect(effet.note == nil)
        #expect(f.meeting.timedNotes.isEmpty)
    }
}
