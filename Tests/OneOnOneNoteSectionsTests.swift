import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les trois temps de la colonne centrale de la capture 2a (spec §3.3 :
/// `① COMMENT ÇA VA`, `② SES SUJETS`, `③ FEEDBACK — DANS LES DEUX SENS`) et
/// l'indicateur « 1:1 complet ».
@Suite("Notes du 1:1 — les trois sections et la complétude")
@MainActor
struct OneOnOneNoteSectionsTests {

    private func reunion() throws -> (Meeting, ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let seance = Meeting(title: "1:1 — Laurent · 14",
                             date: RefonteDemoSeed.oneOnOneSeedDate,
                             notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        try context.save()
        return (seance, context)
    }

    @discardableResult
    private func note(_ t: Double,
                      _ texte: String,
                      kind: MeetingNoteKind = .note,
                      visibility: Visibility = .shared,
                      author: MeetingSide = .me,
                      in seance: Meeting,
                      _ context: ModelContext) -> MeetingNote {
        let ligne = MeetingNote(t: t, text: texte, kind: kind,
                                visibility: visibility, authorSide: author)
        context.insert(ligne)
        ligne.meeting = seance
        try? context.save()
        return ligne
    }

    /// Les six lignes de la capture 2a, aux timecodes de la capture.
    private func captureNotes(in seance: Meeting, _ context: ModelContext) {
        note(160, "Deux migrations en parallèle + astreinte. À surveiller.", in: seance, context)
        note(375, "Charge AP — estime 3 j-h de reprise non prévus.",
             author: .collaborator, in: seance, context)
        note(782, "Formation Admin — veut la porter et l'animer.",
             author: .collaborator, in: seance, context)
        note(1_050, "Risque de départ si la mobilité archi n'avance pas.",
             visibility: .private, in: seance, context)
        note(1_680, "Présentation COSUI très claire.", kind: .feedback, in: seance, context)
        note(1_700, "Les arbitrages budget arrivent trop tard.",
             kind: .feedback, author: .collaborator, in: seance, context)
    }

    // MARK: - Répartition

    @Test("Les libellés des trois sections sont ceux de la capture")
    func libelles() {
        #expect(OneOnOneNoteSections.Section.howAreYou.label == "① COMMENT ÇA VA")
        #expect(OneOnOneNoteSections.Section.topics.label == "② SES SUJETS")
        #expect(OneOnOneNoteSections.Section.feedback.label == "③ FEEDBACK — DANS LES DEUX SENS")
        #expect(OneOnOneNoteSections.Section.allCases.count == 3)
    }

    @Test("La capture 2a se range en 1 + 3 + 2 lignes")
    func repartitionDeLaCapture() throws {
        let (seance, context) = try reunion()
        captureNotes(in: seance, context)

        // ① : la première ligne de la séance est la réponse à la question
        // posée — c'est la règle, documentée dans le service.
        let comment = OneOnOneNoteSections.notes(seance, in: .howAreYou)
        #expect(comment.map(\.t) == [160])

        // ② : les sujets, dont la note privée à 17:30.
        let sujets = OneOnOneNoteSections.notes(seance, in: .topics)
        #expect(sujets.map(\.t) == [375, 782, 1_050])
        #expect(sujets.contains { $0.visibility == .private })

        // ③ : les deux feedbacks, quel que soit leur timecode.
        let feedback = OneOnOneNoteSections.notes(seance, in: .feedback)
        #expect(feedback.map(\.t) == [1_680, 1_700])
        #expect(feedback.allSatisfy { $0.kind == .feedback })
    }

    @Test("Une décision ou un risque tapé en 1:1 reste un sujet")
    func naturesInattendues() throws {
        let (seance, context) = try reunion()
        note(10, "Première ligne", in: seance, context)
        note(20, "On décale le webcast", kind: .decision, in: seance, context)
        note(30, "Départ possible", kind: .risk, in: seance, context)

        // Rien ne se perd : `②` recueille tout ce qui n'est ni la première
        // ligne ni un feedback. Une ligne qui n'apparaîtrait dans aucune
        // section serait une saisie invisible.
        #expect(OneOnOneNoteSections.notes(seance, in: .topics).map(\.t) == [20, 30])
        let toutes = OneOnOneNoteSections.Section.allCases
            .flatMap { OneOnOneNoteSections.notes(seance, in: $0) }
        #expect(toutes.count == 3)
    }

    @Test("Une ligne vide — un marqueur de ⌘M — n'apparaît dans aucune section")
    func marqueurIgnore() throws {
        let (seance, context) = try reunion()
        note(10, "   ", in: seance, context)
        note(20, "Une vraie ligne", in: seance, context)
        #expect(OneOnOneNoteSections.notes(seance, in: .howAreYou).map(\.t) == [20])
        #expect(OneOnOneNoteSections.notes(seance, in: .topics).isEmpty)
    }

    // MARK: - Feedback par côté

    @Test("Les deux cartes de feedback se remplissent par côté d'auteur")
    func feedbackParCote() throws {
        let (seance, context) = try reunion()
        captureNotes(in: seance, context)

        let jeLuiDis = OneOnOneNoteSections.feedback(seance, .given)
        #expect(jeLuiDis.map(\.t) == [1_680])
        let ilMeDit = OneOnOneNoteSections.feedback(seance, .received)
        #expect(ilMeDit.map(\.t) == [1_700])
        #expect(OneOnOneNoteSections.cardLabel(.given) == "CE QUE JE LUI DIS")
        #expect(OneOnOneNoteSections.cardLabel(.received) == "CE QU'IL ME DIT")
    }

    // MARK: - Complétude

    @Test("Le 1:1 n'est complet que quand les deux cartes sont renseignées")
    func completude() throws {
        let (seance, context) = try reunion()
        #expect(!OneOnOneNoteSections.isComplete(seance))
        #expect(OneOnOneNoteSections.completenessLabel(seance) == nil)

        note(1_680, "Présentation COSUI très claire.", kind: .feedback, in: seance, context)
        // Une seule carte : l'indicateur reste muet — il n'est pas bloquant,
        // et un « incomplet » permanent deviendrait du décor.
        #expect(!OneOnOneNoteSections.isComplete(seance))
        #expect(OneOnOneNoteSections.completenessLabel(seance) == nil)

        note(1_700, "Les arbitrages budget arrivent trop tard.",
             kind: .feedback, author: .collaborator, in: seance, context)
        #expect(OneOnOneNoteSections.isComplete(seance))
        #expect(OneOnOneNoteSections.completenessLabel(seance) == "1:1 complet")
    }

    // MARK: - Invites

    @Test("Chaque section vide porte une invite, jamais un cadre muet")
    func invites() {
        for section in OneOnOneNoteSections.Section.allCases {
            let invite = OneOnOneNoteSections.emptyInvite(for: section)
            #expect(!invite.isEmpty)
        }
        for carte in [NoteCommandParser.FeedbackSection.given, .received] {
            #expect(!OneOnOneNoteSections.feedbackEmptyInvite(for: carte).isEmpty)
        }
        #expect(OneOnOneNoteSections.privateLabel == "● NOTE PRIVÉE — VOUS SEUL")
    }

    // MARK: - Ton du moral

    @Test("Les cinq crans portent le ton de la spec")
    func tonsDuMoral() {
        #expect(OneOnOneMoodTone.tone(.difficile) == .report)
        #expect(OneOnOneMoodTone.tone(.sousTension) == .warn)
        #expect(OneOnOneMoodTone.tone(.caVa) == .oneOnOne)
        #expect(OneOnOneMoodTone.tone(.bien) == .ok)
        #expect(OneOnOneMoodTone.tone(.tresBien) == .ok)
        // « Très bien » est un `ok` **profond** : deux crans voisins qui
        // porteraient exactement la même couleur seraient indiscernables.
        #expect(OneOnOneMoodTone.isDeep(.tresBien))
        #expect(!OneOnOneMoodTone.isDeep(.bien))
    }
}
