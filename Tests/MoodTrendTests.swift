import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// **Critère d'acceptation du chantier 2, n° 3** : « le moral saisi en séance
/// alimente immédiatement l'histogramme de préparation suivant ».
///
/// La règle de tendance est celle de la spec §3.4, au demi-point près :
/// « `en baisse` si moyenne des 2 derniers < moyenne des 3 précédents − 0,5 ».
@Suite("Humeur — série, delta et tendance (spec §3.4, critère chantier 2 n° 3)")
@MainActor
struct MoodTrendTests {

    private static let jour: TimeInterval = 86_400
    private static let quatreSeptembre = Date(timeIntervalSince1970: 1_788_506_100)

    private func makeFil() throws -> (OneOnOneThread, ModelContext, Collaborator) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        laurent.oneToOneCadence = .bimensuelle
        context.insert(laurent)
        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        return (fil, context, laurent)
    }

    /// Sème une humeur par séance, la plus ancienne d'abord, à quinze jours
    /// d'intervalle en remontant depuis le 4 septembre.
    private func semer(_ valeurs: [Int], _ fil: OneOnOneThread,
                       _ context: ModelContext, _ collab: Collaborator) -> [Meeting] {
        var seances: [Meeting] = []
        let dernier = valeurs.count - 1
        for (index, valeur) in valeurs.enumerated() {
            let date = Self.quatreSeptembre.addingTimeInterval(Double(index - dernier) * 14 * Self.jour)
            let seance = Meeting(title: "1:1 Laurent", date: date, notes: "")
            seance.kind = .oneToOne
            context.insert(seance)
            seance.participants.append(collab)
            MoodTrend.record(valeur, for: seance, in: fil, in: context)
            seances.append(seance)
        }
        return seances
    }

    // MARK: - Tendance

    @Test("La série du jeu de la capture 2b est en baisse")
    func serieDeLaCapture() throws {
        let (fil, context, collab) = try makeFil()
        // 12/06 → 3, 26/06 → 4, 10/07 → 5, 24/07 → 4, 21/08 → 4, 04/09 → 2.
        // Deux derniers : (4 + 2) / 2 = 3,0. Trois précédents : (4 + 5 + 4) / 3
        // ≈ 4,33. 3,0 < 4,33 − 0,5 → « en baisse ».
        semer([3, 4, 5, 4, 4, 2], fil, context, collab)

        #expect(MoodTrend.direction(MoodTrend.series(fil).map(\.value)) == .enBaisse)
        #expect(MoodTrend.direction(MoodTrend.series(fil).map(\.value)).label == "en baisse")
    }

    @Test("Une remontée symétrique est en hausse")
    func remonteeEnHausse() {
        // Deux derniers : 4,5. Trois précédents : 2,33. 4,5 > 2,33 + 0,5.
        #expect(MoodTrend.direction([2, 2, 3, 4, 5]) == .enHausse)
        #expect(MoodTrend.direction([2, 2, 3, 4, 5]).label == "en hausse")
    }

    @Test("Une série plate est stable")
    func seriePlate() {
        #expect(MoodTrend.direction([4, 4, 4, 4, 4]) == .stable)
        #expect(MoodTrend.direction([4, 4, 4, 4, 4]).label == nil)
    }

    @Test("Le seuil est un demi-point strict")
    func seuilStrict() {
        // Trois précédents à 4, deux derniers à 3,5 : l'écart vaut exactement
        // 0,5, ce qui n'est pas « strictement inférieur à 4 − 0,5 ».
        #expect(MoodTrend.direction([4, 4, 4, 4, 3]) == .stable)
        // Un cran de plus et la baisse est franche.
        #expect(MoodTrend.direction([4, 4, 4, 3, 3]) == .enBaisse)
    }

    @Test("Moins de cinq points : pas de tendance")
    func pasAssezDePoints() {
        for serie in [[], [1], [1, 5], [5, 1, 1], [5, 5, 1, 1]] {
            #expect(MoodTrend.direction(serie) == .stable,
                    "\(serie.count) point(s) ne suffisent pas pour trancher")
        }
    }

    // MARK: - Série

    @Test("La série garde les six derniers, dans l'ordre chronologique")
    func serieDeSixPoints() throws {
        let (fil, context, collab) = try makeFil()
        semer([1, 2, 3, 4, 5, 4, 3, 2], fil, context, collab)

        let serie = MoodTrend.series(fil)
        #expect(serie.count == 6)
        #expect(serie.map(\.value) == [3, 4, 5, 4, 3, 2])
        // Chronologique : la première est la plus ancienne (l'histogramme se
        // lit de gauche à droite).
        #expect(serie.first!.recordedAt < serie.last!.recordedAt)
        #expect(MoodTrend.historyLength == 6)
    }

    // MARK: - Delta

    @Test("Le delta nomme le cran précédent et sa date")
    func delta() throws {
        let (fil, context, collab) = try makeFil()
        semer([3, 4, 5, 4, 4, 2], fil, context, collab)

        let delta = try #require(MoodTrend.delta(fil))
        #expect(delta.current == .sousTension)
        #expect(delta.previous == .bien)
        // 4 septembre − 14 jours = 21 août, la date de la capture 2a.
        #expect(MoodTrend.deltaLabel(fil) == "↓ vs 21 août (Bien)")
    }

    @Test("Une humeur en hausse porte la flèche montante")
    func deltaMontant() throws {
        let (fil, context, collab) = try makeFil()
        semer([2, 4], fil, context, collab)
        #expect(MoodTrend.deltaLabel(fil)?.hasPrefix("↑") == true)
    }

    @Test("Sans humeur précédente, il n'y a pas de delta")
    func pasDeDeltaSansPrecedent() throws {
        let (fil, context, collab) = try makeFil()
        semer([3], fil, context, collab)
        #expect(MoodTrend.delta(fil) == nil)
        #expect(MoodTrend.deltaLabel(fil) == nil)
    }

    // MARK: - Saisie (critère n° 3)

    @Test("Le moral saisi en séance remplace celui de la même réunion")
    func saisieRemplace() throws {
        let (fil, context, collab) = try makeFil()
        let seances = semer([4], fil, context, collab)
        let seance = try #require(seances.first)

        // Une deuxième saisie **corrige** : une humeur est un cran, pas un
        // journal. Empiler ferait deux barres pour une séance.
        MoodTrend.record(2, for: seance, in: fil, in: context)

        #expect(fil.moodEntries.count == 1)
        #expect(MoodTrend.series(fil).map(\.value) == [2])
        #expect(MoodTrend.entry(for: seance, in: fil)?.value == 2)
    }

    @Test("Une valeur hors bornes est ramenée dans l'échelle")
    func valeurBornee() throws {
        let (fil, context, collab) = try makeFil()
        let seances = semer([9], fil, context, collab)
        #expect(MoodTrend.entry(for: seances[0], in: fil)?.clampedValue == 5)

        MoodTrend.record(-3, for: seances[0], in: fil, in: context)
        #expect(MoodTrend.entry(for: seances[0], in: fil)?.clampedValue == 1)
    }

    // MARK: - Échelle et explication

    @Test("Les cinq crans portent les libellés de la spécification")
    func libellesDesCrans() {
        #expect(MoodLevel.allCases.map(\.label)
                == ["Difficile", "Sous tension", "Ça va", "Bien", "Très bien"])
        #expect(MoodLevel.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(MoodLevel(rawValue: 3) == .caVa)
    }

    @Test("La phrase d'explication cite le sujet le plus récurrent")
    func phraseExplicative() {
        let phrase = MoodTrend.explanation([(label: "Charge de travail", count: 5),
                                            (label: "Mobilité archi", count: 3)])
        #expect(phrase == "Cause citée 5 fois : Charge de travail.")
        #expect(MoodTrend.explanation([]) == nil)
        // Un sujet cité une seule fois n'explique rien : ce n'est pas encore
        // un motif, c'est une occurrence.
        #expect(MoodTrend.explanation([(label: "Astreintes", count: 1)]) == nil)
    }
}
