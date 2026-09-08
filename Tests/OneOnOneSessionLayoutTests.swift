import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// La grille de l'écran de séance 1:1 (spec §3.3 : « grille `300 | 1fr | 320` »)
/// et son routage.
///
/// Le calcul est séparé de la vue pour la même raison qu'au lot 1 : en SwiftUI,
/// une soustraction de largeurs non bornée produit une colonne négative qui se
/// traduit par un **chevauchement silencieux**, pas par une erreur.
@Suite("Écran de séance 1:1 — grille 300 | 1fr | 320 et routage")
struct OneOnOneSessionLayoutTests {

    // MARK: - Largeurs

    @Test("À 1 280 px, les trois colonnes valent 300, 660 et 320")
    func grilleA1280() {
        let colonnes = MeetingSpaceLayout.oneOnOneColumns(totalWidth: 1_280)
        #expect(colonnes.left == 300)
        #expect(colonnes.center == 660)
        #expect(colonnes.rail == 320)
        // Critère chantier 1 n° 5, repris ici : la colonne fluide ne descend
        // jamais sous 520 px sans qu'une colonne fixe soit retirée.
        #expect(colonnes.center >= MeetingSpaceLayout.fluidMinimum)
        #expect(colonnes.left + colonnes.center + colonnes.rail == 1_280)
    }

    @Test("Les deux constantes sont celles de la spec")
    func constantes() {
        #expect(MeetingSpaceLayout.oneOnOneLeftWidth == 300)
        #expect(MeetingSpaceLayout.oneOnOneRailWidth == 320)
    }

    @Test("Sous 1 140 px, la colonne gauche cède la première")
    func colonneGaucheCedeLaPremiere() {
        let colonnes = MeetingSpaceLayout.oneOnOneColumns(totalWidth: 1_000)
        // Le rail porte la clôture et les engagements de la séance : c'est la
        // colonne gauche (contexte) qui s'efface, jamais lui.
        #expect(colonnes.left == 0)
        #expect(colonnes.rail == 320)
        #expect(colonnes.center == 680)
    }

    @Test("Sous 840 px, le rail cède à son tour")
    func railCedeEnsuite() {
        let colonnes = MeetingSpaceLayout.oneOnOneColumns(totalWidth: 700)
        #expect(colonnes.left == 0)
        #expect(colonnes.rail == 0)
        #expect(colonnes.center == 700)
    }

    @Test("Aucune largeur n'est négative, même pour une fenêtre absurde")
    func jamaisDeLargeurNegative() {
        for largeur in [CGFloat(-100), 0, 1, 200, 519, 520, 839, 840, 1_139, 1_140, 1_920] {
            let colonnes = MeetingSpaceLayout.oneOnOneColumns(totalWidth: largeur)
            #expect(colonnes.left >= 0)
            #expect(colonnes.center >= 0)
            #expect(colonnes.rail >= 0)
            #expect(colonnes.left + colonnes.center + colonnes.rail <= max(0, largeur))
        }
    }

    @Test("À 1 920 px la colonne centrale prend tout le surplus")
    func grilleA1920() {
        let colonnes = MeetingSpaceLayout.oneOnOneColumns(totalWidth: 1_920)
        #expect(colonnes.left == 300)
        #expect(colonnes.rail == 320)
        #expect(colonnes.center == 1_300)
    }

    // MARK: - Routage

    @Test("Seul un 1:1 mené en mode En séance ouvre l'écran 2a")
    func routageDeLEcran2a() {
        #expect(MeetingSpaceRouting.usesOneOnOneManagerSession(kind: .oneToOne, mode: .live))
        // Le 1:1 subi est l'écran 5a du lot 13, pas celui-ci.
        #expect(!MeetingSpaceRouting.usesOneOnOneManagerSession(kind: .manager, mode: .live))
        #expect(!MeetingSpaceRouting.usesOneOnOneManagerSession(kind: .oneToOne, mode: .prepare))
        #expect(!MeetingSpaceRouting.usesOneOnOneManagerSession(kind: .oneToOne, mode: .review))
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(!MeetingSpaceRouting.usesOneOnOneManagerSession(kind: kind, mode: .live))
        }
    }

    @Test("Le 1:1 garde les trois espaces et les trois modes du programme")
    func espacesEtModesInchanges() {
        #expect(MeetingSpaceRouting.spaces(for: .oneToOne) == [.meeting, .report, .resources])
        #expect(MeetingSpaceRouting.modes(for: .oneToOne) == [.prepare, .live, .review])
    }

    // MARK: - Dates

    @Test("Les deux écritures de date de la capture 2a")
    func ecrituresDeDate() {
        // Vendredi 4 septembre 2026, 9 h 15 — la séance de la capture.
        let seance = Date(timeIntervalSince1970: 1_788_506_100)
        #expect(OneOnOneDateFormat.weekday(seance) == "Vendredi")
        #expect(OneOnOneDateFormat.dayFullMonth(seance) == "4 septembre")
        // Mercredi 9 septembre : la pilule « 9 sept. » reste au format court.
        let mercredi = seance.addingTimeInterval(5 * 86_400)
        #expect(OneOnOneDateFormat.weekday(mercredi) == "Mercredi")
        #expect(OneOnOneDateFormat.dayMonth(mercredi) == "9 sept.")
    }

    @Test("Le jour de la semaine est majuscule, quelle que soit la locale du poste")
    func jourEnMajuscule() {
        let dimanche = Date(timeIntervalSince1970: 1_788_506_100).addingTimeInterval(2 * 86_400)
        let libelle = OneOnOneDateFormat.weekday(dimanche)
        #expect(libelle == "Dimanche")
        #expect(libelle.first?.isUppercase == true)
    }
}
