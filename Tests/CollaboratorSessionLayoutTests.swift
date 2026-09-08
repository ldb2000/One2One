import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// La grille de l'écran de séance du 1:1 **subi** (spec §6.2 : « grille
/// `308 | 1fr | 356` »), son routage, et le fil d'Ariane que la barre du haut
/// en tire.
///
/// Le calcul des largeurs est séparé de la vue pour la raison du lot 1 : en
/// SwiftUI, une soustraction de largeurs non bornée produit une colonne
/// négative qui se traduit par un **chevauchement silencieux**, pas par une
/// erreur.
@Suite("Écran de séance 1:1 collaborateur — grille 308 | 1fr | 356, routage, barre")
struct CollaboratorSessionLayoutTests {

    // MARK: - Largeurs

    @Test("À 1 280 px, les trois colonnes valent 308, 616 et 356")
    func grilleA1280() {
        let colonnes = MeetingSpaceLayout.collaboratorColumns(totalWidth: 1_280)
        #expect(colonnes.left == 308)
        #expect(colonnes.center == 616)
        #expect(colonnes.rail == 356)
        // Critère chantier 1 n° 5, repris ici : la colonne fluide ne descend
        // jamais sous 520 px sans qu'une colonne fixe soit retirée.
        #expect(colonnes.center >= MeetingSpaceLayout.fluidMinimum)
        #expect(colonnes.left + colonnes.center + colonnes.rail == 1_280)
    }

    @Test("Les deux constantes sont celles de la spec §6.2")
    func constantes() {
        #expect(MeetingSpaceLayout.collabLeftWidth == 308)
        #expect(MeetingSpaceLayout.collabRailWidth == 356)
    }

    @Test("À 1 920 px la colonne centrale prend tout le surplus")
    func grilleA1920() {
        let colonnes = MeetingSpaceLayout.collaboratorColumns(totalWidth: 1_920)
        #expect(colonnes.left == 308)
        #expect(colonnes.rail == 356)
        #expect(colonnes.center == 1_256)
    }

    @Test("Sous 1 184 px, la colonne gauche cède la première")
    func colonneGaucheCedeLaPremiere() {
        // Le rail porte les preuves, les promesses et la clôture ; la colonne
        // gauche porte un brouillon privé. C'est elle qui s'efface.
        let colonnes = MeetingSpaceLayout.collaboratorColumns(totalWidth: 1_000)
        #expect(colonnes.left == 0)
        #expect(colonnes.rail == 356)
        #expect(colonnes.center == 644)
    }

    @Test("Sous 876 px, le rail cède à son tour")
    func railCedeEnsuite() {
        let colonnes = MeetingSpaceLayout.collaboratorColumns(totalWidth: 800)
        #expect(colonnes.left == 0)
        #expect(colonnes.rail == 0)
        #expect(colonnes.center == 800)
    }

    @Test("Aucune largeur n'est négative, même pour une fenêtre absurde")
    func jamaisDeLargeurNegative() {
        for largeur in [CGFloat(-100), 0, 1, 200, 519, 520, 875, 876, 1_183, 1_184, 1_920] {
            let colonnes = MeetingSpaceLayout.collaboratorColumns(totalWidth: largeur)
            #expect(colonnes.left >= 0)
            #expect(colonnes.center >= 0)
            #expect(colonnes.rail >= 0)
            #expect(colonnes.left + colonnes.center + colonnes.rail <= max(0, largeur))
        }
    }

    // MARK: - Routage

