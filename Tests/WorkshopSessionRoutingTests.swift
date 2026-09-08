import Testing
import Foundation
@testable import OneToOne

/// Le routage de l'écran 6b et son crochet de recette.
@Suite("Atelier — routage de la planche de séance")
@MainActor
struct WorkshopSessionRoutingTests {

    @Test("Le mode Relire de l'atelier remplace le poste de pilotage")
    func workshopReviewReplacesTheCockpit() {
        #expect(MeetingSpaceRouting.usesWorkshopReview(kind: .workshop, mode: .review))
        #expect(!MeetingSpaceRouting.usesWorkshopReview(kind: .workshop, mode: .live))
        #expect(!MeetingSpaceRouting.usesWorkshopReview(kind: .workshop, mode: .prepare))
        // Les autres types gardent le poste de pilotage du lot 5.
        for kind in [MeetingKind.project, .oneToOne, .manager, .global, .work, .note] {
            #expect(!MeetingSpaceRouting.usesWorkshopReview(kind: kind, mode: .review))
        }
    }

    @Test("Les prédicats d'écran plein cadre restent exclusifs deux à deux")
    func screenPredicatesStayMutuallyExclusive() {
        for kind in MeetingKind.allCases {
            for mode in [MeetingScreenModel.Mode.prepare, .live, .review] {
                let allumes = [
                    MeetingSpaceRouting.usesWorkshopReview(kind: kind, mode: mode),
                    MeetingSpaceRouting.usesOneOnOneManagerSession(kind: kind, mode: mode),
                    MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: kind, mode: mode),
                    MeetingSpaceRouting.usesOneOnOnePreparation(kind: kind, mode: mode),
                    // Lot 14, entré dans la base à l'intégration de la vague 7 :
                    // la préparation du 1:1 subi est le cinquième plein cadre,
                    // et l'oublier ici laisserait passer un chevauchement.
                    MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: kind, mode: mode),
                ].filter { $0 }.count
                #expect(allumes <= 1)
            }
        }
    }

    @Test("L'atelier garde ses trois espaces et ses trois modes")
    func workshopKeepsItsSpacesAndModes() {
        #expect(MeetingSpaceRouting.modes(for: .workshop).contains(.review))
        #expect(MeetingSpaceRouting.spaces(for: .workshop).contains(.report))
    }

    @Test("Le code 6b ouvre l'atelier en mode Relire")
    func recetteCode6bOpensTheWorkshopInReview() {
        let ecran = RecetteScreen.from(environment: "6b")
        #expect(ecran == .atelierPlancheDeSeance)
        #expect(ecran?.cible == .atelier)
        #expect(ecran?.mode == .review)
        // 6a n'a pas bougé.
        #expect(RecetteScreen.from(environment: "6a")?.mode == .live)
    }

    @Test("Chaque code de recette reste unique")
    func recetteCodesStayUnique() {
        let codes = RecetteScreen.allCases.map(\.rawValue)
        #expect(Set(codes).count == codes.count)
        #expect(codes.contains("6b"))
    }
}
