import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le critère d'acceptation chantier 5 **n° 2** : « aucune note du
/// collaborateur ne devient visible du manager sans un geste explicite sur
/// cette ligne ».
///
/// Deux moitiés, testées séparément : le **défaut** (toute ligne écrite côté
/// collaborateur naît `private`, quel que soit le chemin d'écriture) et le
/// **geste** (`Partager la ligne` ne touche qu'une ligne, jamais la séance).
@Suite("Écran 5a — aucune ligne partagée sans geste explicite (critère n° 2)")
@MainActor
struct CollaboratorNotePrivacyTests {

    static let seance = Date(timeIntervalSince1970: 1_788_506_100)

    private func makeFil() throws -> (context: ModelContext,
                                      fil: OneOnOneThread,
                                      seance: Meeting) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let yann = Collaborator(name: "Yann PENVEN", role: "Manager")
        context.insert(yann)
        let seance = Meeting(title: "1:1 avec Yann · 4", date: Self.seance, notes: "")
        seance.kind = .manager
        context.insert(seance)
        seance.participants.append(yann)
        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))
        try context.save()
        return (context, fil, seance)
    }

    // MARK: - Le défaut

    @Test("Le défaut de l'écran est `private`, et c'est celui du rôle")
    func defautPrive() {
        #expect(CollaboratorNotePrivacy.defaultVisibility == .private)
        #expect(OneOnOneConfidentiality.defaultVisibility(for: .collaborator) == .private)
    }

    @Test("Une ligne écrite au composeur naît privée, sans que l'écran s'en mêle")
    func ligneDuComposeurNaitPrivee() throws {
        let (context, fil, seance) = try makeFil()
        let contexte = OneOnOneComposerContext(thread: fil, role: .collaborator)

        let simple = contexte.apply("Posé les 3 j-h de reprise non prévus",
                                    at: 400, to: seance, in: context)
        #expect(simple.note?.visibility == .private)

        // `/promesse` : la note **et** l'engagement du manager naissent privés.
        let promesse = contexte.apply("/promesse Grille de compensation des astreintes",
                                      at: 545, to: seance, in: context)
        #expect(promesse.note?.visibility == .private)
        #expect(promesse.commitment?.visibility == .private)
        #expect(promesse.commitment?.ownerSide == .manager)

        // `/demande` : la note et la demande suivie naissent privées.
        let demande = contexte.apply("/demande Mobilité vers l'architecture",
                                     at: 900, to: seance, in: context)
        #expect(demande.note?.visibility == .private)
        #expect(demande.agenda?.visibility == .private)
        #expect(demande.agenda?.kind == .request)

        // `/preuve` : une preuve citée reste privée jusqu'au geste de partage.
        let preuve = contexte.apply("/preuve Reprise du périmètre Nexus close le 29 août",
                                    at: 950, to: seance, in: context)
        #expect(preuve.note?.visibility == .private)
        #expect(preuve.note?.kind == .proof)

        // Bilan : rien de partagé dans toute la séance.
        #expect(CollaboratorNotePrivacy.sharedCount(seance.timedNotes) == 0)
    }

    @Test("Un sujet ajouté à la main naît privé")
    func sujetNaitPrive() throws {
        let (context, fil, seance) = try makeFil()
        let sujet = try #require(ManagerAgendaModel.add("Porter la formation Admin",
                                                        for: seance, in: fil,
                                                        role: .collaborator, in: context))
        #expect(sujet.visibility == .private)
    }

    @Test("Les trois commandes du composeur sont celles du côté collaborateur")
    func commandesDuComposeur() {
        let pilules = NoteCommandCatalog.commands(for: .manager, role: .collaborator)
        #expect(pilules.map(\.pill) == ["/promesse", "/demande", "/preuve"])
    }

    // MARK: - Le geste

    @Test("`Partager la ligne` ne change qu'une ligne")
    func partagerUneSeuleLigne() throws {
        let (context, _, seance) = try makeFil()
        var notes: [MeetingNote] = []
        for (rang, texte) in ["Première", "Deuxième", "Troisième"].enumerated() {
            let note = MeetingNote(t: Double(rang) * 100, text: texte,
                                   visibility: .private, orderIndex: rang)
            context.insert(note)
            note.meeting = seance
            notes.append(note)
        }
        try context.save()

        #expect(CollaboratorNotePrivacy.shareLine(notes[1], in: context))

        #expect(notes[0].visibility == .private)
        #expect(notes[1].visibility == .shared)
        #expect(notes[2].visibility == .private)
        #expect(CollaboratorNotePrivacy.sharedCount(seance.timedNotes) == 1)
    }

    @Test("Partager deux fois la même ligne ne partage pas la suivante")
    func partageIdempotent() throws {
        let (context, _, seance) = try makeFil()
        let note = MeetingNote(t: 0, text: "Assumée", visibility: .private)
        context.insert(note)
        note.meeting = seance
        let autre = MeetingNote(t: 10, text: "Gardée", visibility: .private)
        context.insert(autre)
        autre.meeting = seance
        try context.save()

        #expect(CollaboratorNotePrivacy.shareLine(note, in: context))
        // Deuxième appel : déjà partagée, rien à faire, et surtout aucun effet
        // de bord sur la ligne voisine.
        #expect(!CollaboratorNotePrivacy.shareLine(note, in: context))
        #expect(autre.visibility == .private)
    }

    @Test("Une ligne escaladée ne devient jamais partagée par ce geste")
    func ligneEscaladeeProtegee() throws {
        let (context, _, seance) = try makeFil()
        let note = MeetingNote(t: 0, text: "À monter au N+1", visibility: .escalated)
        context.insert(note)
        note.meeting = seance
        try context.save()

        // D9 : une ligne montée à la hiérarchie ne redescend pas vers le
        // manager par un aller-retour de bascule.
        #expect(!CollaboratorNotePrivacy.shareLine(note, in: context))
        #expect(note.visibility == .escalated)
    }

    @Test("Une ligne partagée sort vers le manager, une ligne privée non")
    func effetDuGesteSurLeRecap() throws {
        let (context, _, seance) = try makeFil()
        let privee = MeetingNote(t: 0, text: "Je regarde ailleurs", visibility: .private)
        context.insert(privee)
        privee.meeting = seance
        let partagee = MeetingNote(t: 10, text: "Les 3 j-h de reprise", visibility: .private)
        context.insert(partagee)
        partagee.meeting = seance
        try context.save()

        CollaboratorNotePrivacy.shareLine(partagee, in: context)

        let sortantes = MeetingNoteStore.exportable(seance.timedNotes, for: .manager)
        #expect(sortantes.map(\.text) == ["Les 3 j-h de reprise"])
    }
}