    @Test("Seul un 1:1 subi en mode En séance ouvre l'écran 5a")
    func routageDeLEcran5a() {
        #expect(MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: .manager, mode: .live))
        // Le 1:1 mené est l'écran 2a du lot 11, pas celui-ci.
        #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: .oneToOne, mode: .live))
        #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: .manager, mode: .prepare))
        #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: .manager, mode: .review))
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: kind, mode: .live))
        }
    }

    @Test("Les deux écrans de séance 1:1 ne se recouvrent jamais")
    func lesDeuxEcransSExcluent() {
        for kind in MeetingKind.allCases {
            for mode in [MeetingScreenModel.Mode.prepare, .live, .review] {
                let mene = MeetingSpaceRouting.usesOneOnOneManagerSession(kind: kind, mode: mode)
                let subi = MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: kind,
                                                                              mode: mode)
                #expect(!(mene && subi))
            }
        }
    }

    @Test("Le 1:1 subi garde les trois espaces et les trois modes du programme")
    func espacesEtModesInchanges() {
        #expect(MeetingSpaceRouting.spaces(for: .manager) == [.meeting, .report, .resources])
        #expect(MeetingSpaceRouting.modes(for: .manager) == [.prepare, .live, .review])
    }

    // MARK: - Critère chantier 5 n° 1 — le rôle est visible en permanence

    @Test("Le fil d'Ariane d'un 1:1 subi porte `Mes 1:1`, le badge et la pilule de rôle")
    func filDArianeDuSubi() {
        let segments = CollaboratorTopBarModel.breadcrumbSegments(for: .manager)
        #expect(segments == ["One2One", "Mes 1:1", "1:1", "Je suis le collaborateur"])
    }

    @Test("Le fil d'Ariane d'un 1:1 mené n'a ni `Mes 1:1` ni pilule de rôle")
    func filDArianeDuMene() {
        let segments = CollaboratorTopBarModel.breadcrumbSegments(for: .oneToOne)
        #expect(segments == ["One2One", "Mon équipe", "1:1"])
        #expect(!segments.contains("Je suis le collaborateur"))
        #expect(!segments.contains("Mes 1:1"))
    }

    @Test("La pilule de rôle n'est jamais masquée : elle est dans le fil d'Ariane du subi")
    func pilluleDeRoleObligatoire() {
        // D4 et spec §6.1 : « Pilule `Je suis le collaborateur` dans la barre,
        // obligatoire ». Elle ne dépend d'aucun réglage, d'aucune largeur et
        // d'aucun état d'écran — seulement du type.
        #expect(MeetingTopChromeBar.collaboratorPillLabel(for: .manager)
                == "Je suis le collaborateur")
        for kind in MeetingKind.allCases where kind != .manager {
            #expect(MeetingTopChromeBar.collaboratorPillLabel(for: kind) == nil)
        }
        #expect(CollaboratorTopBarModel.breadcrumbSegments(for: .manager)
            .contains("Je suis le collaborateur"))
    }

    @Test("Aucun type autre que le 1:1 subi ne porte le segment `Mes 1:1`")
    func segmentMesUnUnReserveAuSubi() {
        #expect(MeetingTopChromeBar.myOneOnOnesSegmentLabel(for: .manager) == "Mes 1:1")
        for kind in MeetingKind.allCases where kind != .manager {
            #expect(MeetingTopChromeBar.myOneOnOnesSegmentLabel(for: kind) == nil)
        }
    }

    // MARK: - En-tête de la barre

    @Test("L'en-tête d'un 1:1 subi est `Avec <Manager> — <jour mois>`")
    func enTeteDuSubi() {
        // Vendredi 4 septembre 2026, 9 h 15 — la séance de la capture 5a.
        let seance = Date(timeIntervalSince1970: 1_788_506_100)
        #expect(MeetingTopChromeBar.collaboratorSessionHeading(person: "Yann PENVEN",
                                                               date: seance)
                == "Avec Yann PENVEN — 4 septembre")
    }

    @Test("Sans nom de manager, l'en-tête reste une phrase et n'affiche pas un tiret nu")
    func enTeteSansNom() {
        let seance = Date(timeIntervalSince1970: 1_788_506_100)
        #expect(MeetingTopChromeBar.collaboratorSessionHeading(person: "   ", date: seance)
                == "Mon 1:1 du 4 septembre")
    }
}
