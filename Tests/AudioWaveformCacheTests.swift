import Testing
import Foundation
@testable import OneToOne

/// Le cache des pics d'onde de la frise audio (spec §2.4).
///
/// Aucun fichier audio n'est lu ici : les tests portent sur ce qui compte —
/// un fichier illisible ne fait pas planter la frise, et il n'est pas
/// redécodé à chaque rendu.
@Suite("Cache des pics d'onde")
@MainActor
struct AudioWaveformCacheTests {

    @Test("Un fichier illisible rend une onde vide, mémorisée une seule fois")
    func fichierIllisible() async {
        // Cache propre au test : les suites tournent en parallèle, et compter
        // les entrées du singleton mesurerait le travail des autres.
        let cache = AudioWaveformCache()
        let url = URL(fileURLWithPath: "/tmp/onetoone-inexistant-\(UUID().uuidString).wav")
        let depart = cache.cachedCount

        let premier = await cache.peaks(url: url, count: 64)
        let second = await cache.peaks(url: url, count: 64)

        #expect(premier.isEmpty)
        #expect(second.isEmpty)
        #expect(cache.cachedCount == depart + 1, "une seule entrée pour deux demandes")

        cache.invalidate(url: url)
        #expect(cache.cachedCount == depart)
    }

    @Test("Deux résolutions du même fichier sont deux entrées distinctes")
    func deuxResolutions() async {
        let cache = AudioWaveformCache()
        let url = URL(fileURLWithPath: "/tmp/onetoone-inexistant-\(UUID().uuidString).wav")
        let depart = cache.cachedCount

        _ = await cache.peaks(url: url, count: 64)
        _ = await cache.peaks(url: url, count: 256)
        // Mélanger les résolutions donnerait une onde étirée : la frise de
        // 22 px et l'éditeur audio ne demandent pas le même nombre de pics.
        #expect(cache.cachedCount == depart + 2)

        cache.invalidate(url: url)
        #expect(cache.cachedCount == depart)
    }

    @Test("Le nombre de pics demandé suit la largeur de la frise, borné")
    func nombreDePics() {
        #expect(AudioTimelineGeometry.peakCount(width: 600) == 100)
        #expect(AudioTimelineGeometry.peakCount(width: 0) == 1)
        #expect(AudioTimelineGeometry.peakCount(width: 9_000) == 400)
    }
}
