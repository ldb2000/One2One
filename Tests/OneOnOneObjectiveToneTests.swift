import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Spec §3.4 : « Objectifs : label + pourcentage + barre ; couleur par
/// avancement (< 30 % `warn`, < 70 % neutre/violet, ≥ 70 % `ok`). Date de revue
/// en pied. »
@Suite("Objectifs — ton par seuil et date de revue (spec §3.4)")
@MainActor
struct OneOnOneObjectiveToneTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Les trois seuils sont ceux de la spécification")
    func seuils() {
        #expect(OneOnOneObjective.tone(forProgress: 0) == .warn)
        #expect(OneOnOneObjective.tone(forProgress: 29) == .warn)
        #expect(OneOnOneObjective.tone(forProgress: 30) == .oneOnOne)
        #expect(OneOnOneObjective.tone(forProgress: 69) == .oneOnOne)
        #expect(OneOnOneObjective.tone(forProgress: 70) == .ok)
        #expect(OneOnOneObjective.tone(forProgress: 100) == .ok)
    }

    @Test("Les trois objectifs de la capture 2b portent les trois tons")
    func objectifsDeLaCapture() {
        // Industrialiser la CI/CD 70 % (vert), Monter en compétence archi 25 %
        // (orange), Transmettre 10 % (orange).
        #expect(OneOnOneObjective.tone(forProgress: 70) == .ok)
        #expect(OneOnOneObjective.tone(forProgress: 25) == .warn)
        #expect(OneOnOneObjective.tone(forProgress: 10) == .warn)
    }

    @Test("Une progression hors bornes est ramenée dans l'échelle")
    func progressionBornee() throws {
        let context = try makeContext()
        let bas = OneOnOneObjective(label: "Trop bas", progress: 0)
        let haut = OneOnOneObjective(label: "Trop haut", progress: 100)
        context.insert(bas)
        context.insert(haut)
        // La colonne brute reste lisible pour une restauration douteuse ; le
        // ton, lui, passe par la valeur bornée.
        bas.progress = -5
        haut.progress = 140

        #expect(bas.tone == .warn)
        #expect(haut.tone == .ok)
        #expect(bas.clampedProgress == 0)
        #expect(haut.clampedProgress == 100)
    }

    @Test("Les objectifs sortent dans l'ordre manuel, puis par date de création")
    func tri() throws {
        let context = try makeContext()
        let troisieme = OneOnOneObjective(label: "Transmettre (formation Admin)", progress: 10, order: 2)
        let premier = OneOnOneObjective(label: "Industrialiser la CI/CD", progress: 70, order: 0)
        let deuxieme = OneOnOneObjective(label: "Monter en compétence archi", progress: 25, order: 1)
        for objectif in [troisieme, premier, deuxieme] { context.insert(objectif) }

        #expect(OneOnOneObjectiveList.sorted([troisieme, premier, deuxieme]).map(\.label)
                == ["Industrialiser la CI/CD", "Monter en compétence archi",
                    "Transmettre (formation Admin)"])
    }

    @Test("Le pied annonce la revue la plus proche")
    func dateDeRevue() throws {
        let context = try makeContext()
        // 18 septembre 2026 — la date de la capture 2b.
        let dixHuitSeptembre = Date(timeIntervalSince1970: 1_788_506_100 + 14 * 86_400)
        let proche = OneOnOneObjective(label: "Proche", reviewAt: dixHuitSeptembre)
        let lointain = OneOnOneObjective(label: "Lointain",
                                          reviewAt: dixHuitSeptembre.addingTimeInterval(60 * 86_400))
        let sansDate = OneOnOneObjective(label: "Sans date")
        for objectif in [lointain, proche, sansDate] { context.insert(objectif) }

        #expect(OneOnOneObjectiveList.reviewLabel([lointain, proche, sansDate])
                == "Revue prévue le 18 sept.")
        #expect(OneOnOneObjectiveList.reviewLabel([sansDate]) == nil)
        #expect(OneOnOneObjectiveList.reviewLabel([]) == nil)
    }
}
