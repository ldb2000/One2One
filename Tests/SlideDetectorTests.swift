import Testing
import CoreGraphics
@testable import OneToOne

@Suite("SlideDetector")
struct SlideDetectorTests {

    private func feed(_ detector: inout SlideDetector, _ image: CGImage, times: Int) throws -> [SlideDetector.Decision] {
        let fp = try #require(SlideFingerprint(image: image))
        return (0..<times).map { _ in detector.consume(fp) }
    }

    private func banded(_ f: Double) -> CGImage { SlideImageFixtures.banded(fraction: f) }

    @Test("un écran statique dès le démarrage produit exactement la séquence attendue")
    func staticScreenSequence() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        let decisions = try feed(&detector, banded(0.3), times: 6)
        #expect(decisions == [.settling, .ignore, .newSlide, .ignore, .ignore, .ignore])
        #expect(detector.recordedCount == 1)
    }

    @Test("une transition animée ne produit qu'un slide de plus, celui de l'état final")
    func animatedTransitionProducesOneSlide() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        var decisions = try feed(&detector, banded(0.1), times: 4)
        for f in [0.25, 0.4, 0.55, 0.7, 0.85] { decisions += try feed(&detector, banded(f), times: 1) }
        #expect(decisions.filter { $0 == .newSlide }.count == 1)
        decisions += try feed(&detector, banded(0.9), times: 4)
        #expect(decisions.filter { $0 == .newSlide }.count == 2)
    }

    @Test("une vidéo qui tourne en continu ne produit aucun slide")
    func loopingVideoProducesNothing() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        var decisions: [SlideDetector.Decision] = []
        for i in 0..<40 { decisions += try feed(&detector, banded(i.isMultiple(of: 2) ? 0.2 : 0.8), times: 1) }
        #expect(decisions.filter { $0 == .newSlide }.isEmpty)
        #expect(detector.recordedCount == 0)
    }

    @Test("retour arrière : un seul doublon, jamais répété, puis le slide suivant est capturé")
    func duplicateOnceThenNextSlide() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        let first = banded(0.2), second = banded(0.8)
        #expect(try feed(&detector, first, times: 4) == [.settling, .ignore, .newSlide, .ignore])
        _ = try feed(&detector, second, times: 4)
        #expect(try feed(&detector, first, times: 4) == [.settling, .ignore, .duplicate, .ignore])
        let forward = try feed(&detector, banded(0.5), times: 4)
        #expect(forward.filter { $0 == .newSlide }.count == 1)
        #expect(detector.recordedCount == 3)
    }

    @Test("un changement sous le seuil ne déclenche rien")
    func noiseBelowThresholdIsIgnored() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        _ = try feed(&detector, banded(0.5), times: 4)
        let decisions = try feed(&detector, banded(0.505), times: 6)
        #expect(decisions.filter { $0 == .newSlide }.isEmpty)
        #expect(detector.recordedCount == 1)
    }

    @Test("une sensibilité faible ignore un changement qu'une sensibilité élevée détecte")
    func sensitivityChangesOutcome() throws {
        // écart ≈ 0,029 depuis 0,50 : au-dessus du seuil d'identité (0,020) et du seuil
        // élevé (0,010), sous le seuil faible (0,045).
        let modest = banded(0.53)
        func detected(_ s: SlideCaptureSettings.Sensitivity) throws -> Int {
            var d = SlideDetector(settings: SlideCaptureSettings(sensitivity: s))
            _ = try feed(&d, banded(0.5), times: 4)
            _ = try feed(&d, modest, times: 4)
            return d.recordedCount
        }
        #expect(try detected(.high) == 2)
        #expect(try detected(.low) == 1)
    }

    @Test("la sensibilité élevée ne rend pas l'anti-doublon laxiste : deux seuils distincts")
    func identityThresholdIsIndependentFromSensitivity() throws {
        // Avec un seuil unique à 0,010 (élevée), 0,50 puis 0,515 (écart ≈ 0,014) seraient
        // deux slides. Avec le seuil d'identité fixé à 0,020, le second est un doublon.
        var detector = SlideDetector(settings: SlideCaptureSettings(sensitivity: .high))
        _ = try feed(&detector, banded(0.50), times: 4)
        let decisions = try feed(&detector, banded(0.515), times: 4)
        #expect(decisions.contains(.duplicate))
        #expect(!decisions.contains(.newSlide))
        #expect(detector.recordedCount == 1)
    }

    @Test("aucun slide n'est écrit avant que stableTicksRequired soit atteint")
    func honoursStableTicksRequired() throws {
        var settings = SlideCaptureSettings()
        settings.stableTicksRequired = 3
        var detector = SlideDetector(settings: settings)
        let fp = try #require(SlideFingerprint(image: banded(0.3)))
        #expect(detector.consume(fp) == .settling)
        #expect(detector.consume(fp) == .ignore)
        #expect(detector.consume(fp) == .ignore)
        #expect(detector.consume(fp) == .newSlide)
    }

    @Test("une dérive lente finit par produire un nouveau slide")
    func slowDriftEventuallyProducesNewSlide() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        _ = try feed(&detector, banded(0.10), times: 4)
        var f = 0.10
        for _ in 0..<40 { f += 0.005; _ = try feed(&detector, banded(f), times: 1) }
        let final = try feed(&detector, banded(f), times: 4)
        #expect(final.contains(.newSlide))
        #expect(detector.recordedCount >= 2)
    }

    @Test("seed : un slide déjà connu est signalé comme doublon sans avoir été consommé")
    func seedMakesKnownSlidesDuplicates() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        let known = try #require(SlideFingerprint(image: banded(0.3)))
        detector.seed([known])
        #expect(detector.recordedCount == 1)
        let decisions = try feed(&detector, banded(0.3), times: 4)
        #expect(decisions == [.settling, .ignore, .duplicate, .ignore])
        let fresh = try feed(&detector, banded(0.8), times: 4)
        #expect(fresh.contains(.newSlide))
        #expect(detector.recordedCount == 2)
    }

    // MARK: - acknowledge (lot 7, port de Teams-Capture)

    @Test("acknowledge : le contenu qu'on vient de capturer à la main n'est pas réécrit")
    func acknowledgePreventsDoubleWrite() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        // Trois ticks sur la même image : le détecteur écrirait normalement au
        // troisième (`.newSlide`). On simule ici une capture manuelle arrivée
        // avant, sur ce même contenu.
        let fp = try #require(SlideFingerprint(image: banded(0.3)))
        detector.acknowledge(fp)
        #expect(detector.recordedCount == 1)

        let decisions = try feed(&detector, banded(0.3), times: 5)
        // Preuve par mutation : retirer `armed = false` de `acknowledge` fait
        // apparaître un `.duplicate` au deuxième tick — le détecteur
        // « conclurait » sur un contenu déjà écrit, et la bande afficherait
        // une décision là où il n'y a rien eu.
        #expect(decisions == [.ignore, .ignore, .ignore, .ignore, .ignore])
        #expect(detector.recordedCount == 1)
    }

    @Test("acknowledge : un contenu nouveau après la capture manuelle est toujours écrit")
    func acknowledgeDoesNotFreezeDetection() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        detector.acknowledge(try #require(SlideFingerprint(image: banded(0.2))))
        _ = try feed(&detector, banded(0.2), times: 2)

        let suite = try feed(&detector, banded(0.9), times: 4)
        #expect(suite.contains(.newSlide))
        #expect(detector.recordedCount == 2)
    }

    @Test("acknowledge : revenir au contenu capturé à la main le reconnaît en doublon")
    func acknowledgeRecordsForAntiDuplicate() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        detector.acknowledge(try #require(SlideFingerprint(image: banded(0.2))))

        // On s'éloigne : le nouveau contenu est bien écrit…
        let ailleurs = try feed(&detector, banded(0.9), times: 4)
        #expect(ailleurs.contains(.newSlide))

        // …puis on revient sur le contenu capturé à la main. Preuve par
        // mutation : sans le `recorded.append` d'`acknowledge`, ce retour
        // produit un `.newSlide` et la même image est écrite deux fois.
        let retour = try feed(&detector, banded(0.2), times: 4)
        #expect(retour.contains(.duplicate))
        #expect(!retour.contains(.newSlide))
    }

    @Test("acknowledge avant le premier tick ne fait pas repartir de .settling")
    func acknowledgeSeedsPrevious() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        detector.acknowledge(try #require(SlideFingerprint(image: banded(0.4))))
        // `previous` est posé par `acknowledge` : le tout premier tick n'est
        // donc plus un `.settling` gâché.
        let premier = try feed(&detector, banded(0.4), times: 1)
        #expect(premier == [.ignore])
    }

    @Test("acknowledge d'un contenu déjà enregistré n'ajoute pas de doublon dans l'historique")
    func acknowledgeIsIdempotent() throws {
        var detector = SlideDetector(settings: SlideCaptureSettings())
        let fp = try #require(SlideFingerprint(image: banded(0.5)))
        detector.acknowledge(fp)
        detector.acknowledge(fp)
        #expect(detector.recordedCount == 1)
    }
}
