import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// `① COMMENT ÇA VA` — l'échelle à cinq crans de la capture 2a et ce qu'elle
/// écrit.
///
/// Critère d'acceptation chantier 2 n° 3 : « le moral saisi en séance alimente
/// immédiatement l'histogramme de préparation suivant ». Le relevé est donc
/// écrit **en base**, sur la séance et sur le fil, et il **remplace** celui de
/// la séance au lieu de s'y ajouter.
@Suite("Échelle de moral — saisie, remplacement, delta")
@MainActor
struct OneOnOneMoodScaleTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }

    // MARK: - Saisie

    @Test("Choisir un cran crée un relevé rattaché à la séance et au fil")
    func saisieDUnCran() throws {
        let (fil, seance, context) = try filDeDemonstration()
        let avant = fil.moodEntries.count

        let entree = MoodScaleModel.record(.sousTension, for: seance, in: fil, in: context)
        #expect(entree.value == MoodLevel.sousTension.rawValue)
        #expect(entree.meeting?.persistentModelID == seance.persistentModelID)
        #expect(entree.thread?.persistentModelID == fil.persistentModelID)
        // Le jeu de démonstration a déjà un relevé sur cette séance : la
        // saisie le remplace, elle ne l'ajoute pas.
        #expect(fil.moodEntries.count == avant)
    }

    @Test("Deux corrections de suite ne laissent qu'un relevé pour la séance")
    func remplacement() throws {
        let (fil, seance, context) = try filDeDemonstration()
        MoodScaleModel.record(.difficile, for: seance, in: fil, in: context)
        MoodScaleModel.record(.bien, for: seance, in: fil, in: context)

        let releves = fil.moodEntries.filter {
            $0.meeting?.persistentModelID == seance.persistentModelID
        }
        #expect(releves.count == 1)
        #expect(MoodScaleModel.selected(for: seance, in: fil) == .bien)
        // La série de six barres de la capture 2b garde sa longueur : sans
        // remplacement, une correction décalerait tout l'histogramme.
        #expect(MoodTrend.series(fil).count == 6)
    }

    @Test("Le cran choisi est celui qu'on relit, y compris après un aller-retour")
    func relecture() throws {
        let (fil, seance, context) = try filDeDemonstration()
        for cran in MoodLevel.allCases {
            MoodScaleModel.record(cran, for: seance, in: fil, in: context)
            #expect(MoodScaleModel.selected(for: seance, in: fil) == cran)
        }
    }

    @Test("Une séance sans relevé n'a aucun cran choisi")
    func aucunCran() throws {
        let (fil, seance, context) = try filDeDemonstration()
        let entree = try #require(MoodTrend.entry(for: seance, in: fil))
        context.delete(entree)
        try context.save()
        #expect(MoodScaleModel.selected(for: seance, in: fil) == nil)
    }

    // MARK: - Delta (capture 2a)

    @Test("Le delta de la capture : ↓ vs 21 août (Bien)")
    func deltaDeLaCapture() throws {
        let (fil, _, _) = try filDeDemonstration()
        // Le jeu du lot 10 sème 3, 4, 5, 4, 4, 2 : le dernier cran est
        // « Sous tension », le précédent « Bien », quinze jours avant.
        #expect(MoodScaleModel.selectedLabel(of: fil) == "Sous tension")
        #expect(MoodTrend.deltaLabel(fil) == "↓ vs 21 août (Bien)")
    }

    @Test("Le delta suit la correction faite en séance")
    func deltaApresCorrection() throws {
        let (fil, seance, context) = try filDeDemonstration()
        MoodScaleModel.record(.tresBien, for: seance, in: fil, in: context)
        // Le cran monte : la flèche change de sens dans la même seconde —
        // c'est ce que « alimente immédiatement » veut dire.
        #expect(MoodTrend.deltaLabel(fil) == "↑ vs 21 août (Bien)")
    }

    @Test("Sans relevé précédent, aucun delta n'est affiché")
    func sansDelta() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let personne = Collaborator(name: "Nouvelle ARRIVÉE")
        context.insert(personne)
        let seance = Meeting(title: "1:1 — Nouvelle · 1", date: Self.maintenant, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(personne)
        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))

        MoodScaleModel.record(.caVa, for: seance, in: fil, in: context)
        #expect(MoodTrend.deltaLabel(fil) == nil)
    }

    // MARK: - Rendu

    @Test("Les cinq crans sont dans l'ordre, avec leur libellé et leur ton")
    func cransEtTons() {
        #expect(MoodLevel.allCases.map(\.label)
                == ["Difficile", "Sous tension", "Ça va", "Bien", "Très bien"])
        #expect(MoodScaleModel.title == "① COMMENT ÇA VA")
        #expect(MoodScaleModel.tone(.sousTension) == .warn)
    }

    // MARK: - Fixture

    /// Le fil de la capture, semé par le lot 10 : quatorze séances, six
    /// relevés d'humeur, la dernière séance au 4 septembre.
    private func filDeDemonstration() throws -> (OneOnOneThread, Meeting, ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let fils = RefonteDemoSeed.seedOneOnOneThreads(in: context)
        let seance = try #require(
            OneOnOneThreadStore.meetings(of: fils.manager, now: Self.maintenant).last)
        return (fils.manager, seance, context)
    }
}
