import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Ce que le jeu de démonstration doit reproduire de
/// `1c-poste-de-pilotage.png` : sans ces chiffres, la recette visuelle compare
/// deux écrans différents et ne prouve rien.
@Suite("Jeu de démonstration du poste de pilotage")
@MainActor
struct RefonteDemoSeedLot5Tests {

    private var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Les trois décisions de la capture sont horodatées 11:03, 13:40 et 20:15")
    func timedDecisions() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        let lignes = DecisionsCard.lignes(for: reunion)
        #expect(lignes.count == 3)
        #expect(lignes.map { $0.t } == [663, 820, 1_215])
        #expect(lignes.compactMap { $0.t }.map { TimecodeLabel.format($0) }
                == ["11:03", "13:40", "20:15"])
        // La première nomme son porteur : c'est le « — Olivier Freund » de la
        // capture, détaché du texte.
        #expect(lignes[0].porteur == "Olivier Freund")
        #expect(lignes[0].texte == "Le partenaire finalise la migration")
        #expect(lignes[1].porteur == nil)
        #expect(lignes[2].texte == "Webcast développeurs lancé cette semaine")
    }

    @Test("Les quatre thèmes de la carte EN UNE PHRASE sont posés")
    func tags() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        #expect(reunion.tags.count == 4)
        #expect(Set(reunion.tags.map(\.name))
                == Set(["Migration AP", "Facturation", "GitLab / CI-CD", "Ressources"]))
    }

    @Test("Le résumé en une phrase est celui de la capture, gras compris")
    func shortSummary() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        #expect(reunion.shortSummary.contains("**AP**"))
        #expect(reunion.shortSummary.contains("**Décision**"))
        #expect(reunion.shortSummary.contains("**Reste à faire**"))
        // Le gras survit au rendu de la carte.
        let riche = OneSentenceCard.texteRiche(reunion.shortSummary)
        #expect(!String(riche.characters).contains("**"))
    }

    @Test("Le bloc projet montre les trois réunions de la capture")
    func projectThread() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)
        let historique = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []

        let dernieres = ReviewSidebarNav.dernieresDuProjet(reunion, dans: historique)
        #expect(dernieres.count == 3)
        #expect(dernieres.map { ReviewSidebarNav.libelleReunion($0, calendar: calendrier) }
                == ["1er sept. — COSUI hebdo",
                    "31 août — Gouvernance",
                    "26 août — Situation AP"])
    }

    @Test("La ligne de métadonnées de l'en-tête est celle de la capture")
    func headerLine() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        #expect(ReviewHeader.metadonnees(for: reunion,
                                         locale: Locale(identifier: "fr_FR"),
                                         calendar: calendrier)
                == "P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants")
    }

    @Test("Le rail latéral affiche les compteurs de la capture")
    func navCounters() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        let parSection = Dictionary(uniqueKeysWithValues:
            ReviewSidebarNav.entrees(for: reunion).map { ($0.section, $0) })
        #expect(parSection[.transcription]?.complement == .minutes(23))
        #expect(parSection[.actions]?.complement == .compte(12))
        // `9 sans responsable` : le compteur est en rouge.
        #expect(parSection[.actions]?.alerte == true)
        #expect(parSection[.synthese]?.complement == .etat("généré"))
        // Chaque entrée porte quelque chose, y compris sur ce jeu réel.
        for entree in ReviewSidebarNav.entrees(for: reunion) {
            #expect(!entree.complement.texte.isEmpty)
        }
    }

    @Test("Le tableau d'actions montre cinq lignes et annonce sept autres")
    func actionsTable() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        let ouvertes = ActionsRailGrouping.triees(reunion.tasks.filter { $0.status == .open })
        #expect(ouvertes.count == 12)
        let replie = ActionsTableCommands.repli(ouvertes,
                                                limite: ActionsTable.lignesRepliees,
                                                tout: false)
        #expect(replie.visibles.count == 5)
        // « 7 autres · tout afficher » de la capture.
        #expect(replie.restantes == 7)

        let sansResponsable = ouvertes.filter { !ActionsRailGrouping.aUnPorteur($0) }
        #expect(sansResponsable.count == 9)
        // Le focus posé après le rapport tombe sur la première d'entre elles.
        #expect(ActionsTableCommands.premiereSansResponsable(ouvertes) != nil)
    }

    @Test("La frise étiquetée retient les marqueurs de la capture")
    func timelineLabels() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        let repères = MeetingTimelineMarkers.markers(for: reunion)
        let candidats = AudioTimelineStrip.candidats(repères)
        // Trois décisions et trois notes : six étiquettes candidates.
        #expect(candidats.filter(\.estDecision).count == 3)
        let placees = TimelineLabelLayout.placer(candidats,
                                                 duration: Double(reunion.durationSeconds),
                                                 width: 1_200)
        // Les trois décisions passent d'abord — c'est la règle de priorité.
        #expect(placees.filter(\.estDecision).count == 3)
        // …et rien ne se chevauche.
        for (precedente, suivante) in zip(placees, placees.dropFirst()) {
            #expect(suivante.centre - suivante.largeur / 2
                    >= precedente.centre + precedente.largeur / 2
                        + TimelineLabelLayout.espacement)
        }
    }

    @Test("Semer deux fois ne duplique rien")
    func idempotent() throws {
        let context = try makeContext()
        let premiere = RefonteDemoSeed.seedLot5(in: context)
        let decisions = DecisionsCard.lignes(for: premiere).count
        let themes = premiere.tags.count
        let notes = premiere.timedNotes.count
        let actions = premiere.tasks.count

        let seconde = RefonteDemoSeed.seedLot5(in: context)
        #expect(seconde.persistentModelID == premiere.persistentModelID)
        #expect(DecisionsCard.lignes(for: seconde).count == decisions)
        #expect(seconde.tags.count == themes)
        #expect(seconde.timedNotes.count == notes)
        #expect(seconde.tasks.count == actions)

        let reunions = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        // La réunion de la capture, les trois du fil, et rien de plus.
        #expect(reunions.count == 4)
    }

    @Test("Le semis du lot 3 reste intact")
    func lot3Untouched() throws {
        let context = try makeContext()
        let reunion = RefonteDemoSeed.seedLot5(in: context)

        // Les chiffres de `1a-cockpit.png`, que le lot 3 fixe déjà.
        #expect(reunion.tasks.count == 12)
        #expect(reunion.participants.count == 6)
        #expect(reunion.meetingAlerts.count == 5)
        #expect(reunion.transcriptSegments.count == 4)
        #expect(reunion.durationSeconds == 1_404)
        #expect(reunion.decisions.count == 3)
        let kpi = MeetingKPIBuilder.build(meeting: reunion)
        #expect(kpi.actions.total == 12)
        #expect(kpi.actions.unassigned == 9)
    }
}
