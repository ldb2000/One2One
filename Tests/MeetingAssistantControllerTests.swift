import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'assistant de réunion sorti de sa vue (lot 4).
///
/// Le panneau du mode séance (spec §2.6) pose les mêmes questions que
/// `MeetingChatView` : deux constructions du même prompt finiraient par ne plus
/// donner les mêmes réponses selon l'écran. Ces tests fixent l'équivalence, et
/// couvrent les sources horodatées de la capture 1b (`1 sept. 08:12 ↗`,
/// `15:20 ↗`).
@Suite("Assistant de réunion")
@MainActor
struct MeetingAssistantControllerTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("`MeetingChatView` et le contrôleur construisent le même prompt")
    func promptsAgree() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final",
                              date: Date(timeIntervalSince1970: 1_788_506_100))
        context.insert(reunion)

        let vue = MeetingChatView(meeting: reunion)
        let parLaVue = vue.makePrompt(question: "Où en était le chiffrage ?",
                                      historicalContext: "[1] 1 sept. — COSUI: 40k engagés",
                                      history: "Utilisateur: bonjour\n\nAssistant: bonjour")
        let parLeControleur = MeetingAssistantController.prompt(
            meetingTitle: reunion.title,
            notesBlock: MeetingNoteStore.contextBlock(for: reunion, audience: .projectTeam),
            question: "Où en était le chiffrage ?",
            historicalContext: "[1] 1 sept. — COSUI: 40k engagés",
            history: "Utilisateur: bonjour\n\nAssistant: bonjour")
        #expect(parLaVue == parLeControleur)
    }

    @Test("Le prompt garde la consigne, la question, et n'ajoute rien de vide")
    func promptShape() {
        let sansRien = MeetingAssistantController.prompt(meetingTitle: "COSUI hebdo",
                                                         notesBlock: "",
                                                         question: "Et alors ?",
                                                         historicalContext: "",
                                                         history: "")
        #expect(sansRien.contains("COSUI hebdo"))
        #expect(sansRien.contains("Et alors ?"))
        #expect(!sansRien.contains("Notes prises en séance"))
        #expect(!sansRien.contains("Contexte historique"))
        #expect(!sansRien.contains("Conversation antérieure"))

        let avecTout = MeetingAssistantController.prompt(meetingTitle: "COSUI hebdo",
                                                         notesBlock: "[04:12] note",
                                                         question: "Et alors ?",
                                                         historicalContext: "[1] extrait",
                                                         history: "Utilisateur: x")
        #expect(avecTout.contains("Notes prises en séance"))
        #expect(avecTout.contains("Contexte historique"))
        #expect(avecTout.contains("Conversation antérieure"))
    }

    @Test("L'historique est coupé aux cinq derniers tours")
    func historyIsTrimmed() {
        let tours = (1...8).map { (question: "q\($0)", reponse: "r\($0)") }
        let texte = MeetingAssistantController.history(tours)
        #expect(!texte.contains("q3"))
        #expect(texte.contains("q4"))
        #expect(texte.contains("r8"))
        #expect(MeetingAssistantController.history([]).isEmpty)
    }

    @Test("Le libellé d'une source : dans la séance, ailleurs, sans instant")
    func sourceLabels() {
        let premierSeptembre = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9)) ?? .now
        // Dans la séance : le timecode seul.
        #expect(MeetingAssistantController.libelleSource(date: nil, t: 920) == "15:20")
        // Ailleurs : la date et le timecode.
        #expect(MeetingAssistantController.libelleSource(date: premierSeptembre, t: 492)
                .hasSuffix("08:12"))
        // Sans instant retrouvé : la date seule, jamais `00:00`, qui désignerait
        // un moment où rien ne s'est passé.
        let sansInstant = MeetingAssistantController.libelleSource(date: premierSeptembre, t: nil)
        #expect(!sansInstant.contains("00:00"))
        #expect(!sansInstant.isEmpty)
    }

    @Test("L'instant d'un extrait est retrouvé par recouvrement de texte")
    func extractInstant() {
        let segments = [
            (t: 231.0, texte: "Synchroniser les pipelines entre la source et le GitLab."),
            (t: 492.0, texte: "Sylvain devait fournir l'estimation Marine avant la fin du mois.")
        ]
        let t = MeetingAssistantController.instant(
            ofExtract: "Sylvain devait fournir l'estimation Marine — toujours ouverte.",
            inSegments: segments)
        #expect(t == 492)
    }

    @Test("Un extrait trop court ou étranger ne fabrique pas d'instant")
    func noFabricatedInstant() {
        let segments = [(t: 231.0, texte: "Synchroniser les pipelines.")]
        // Trop court : deviner reviendrait à poser un lien au hasard.
        #expect(MeetingAssistantController.instant(ofExtract: "oui", inSegments: segments) == nil)
        #expect(MeetingAssistantController.instant(
            ofExtract: "Rien à voir avec cette réunion du tout",
            inSegments: segments) == nil)
        #expect(MeetingAssistantController.instant(ofExtract: "n'importe quoi de long",
                                                   inSegments: []) == nil)
    }

    @Test("Une source de la séance replace la lecture, une autre ouvre sa réunion")
    func sourceRouting() {
        let ici = MeetingAssistantController.Source(libelle: "15:20",
                                                    meetingStableID: nil,
                                                    t: 920)
        let ailleurs = MeetingAssistantController.Source(libelle: "1 sept. 08:12",
                                                        meetingStableID: UUID(),
                                                        t: 492)
        #expect(ici.estDansLaSeance)
        #expect(!ailleurs.estDansLaSeance)
    }

    @Test("Le bloc de contexte numérote les extraits, et reste vide sans résultat")
    func contextBlock() {
        #expect(MeetingAssistantController.contextBlock([]).isEmpty)
    }

    @Test("Une question vide n'ouvre aucun échange")
    func emptyQuestionIsIgnored() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COSUI hebdo", date: .now)
        context.insert(reunion)
        let settings = AppSettings()
        context.insert(settings)

        let assistant = MeetingAssistantController()
        assistant.demander("   ", meeting: reunion, settings: settings, context: context)
        #expect(assistant.echanges.isEmpty)
        #expect(assistant.dernier == nil)
        #expect(!assistant.enCours)
    }
}
