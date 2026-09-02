# Capture automatique de slides — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer la capture de slides actuelle (flux `SCStream` + pHash, mode manuel) par une capture **automatique** d'une zone tracée sur une fenêtre choisie, avec détection de stabilité, arrêt/reprise sur le même lot, et reprise d'un lot existant après relance de l'app.

**Architecture:** Un module cœur pur et testé (`OneToOne/Services/SlideCapture/`) porte l'empreinte 32×32, la zone normalisée, le détecteur à états et la source ScreenCaptureKit par polling. `ScreenCaptureService` (réécrit, nom conservé) est le seul type qui enchaîne source → crop → détecteur → écriture `SlideCapture`/OCR, avec un jeton de session revérifié après chaque `await`. Le popover de configuration est réécrit en trois faces (configurer / suivre / reprendre-terminer) plus un écran de refus d'autorisation.

**Tech Stack:** Swift 5 mode (`swift-tools-version: 5.9`), macOS 15, SwiftUI, SwiftData, ScreenCaptureKit (`SCScreenshotManager`), CoreGraphics/ImageIO, Vision (OCR existant), Swift Testing pour les nouveaux tests.

**Spec:** `docs/superpowers/specs/2026-09-02-capture-auto-slides-design.md`

## Global Constraints

- Branche `feat/capture-auto-slides`, commits conventionnels, jamais de commit sur `master`.
- Aucune dépendance SwiftPM nouvelle. Le cœur de Teams-Capture est **copié**, pas lié.
- Commentaires et libellés UI en **français** ; symboles et code en anglais.
- Énumérations persistées SwiftData : champ `…Raw: String` + wrapper calculé. Un champ avec valeur par défaut = migration légère, **pas** de `SchemaV2`.
- Services : `@MainActor final class … : ObservableObject` (le service existant est injecté via `@ObservedObject` dans trois vues, on garde ce contrat).
- Les tests ne touchent **jamais** ScreenCaptureKit (`SCScreenshotManager` plante hors session graphique). Toute I/O ScreenCaptureKit passe par le protocole `FrameSource`, remplacé dans les tests.
- Constantes : polling 500 ms ; 2 ticks stables ; seuils de mouvement 0,010 / 0,020 / 0,045 (élevée / normale / faible) ; seuil d'identité 0,020 fixe ; fraction minimale de tracé 5 % ; fenêtre ≥ 200 pt.
- Fichiers `slide-NNNN-HHmmss.png` (**quatre** chiffres) dans `recordings/<meeting.ensuredStableID>/slides/`.
- `swift build` avant chaque commit d'une tâche qui touche l'app ; `swift test` complet avant la PR (~1500 tests, plusieurs minutes : lancer avec `--filter` pendant le développement).
- Commande de test ciblée : `swift test --filter <NomDeSuite>` (Swift Testing : le filtre matche le nom du type de suite).

---

## Carte des fichiers

| Fichier | Rôle | Tâche |
| --- | --- | --- |
| `OneToOne/Services/SlideCapture/SlideFingerprint.swift` | empreinte 32×32, distance, chargement depuis un PNG | 1 |
| `OneToOne/Services/SlideCapture/NormalizedRect.swift` | zone en fractions, tracé, crop | 1 |
| `Tests/SlideImageFixtures.swift` | images de test CoreGraphics | 1 |
| `Tests/SlideFingerprintTests.swift`, `Tests/NormalizedRectTests.swift` | | 1 |
| `OneToOne/Services/SlideCapture/SlideCaptureSettings.swift` | constantes, sensibilité, deux seuils | 2 |
| `OneToOne/Services/SlideCapture/SlideDetector.swift` | machine à états | 2 |
| `OneToOne/Models/AppSettings.swift` | `slideCaptureSensitivityRaw` | 2 |
| `Tests/SlideDetectorTests.swift` | | 2 |
| `OneToOne/Services/SlideCapture/FrameSource.swift` | protocole, `ShareableWindow`, `SlideCaptureError` | 3 |
| `OneToOne/Services/SlideCapture/WindowCatalog.swift` | filtre + tri des fenêtres | 3 |
| `OneToOne/Services/SlideCapture/WindowFrameSource.swift` | `SCScreenshotManager` par fenêtre | 3 |
| `Info.plist` | `NSScreenCaptureUsageDescription` | 3 |
| `Tests/SlideCaptureErrorTests.swift`, `Tests/WindowCatalogTests.swift` | | 3 |
| `OneToOne/Services/ScreenCaptureService.swift` | coordinateur réécrit | 4 |
| `OneToOne/Services/PerceptualHasher.swift` | **supprimé** | 4 |
| `Tests/ScreenCaptureServiceTestDoubles.swift`, `Tests/ScreenCaptureServiceTests.swift` | | 4 |
| `OneToOne/Views/CropSelectionView.swift` | aperçu + tracé | 5 |
| `OneToOne/Services/SlideCapture/ScreenRecordingSettingsLink.swift` | URLs des Réglages, repli | 5 |
| `Tests/ScreenRecordingSettingsLinkTests.swift` | | 5 |
| `OneToOne/Views/ScreenCaptureConfigView.swift` | popover réécrit | 6 |
| `OneToOne/Views/RectSelectorOverlay.swift` | **supprimé** | 6 |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift`, `Meeting/MeetingContextualRecorderBar.swift`, `MeetingView.swift` | câblage état / reprendre / terminer | 7 |
| `docs/adr/2026-09-02-capture-slides-polling-empreinte.md`, `STATUS.md` | | 8 |

---

### Task 1 : Empreinte et zone normalisée

**Files:**
- Create: `OneToOne/Services/SlideCapture/SlideFingerprint.swift`
- Create: `OneToOne/Services/SlideCapture/NormalizedRect.swift`
- Create: `Tests/SlideImageFixtures.swift`
- Test: `Tests/SlideFingerprintTests.swift`
- Test: `Tests/NormalizedRectTests.swift`

**Interfaces:**
- Produces: `struct SlideFingerprint: Equatable, Sendable` — `static let side = 32`, `let samples: [UInt8]`, `init(samples:)`, `init?(image: CGImage)`, `init?(contentsOf url: URL)`, `func distance(to:) -> Double`.
- Produces: `struct NormalizedRect: Equatable, Sendable, Codable` — `x, y, width, height: Double`, `static let full`, `init(x:y:width:height:)`, `init(from:to:in:)`, `static func fromDrag(from:to:in:minimumFraction:current:)`, `var isEmpty`, `func displayRect(in:) -> CGRect`, `func pixelRect(forWidth:height:) -> CGRect`, `func apply(to: CGImage) -> CGImage?`.
- Produces (tests) : `enum SlideImageFixtures` — `make(width:height:draw:)`, `solid(gray:width:height:)`, `banded(fraction:width:height:)`, `writePNG(_:to:)`.

- [ ] **Step 1 : Fixtures d'images de test**

`Tests/SlideImageFixtures.swift` :

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images de test pour la capture de slides. Le contexte fourni au closure a son
/// origine **en bas à gauche** (convention CoreGraphics) : un rectangle dessiné en
/// `y: 0` est le BAS de l'image à l'écran. Les tests d'axe en tiennent compte.
enum SlideImageFixtures {

    static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { fatalError("contexte de test non créable") }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(ctx)
        guard let image = ctx.makeImage() else { fatalError("image de test non créable") }
        return image
    }

    /// Image uniforme d'un gris donné (0 = noir, 1 = blanc).
    static func solid(gray: Double, width: Int = 400, height: Int = 300) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: gray, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Image blanche avec un bandeau noir couvrant `fraction` de la hauteur (en bas).
    /// Simule un changement de contenu d'ampleur contrôlée.
    static func banded(fraction: Double, width: Int = 400, height: Int = 300) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height) * fraction))
        }
    }

    /// Écrit une image en PNG, sans passer par le service : simule un lot déjà sur disque.
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
```

- [ ] **Step 2 : Tests de l'empreinte (échec attendu)**

`Tests/SlideFingerprintTests.swift` :

```swift
import Testing
import CoreGraphics
import Foundation
@testable import OneToOne

@Suite("SlideFingerprint")
struct SlideFingerprintTests {

    @Test("une empreinte est à distance nulle d'elle-même")
    func identity() throws {
        let fp = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.5)))
        #expect(fp.distance(to: fp) == 0)
    }

    @Test("noir et blanc uniformes sont à distance maximale")
    func opposites() throws {
        let black = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 0)))
        let white = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 1)))
        #expect(black.distance(to: white) > 0.95)
    }

    @Test("la distance est symétrique")
    func symmetry() throws {
        let a = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.2)))
        let b = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.8)))
        #expect(abs(a.distance(to: b) - b.distance(to: a)) < 1e-12)
    }

    @Test("un curseur de souris reste sous le seuil le plus sensible (0,010)")
    func cursorIsInvisible() throws {
        let plain = SlideImageFixtures.banded(fraction: 0.5)
        let withCursor = SlideImageFixtures.make(width: 400, height: 300) { ctx in
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 150))
            // un pointeur de 12x18 points, la taille réelle d'un curseur macOS
            ctx.setFillColor(gray: 0.2, alpha: 1)
            ctx.fill(CGRect(x: 200, y: 200, width: 12, height: 18))
        }
        let a = try #require(SlideFingerprint(image: plain))
        let b = try #require(SlideFingerprint(image: withCursor))
        #expect(a.distance(to: b) < 0.010)
    }

    @Test("un bandeau de 2 % de la hauteur donne une distance d'environ 0,019")
    func twoPercentBanner() throws {
        let a = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.50)))
        let b = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.52)))
        let d = a.distance(to: b)
        #expect(d > 0.015 && d < 0.025)
    }

    @Test("un changement de slide franchit même le seuil le moins sensible (0,045)")
    func slideChangeIsVisible() throws {
        let a = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.2)))
        let b = try #require(SlideFingerprint(image: SlideImageFixtures.banded(fraction: 0.7)))
        #expect(a.distance(to: b) > 0.045)
    }

    @Test("l'empreinte a toujours 32x32 échantillons")
    func fixedSize() throws {
        let fp = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 0.5, width: 1920, height: 1080)))
        #expect(fp.samples.count == 32 * 32)
    }

    @Test("une empreinte se lit depuis un PNG sur disque et vaut celle de l'image")
    func loadsFromPNG() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("slide-0001-101010.png")
        let image = SlideImageFixtures.banded(fraction: 0.3)
        try SlideImageFixtures.writePNG(image, to: url)

        let fromDisk = try #require(SlideFingerprint(contentsOf: url))
        let fromImage = try #require(SlideFingerprint(image: image))
        #expect(fromDisk.distance(to: fromImage) < 0.001)
        #expect(SlideFingerprint(contentsOf: dir.appendingPathComponent("absent.png")) == nil)
    }
}
```

- [ ] **Step 3 : Tests de la zone normalisée (échec attendu)**

`Tests/NormalizedRectTests.swift` :

```swift
import Testing
import CoreGraphics
@testable import OneToOne

@Suite("NormalizedRect")
struct NormalizedRectTests {

    @Test("la zone entière ne change pas les dimensions")
    func fullKeepsSize() throws {
        let image = SlideImageFixtures.solid(gray: 0.5, width: 800, height: 600)
        let cropped = try #require(NormalizedRect.full.apply(to: image))
        #expect(cropped.width == 800)
        #expect(cropped.height == 600)
    }

    @Test("une même zone normalisée survit au redimensionnement de la fenêtre")
    func survivesResize() throws {
        let zone = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let small = try #require(zone.apply(to: SlideImageFixtures.solid(gray: 0.5, width: 400, height: 300)))
        let large = try #require(zone.apply(to: SlideImageFixtures.solid(gray: 0.5, width: 800, height: 600)))
        #expect(small.width == 200)
        #expect(small.height == 150)
        #expect(large.width == 400)
        #expect(large.height == 300)
    }

    @Test("les coordonnées hors bornes sont ramenées dans 0...1")
    func clamping() {
        let zone = NormalizedRect(x: -0.5, y: 0.8, width: 3, height: 3)
        #expect(zone.x == 0)
        #expect(zone.y == 0.8)
        #expect(zone.width == 1)
        #expect(abs(zone.height - 0.2) < 1e-12)
    }

    @Test("une zone de surface nulle est vide et ne recadre rien")
    func degenerate() {
        let zone = NormalizedRect(x: 0.5, y: 0.5, width: 0, height: 0.3)
        #expect(zone.isEmpty)
        #expect(zone.apply(to: SlideImageFixtures.solid(gray: 0.5)) == nil)
    }

    @Test("le crop y=0 porte sur le HAUT de l'image à l'écran")
    func topLeftOrigin() throws {
        // CoreGraphics dessine origine en bas : ce rectangle est la moitié BASSE.
        let image = SlideImageFixtures.make(width: 100, height: 100) { ctx in
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }
        // y = 0, hauteur 0,5 → moitié HAUTE à l'écran, donc la partie blanche.
        let top = try #require(NormalizedRect(x: 0, y: 0, width: 1, height: 0.5).apply(to: image))
        let fp = try #require(SlideFingerprint(image: top))
        let white = try #require(SlideFingerprint(image: SlideImageFixtures.solid(gray: 1)))
        #expect(fp.distance(to: white) < 0.02)
    }

    @Test("un glissement sous le seuil des 5 % laisse la zone actuelle inchangée")
    func dragBelowThresholdKeepsCurrent() {
        let size = CGSize(width: 400, height: 400)
        let current = NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let result = NormalizedRect.fromDrag(
            from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 60), in: size, current: current
        )
        #expect(result == current)
    }

    @Test("les quatre composantes du glissement sont ancrées sur des valeurs asymétriques")
    func dragCandidateAsymmetricComponents() {
        // Vue bien plus large que haute, glissement dans le quart supérieur gauche :
        // quatre valeurs attendues toutes distinctes, y proche de 0 (le haut). Une
        // inversion d'axe Y ou une confusion x/y ferait échouer ce test, contrairement
        // au test d'aller-retour ci-dessous.
        let size = CGSize(width: 1000, height: 200)
        let result = NormalizedRect.fromDrag(
            from: CGPoint(x: 100, y: 10), to: CGPoint(x: 250, y: 70), in: size, current: .full
        )
        #expect(abs(result.x - 0.1) < 1e-12)
        #expect(abs(result.y - 0.05) < 1e-12)
        #expect(abs(result.width - 0.15) < 1e-12)
        #expect(abs(result.height - 0.3) < 1e-12)
    }

    @Test("l'ordre des deux points du glissement est indifférent")
    func dragDirectionAgnostic() {
        let size = CGSize(width: 400, height: 400)
        let forward = NormalizedRect.fromDrag(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 300, y: 200), in: size, current: .full)
        let backward = NormalizedRect.fromDrag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), in: size, current: .full)
        #expect(forward == backward)
    }

    @Test("un glissement débordant est borné, une vue de taille nulle ne casse rien")
    func dragClampsAndTolerantToDegenerateSize() {
        let overflow = NormalizedRect.fromDrag(
            from: CGPoint(x: -200, y: -200), to: CGPoint(x: 900, y: 900),
            in: CGSize(width: 400, height: 400), current: .full
        )
        #expect(overflow.x >= 0 && overflow.width <= 1 && !overflow.isEmpty)

        let current = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        for size in [CGSize(width: 0, height: 100), CGSize(width: 100, height: -10), .zero] {
            let r = NormalizedRect.fromDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50), in: size, current: current)
            #expect(r.x >= 0 && r.x <= 1 && r.width >= 0 && r.width <= 1)
        }
    }

    @Test("displayRect suit la convention haut-gauche, sans inversion d'axe Y")
    func displayRectTopLeftConvention() {
        let zone = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        #expect(zone.displayRect(in: CGSize(width: 800, height: 400)) == CGRect(x: 200, y: 200, width: 400, height: 100))
    }

    @Test("la zone survit à un aller-retour Codable")
    func codableRoundTrip() throws {
        let zone = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let data = try JSONEncoder().encode(zone)
        #expect(try JSONDecoder().decode(NormalizedRect.self, from: data) == zone)
    }
}
```

- [ ] **Step 4 : Vérifier l'échec**

Run : `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected : erreurs `cannot find 'SlideFingerprint' in scope`, `cannot find 'NormalizedRect' in scope`.

- [ ] **Step 5 : Implémenter `SlideFingerprint`**

`OneToOne/Services/SlideCapture/SlideFingerprint.swift` :

```swift
import CoreGraphics
import Foundation
import ImageIO

/// Signature compacte d'une image, conçue pour comparer deux captures successives.
///
/// La réduction à 32×32 en niveaux de gris est le cœur de la robustesse du détecteur :
/// à cette échelle un curseur de souris ou du bruit de compression pèsent moins d'un
/// millième de la surface, alors qu'un changement de slide en modifie une large part.
struct SlideFingerprint: Equatable, Sendable {

    /// Côté de l'empreinte, en échantillons.
    static let side = 32

    /// Luminances, ligne par ligne, `side * side` éléments.
    let samples: [UInt8]

    init(samples: [UInt8]) {
        precondition(samples.count == SlideFingerprint.side * SlideFingerprint.side,
                     "une empreinte fait exactement \(SlideFingerprint.side * SlideFingerprint.side) échantillons")
        self.samples = samples
    }

    /// Réduit l'image en empreinte. Retourne `nil` si CoreGraphics refuse le contexte.
    init?(image: CGImage) {
        let side = SlideFingerprint.side
        guard let space = CGColorSpace(name: CGColorSpace.linearGray) else { return nil }
        var buffer = [UInt8](repeating: 0, count: side * side)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side, space: space,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            // `.high` fait une vraie moyenne des pixels sources ; c'est ce qui rend
            // l'empreinte insensible au curseur. Ne pas baisser cette qualité.
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        self.samples = buffer
    }

    /// Empreinte d'un PNG sur disque (réamorçage d'un lot existant). `nil` si le
    /// fichier est absent ou illisible.
    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image: image)
    }

    /// Écart moyen normalisé entre deux empreintes.
    /// `0` = images identiques, `1` = noir uniforme contre blanc uniforme.
    func distance(to other: SlideFingerprint) -> Double {
        var total = 0
        for index in samples.indices {
            total += abs(Int(samples[index]) - Int(other.samples[index]))
        }
        return Double(total) / (Double(samples.count) * 255.0)
    }
}
```

- [ ] **Step 6 : Implémenter `NormalizedRect`**

`OneToOne/Services/SlideCapture/NormalizedRect.swift` :

```swift
import CoreGraphics

/// Zone rectangulaire exprimée en fraction des dimensions de son support.
///
/// Stocker la zone en proportions et non en pixels est ce qui permet au cadrage de
/// survivre à un redimensionnement de la fenêtre source ou à un changement d'écran.
///
/// Convention : l'origine `(0, 0)` est en **haut à gauche**, comme les coordonnées
/// locales SwiftUI et comme `CGImage.cropping(to:)`.
struct NormalizedRect: Equatable, Sendable, Codable {

    let x: Double
    let y: Double
    let width: Double
    let height: Double

    /// La totalité du support.
    static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    /// Les valeurs sont ramenées dans `0…1` et la taille est réduite pour ne pas
    /// dépasser le bord : une zone invalide est impossible à construire.
    init(x: Double, y: Double, width: Double, height: Double) {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        self.x = clampedX
        self.y = clampedY
        self.width = min(max(width, 0), 1 - clampedX)
        self.height = min(max(height, 0), 1 - clampedY)
    }

    /// Zone décrite par un glissement entre deux points dans une vue de taille `size`.
    /// L'ordre des points est indifférent.
    init(from start: CGPoint, to end: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { self = .full; return }
        self.init(
            x: Double(min(start.x, end.x)) / Double(size.width),
            y: Double(min(start.y, end.y)) / Double(size.height),
            width: Double(abs(end.x - start.x)) / Double(size.width),
            height: Double(abs(end.y - start.y)) / Double(size.height)
        )
    }

    /// Vrai si la zone n'a pas de surface exploitable.
    var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Zone candidate produite par un glissement. Sous `minimumFraction` sur l'un des
    /// deux axes, un glissement accidentel ne doit pas rendre le cadrage inutilisable :
    /// `current` est renvoyée inchangée. Fonction pure, sans SwiftUI : testable sans geste.
    static func fromDrag(
        from start: CGPoint,
        to end: CGPoint,
        in size: CGSize,
        minimumFraction: Double = 0.05,
        current: NormalizedRect
    ) -> NormalizedRect {
        let candidate = NormalizedRect(from: start, to: end, in: size)
        guard candidate.width > minimumFraction, candidate.height > minimumFraction else {
            return current
        }
        return candidate
    }

    /// Rectangle d'affichage pour une vue de taille `size`, inverse de `init(from:to:in:)`.
    /// L'appelant passe la taille d'affichage réelle de l'image : aucun décalage aspect-fit.
    func displayRect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    /// Zone en pixels pour un support donné, arrondie sur la grille et bornée.
    func pixelRect(forWidth imageWidth: Int, height imageHeight: Int) -> CGRect {
        let rect = CGRect(
            x: (x * Double(imageWidth)).rounded(.down),
            y: (y * Double(imageHeight)).rounded(.down),
            width: (width * Double(imageWidth)).rounded(),
            height: (height * Double(imageHeight)).rounded()
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }

    /// Recadre l'image. `nil` si la zone est vide ou le crop impossible.
    func apply(to image: CGImage) -> CGImage? {
        guard !isEmpty else { return nil }
        let rect = pixelRect(forWidth: image.width, height: image.height)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return image.cropping(to: rect)
    }
}
```

- [ ] **Step 7 : Vérifier le vert**

Run : `swift test --filter "SlideFingerprintTests|NormalizedRectTests" 2>&1 | tail -15`
Expected : `Test run with 19 tests passed` (8 + 11), 0 failures.

- [ ] **Step 8 : Preuve par mutation, axe Y**

Dans `NormalizedRect.displayRect(in:)`, remplacer temporairement `y: y * size.height` par `y: (1 - y - height) * size.height`. Run : `swift test --filter NormalizedRectTests 2>&1 | grep -E "displayRectTopLeftConvention|failed"`. Expected : `displayRectTopLeftConvention` **échoue**. Rétablir, relancer, vert.

- [ ] **Step 9 : Commit**

```bash
git add OneToOne/Services/SlideCapture/SlideFingerprint.swift OneToOne/Services/SlideCapture/NormalizedRect.swift Tests/SlideImageFixtures.swift Tests/SlideFingerprintTests.swift Tests/NormalizedRectTests.swift
git commit -m "feat(capture): empreinte 32x32 et zone normalisee, module coeur de la capture de slides"
```

---

### Task 2 : Réglages, détecteur, sensibilité persistée

**Files:**
- Create: `OneToOne/Services/SlideCapture/SlideCaptureSettings.swift`
- Create: `OneToOne/Services/SlideCapture/SlideDetector.swift`
- Modify: `OneToOne/Models/AppSettings.swift` (après `captureBlacklistJSON`, ~ligne 191)
- Test: `Tests/SlideDetectorTests.swift`

**Interfaces:**
- Consumes: `SlideFingerprint` (Task 1).
- Produces: `struct SlideCaptureSettings: Equatable, Sendable` — `enum Sensitivity: String, CaseIterable, Identifiable, Sendable { low, normal, high; var movementThreshold: Double; var label: String }`, `var tickInterval: Duration = .milliseconds(500)`, `var stableTicksRequired = 2`, `var sensitivity`, `var movementThreshold`, `var identityThreshold = 0.020`, `static let minimumWindowSide: CGFloat = 200`, `init(sensitivity:)`.
- Produces: `struct SlideDetector: Sendable` — `enum Decision { settling, ignore, newSlide, duplicate }`, `init(settings:)`, `var recordedCount`, `mutating func consume(_:) -> Decision`, `mutating func seed(_ recorded: [SlideFingerprint])`.
- Produces: `AppSettings.slideCaptureSensitivityRaw: String`, `AppSettings.slideCaptureSensitivity: SlideCaptureSettings.Sensitivity`.

- [ ] **Step 1 : Tests du détecteur (échec attendu)**

`Tests/SlideDetectorTests.swift` :

```swift
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
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run : `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected : `cannot find 'SlideDetector' in scope`.

- [ ] **Step 3 : Implémenter `SlideCaptureSettings`**

`OneToOne/Services/SlideCapture/SlideCaptureSettings.swift` :

```swift
import CoreGraphics
import Foundation

/// Toutes les valeurs numériques réglables de la capture de slides, en un seul endroit.
struct SlideCaptureSettings: Equatable, Sendable {

    /// Sensibilité de la détection de **mouvement**. Plus elle est élevée, plus le seuil
    /// de changement est bas. Elle n'agit pas sur l'anti-doublon (`identityThreshold`).
    enum Sensitivity: String, CaseIterable, Identifiable, Sendable {
        case low, normal, high

        var id: String { rawValue }

        /// Écart moyen normalisé (image N contre N−1) à partir duquel « ça bouge ».
        /// Points de départ issus de la spec source, à affiner sur une réunion réelle.
        var movementThreshold: Double {
            switch self {
            case .high: return 0.010
            case .normal: return 0.020
            case .low: return 0.045
            }
        }

        var label: String {
            switch self {
            case .high: return "Élevée"
            case .normal: return "Normale"
            case .low: return "Faible"
            }
        }
    }

    /// Période de polling de la source.
    var tickInterval: Duration = .milliseconds(500)

    /// Ticks stables consécutifs exigés avant d'écrire. À 500 ms par tick, 2 laisse
    /// environ une seconde à une transition animée pour se terminer.
    var stableTicksRequired: Int = 2

    var sensitivity: Sensitivity = .normal

    var movementThreshold: Double { sensitivity.movementThreshold }

    /// Seuil d'**identité** pour l'anti-doublon (image contre l'historique enregistré).
    /// Indépendant de la sensibilité : la coupler rendait l'anti-doublon laxiste quand
    /// on augmentait la sensibilité (piège 5 de la spec source).
    var identityThreshold: Double = 0.020

    /// Une fenêtre plus petite ne peut pas contenir un slide lisible.
    static let minimumWindowSide: CGFloat = 200

    init(sensitivity: Sensitivity = .normal) {
        self.sensitivity = sensitivity
    }
}
```

- [ ] **Step 4 : Implémenter `SlideDetector`**

`OneToOne/Services/SlideCapture/SlideDetector.swift` :

```swift
/// Décide, à partir d'une suite d'empreintes, quand un nouveau slide doit être enregistré.
///
/// On n'écrit jamais une image en mouvement. Tout écart au-dessus du seuil de mouvement
/// « arme » l'attente ; l'écriture n'a lieu qu'une fois l'image stable pendant
/// `stableTicksRequired` ticks. Le détecteur se réarme aussi quand l'écran s'est éloigné
/// du dernier slide **acquitté**, même si aucun tick isolé n'a franchi le seuil : sans
/// cela, une dérive lente (fondu, Morph, défilement lent d'un PDF) ne produirait jamais
/// rien.
///
/// Ce type ne fait aucune I/O : déterministe et testable par séquences de décisions.
struct SlideDetector: Sendable {

    enum Decision: Equatable, Sendable {
        /// Le contenu bouge, ou il n'y a pas encore de référence : on attend.
        case settling
        /// Contenu stable déjà traité : rien à faire.
        case ignore
        /// Un nouveau slide vient de se stabiliser : l'appelant doit l'écrire.
        case newSlide
        /// Slide déjà enregistré dans cette session : ne pas réécrire.
        case duplicate
    }

    private let movementThreshold: Double
    private let identityThreshold: Double
    private let stableTicksRequired: Int

    private var previous: SlideFingerprint?
    private var stableTicks = 0
    /// Armé dès la construction : sinon le slide déjà affiché au démarrage ne serait
    /// jamais écrit, et le slide de titre serait systématiquement perdu.
    private var armed = true
    private var recorded: [SlideFingerprint] = []
    /// Dernier slide acquitté (écrit **ou** reconnu doublon) : ce qui est réellement à
    /// l'écran, contrairement à `recorded.last` qui, après un doublon, ne l'est plus.
    private var acknowledged: SlideFingerprint?

    init(settings: SlideCaptureSettings) {
        self.movementThreshold = settings.movementThreshold
        self.identityThreshold = settings.identityThreshold
        self.stableTicksRequired = max(1, settings.stableTicksRequired)
    }

    /// Nombre de slides retenus (ceux consommés et ceux réamorcés par `seed`).
    var recordedCount: Int { recorded.count }

    /// Ajoute des empreintes déjà connues à l'historique anti-doublon, sans toucher à
    /// l'état de stabilisation. Sert à reprendre un lot existant.
    mutating func seed(_ known: [SlideFingerprint]) {
        recorded.append(contentsOf: known)
    }

    mutating func consume(_ fingerprint: SlideFingerprint) -> Decision {
        defer { previous = fingerprint }

        guard let previous else { return .settling }

        if fingerprint.distance(to: previous) >= movementThreshold {
            armed = true
            stableTicks = 0
            return .settling
        }

        // Dérive lente : aucun tick n'a franchi le seuil, mais l'écran s'est éloigné du
        // slide acquitté.
        if !armed, let acknowledged, fingerprint.distance(to: acknowledged) >= movementThreshold {
            armed = true
            stableTicks = 0
        }

        stableTicks += 1
        guard armed, stableTicks >= stableTicksRequired else { return .ignore }

        armed = false
        stableTicks = 0

        if recorded.contains(where: { $0.distance(to: fingerprint) < identityThreshold }) {
            acknowledged = fingerprint
            return .duplicate
        }
        recorded.append(fingerprint)
        acknowledged = fingerprint
        return .newSlide
    }
}
```

- [ ] **Step 5 : Vérifier le vert**

Run : `swift test --filter SlideDetectorTests 2>&1 | tail -8`
Expected : 10 tests passed.

- [ ] **Step 6 : Preuve par mutation, dérive lente**

Dans `consume`, commenter le bloc `if !armed, let acknowledged, …`. Run : `swift test --filter SlideDetectorTests 2>&1 | grep -E "slowDrift|failed"`. Expected : `slowDriftEventuallyProducesNewSlide` **échoue**. Rétablir, relancer, vert.

- [ ] **Step 7 : Sensibilité persistée dans `AppSettings`**

Dans `OneToOne/Models/AppSettings.swift`, juste après la déclaration de `captureBlacklistJSON` :

```swift
    /// Sensibilité de la capture automatique de slides. Stockée en `…Raw`
    /// (contournement du bug SwiftData sur les énumérations persistées).
    var slideCaptureSensitivityRaw: String = SlideCaptureSettings.Sensitivity.normal.rawValue
    var slideCaptureSensitivity: SlideCaptureSettings.Sensitivity {
        get { SlideCaptureSettings.Sensitivity(rawValue: slideCaptureSensitivityRaw) ?? .normal }
        set { slideCaptureSensitivityRaw = newValue.rawValue }
    }
```

Run : `swift build 2>&1 | grep -E "error:" ; echo "build ok si vide"`. Expected : vide.

- [ ] **Step 8 : Commit**

```bash
git add OneToOne/Services/SlideCapture/SlideCaptureSettings.swift OneToOne/Services/SlideCapture/SlideDetector.swift OneToOne/Models/AppSettings.swift Tests/SlideDetectorTests.swift
git commit -m "feat(capture): detecteur de slides a stabilisation, deux seuils, sensibilite persistee"
```

---

### Task 3 : Source d'images, catalogue de fenêtres, erreurs

**Files:**
- Create: `OneToOne/Services/SlideCapture/FrameSource.swift`
- Create: `OneToOne/Services/SlideCapture/WindowCatalog.swift`
- Create: `OneToOne/Services/SlideCapture/WindowFrameSource.swift`
- Modify: `Info.plist`
- Test: `Tests/SlideCaptureErrorTests.swift`
- Test: `Tests/WindowCatalogTests.swift`

**Interfaces:**
- Consumes: `SlideCaptureSettings.minimumWindowSide` (Task 2).
- Produces: `protocol FrameSource: Sendable { func captureFrame() async throws -> CGImage? }`.
- Produces: `struct ShareableWindow: Identifiable, Equatable, Sendable` — `id: CGWindowID`, `title`, `appName`, `bundleIdentifier: String?`, `frame: CGRect`, `var isMeetingApp: Bool`, `var displayName: String`.
- Produces: `enum SlideCaptureError: Error, Equatable, LocalizedError { screenRecordingDenied, noShareableWindows, captureFailed(String) }`, `static func isPermissionDenial(_:) -> Bool`.
- Produces: `enum WindowCatalog` — `static func shareableWindows(excludingAppNames: Set<String>) async throws -> [ShareableWindow]`, `static func filtered(_:excludingAppNames:) -> [ShareableWindow]`, `static func prioritized(_:) -> [ShareableWindow]`, `static let ownAppNames: Set<String>`.
- Produces: `struct WindowFrameSource: FrameSource` — `init(windowID: CGWindowID, scale: Int = 2)`.

- [ ] **Step 1 : Tests (échec attendu)**

`Tests/SlideCaptureErrorTests.swift` :

```swift
import Testing
import Foundation
import ScreenCaptureKit
@testable import OneToOne

@Suite("SlideCaptureError")
struct SlideCaptureErrorTests {

    @Test("domaine SCStream + code userDeclined = refus d'autorisation")
    func recognizesUserDeclined() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue, userInfo: nil)
        #expect(SlideCaptureError.isPermissionDenial(error) == true)
    }

    @Test("domaine SCStream avec un autre code : pas un refus")
    func rejectsWrongCode() {
        let error = NSError(domain: SCStreamErrorDomain, code: -1, userInfo: nil)
        #expect(SlideCaptureError.isPermissionDenial(error) == false)
    }

    @Test("le code userDeclined dans un autre domaine : pas un refus")
    func rejectsWrongDomain() {
        let error = NSError(domain: NSCocoaErrorDomain, code: SCStreamError.Code.userDeclined.rawValue, userInfo: nil)
        #expect(SlideCaptureError.isPermissionDenial(error) == false)
    }

    @Test("une erreur déjà traduite est reconnue selon son cas")
    func recognizesTranslatedError() {
        #expect(SlideCaptureError.isPermissionDenial(SlideCaptureError.screenRecordingDenied) == true)
        #expect(SlideCaptureError.isPermissionDenial(SlideCaptureError.noShareableWindows) == false)
        #expect(SlideCaptureError.isPermissionDenial(SlideCaptureError.captureFailed("x")) == false)
    }
}
```

`Tests/WindowCatalogTests.swift` :

```swift
import Testing
import CoreGraphics
@testable import OneToOne

@Suite("WindowCatalog")
struct WindowCatalogTests {

    private func window(_ id: CGWindowID, _ title: String, _ app: String, _ bundle: String?, w: CGFloat, h: CGFloat) -> ShareableWindow {
        ShareableWindow(id: id, title: title, appName: app, bundleIdentifier: bundle, frame: CGRect(x: 0, y: 0, width: w, height: h))
    }

    @Test("Teams, Zoom et Meet passent devant, puis surface décroissante")
    func meetingAppsFirstThenArea() {
        let windows = [
            window(1, "Notes", "Notes", "com.apple.Notes", w: 1600, h: 1000),
            window(2, "Réunion", "Microsoft Teams", "com.microsoft.teams2", w: 800, h: 600),
            window(3, "Meet – Point hebdo", "Google Chrome", "com.google.Chrome", w: 900, h: 600),
            window(4, "Zoom Meeting", "zoom.us", "us.zoom.xos", w: 1000, h: 700),
            window(5, "Mail", "Mail", "com.apple.mail", w: 1200, h: 800),
        ]
        let sorted = WindowCatalog.prioritized(windows).map(\.id)
        #expect(sorted == [4, 3, 2, 1, 5])
    }

    @Test("les fenêtres de OneToOne, la liste noire, les petites et les sans-titre sont écartées")
    func filtering() {
        let windows = [
            window(1, "Réunion", "OneToOne", "com.onetoone.app", w: 1000, h: 800),
            window(2, "Réunion", "Microsoft Teams", "com.microsoft.teams2", w: 1000, h: 800),
            window(3, "Palette", "Microsoft Teams", "com.microsoft.teams2", w: 199, h: 800),
            window(4, "", "Microsoft Teams", "com.microsoft.teams2", w: 1000, h: 800),
            window(5, "Slack", "Slack", "com.tinyspeck.slackmacgap", w: 1000, h: 800),
        ]
        let kept = WindowCatalog.filtered(windows, excludingAppNames: ["slack"]).map(\.id)
        #expect(kept == [2])
    }

    @Test("le nom affiché combine application et titre, ou l'application seule")
    func displayName() {
        #expect(window(1, "Hebdo", "Microsoft Teams", nil, w: 1, h: 1).displayName == "Microsoft Teams — Hebdo")
        #expect(window(2, "", "Safari", nil, w: 1, h: 1).displayName == "Safari")
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run : `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected : `cannot find 'SlideCaptureError' in scope`, `cannot find 'ShareableWindow' in scope`.

- [ ] **Step 3 : Implémenter `FrameSource.swift`**

```swift
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Fournit l'état courant d'une source d'images.
protocol FrameSource: Sendable {
    /// Capture l'état courant. Retourne `nil` si la source a **disparu** (fenêtre
    /// fermée, application quittée) : l'appelant met la session en pause. Lève une
    /// erreur sur tout **échec** d'API : visible, sans arrêter la session. Aucune
    /// implémentation ne doit convertir un échec en `nil`.
    func captureFrame() async throws -> CGImage?
}

/// Une fenêtre proposée à l'utilisateur comme source de capture.
struct ShareableWindow: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleIdentifier: String?
    let frame: CGRect

    init(id: CGWindowID, title: String, appName: String, bundleIdentifier: String?, frame: CGRect) {
        self.id = id
        self.title = title
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
    }

    /// Identifiants des applications de réunion à placer en tête.
    static let meetingBundleIdentifiers: Set<String> = [
        "com.microsoft.teams2", "com.microsoft.teams", "us.zoom.xos"
    ]

    /// Teams, Zoom, ou un onglet Google Meet (Meet vit dans un navigateur : on
    /// reconnaît le titre).
    var isMeetingApp: Bool {
        if let bundleIdentifier, ShareableWindow.meetingBundleIdentifiers.contains(bundleIdentifier) { return true }
        return title.localizedCaseInsensitiveContains("meet")
    }

    var displayName: String {
        title.isEmpty ? appName : "\(appName) — \(title)"
    }
}

enum SlideCaptureError: Error, Equatable, LocalizedError {
    case screenRecordingDenied
    case noShareableWindows
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "OneToOne n'a pas l'autorisation d'enregistrer l'écran."
        case .noShareableWindows:
            return "Aucune fenêtre partageable n'a été trouvée."
        case .captureFailed(let reason):
            return "La capture a échoué : \(reason)"
        }
    }

    /// Vrai si l'erreur correspond à un refus d'autorisation d'enregistrement d'écran.
    /// Fonction pure : le domaine **et** le code sont exigés (le même code dans un autre
    /// domaine n'est pas un refus).
    static func isPermissionDenial(_ error: any Error) -> Bool {
        if let captureError = error as? SlideCaptureError {
            return captureError == .screenRecordingDenied
        }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }
}
```

- [ ] **Step 4 : Implémenter `WindowCatalog.swift`**

```swift
import CoreGraphics
import ScreenCaptureKit

/// Énumère les fenêtres que l'utilisateur peut choisir comme source.
enum WindowCatalog {

    /// Noms (minuscules) sous lesquels l'app elle-même apparaît : à exclure de la liste.
    static let ownAppNames: Set<String> = ["onetoone", "one2one"]

    /// Fenêtres à l'écran, filtrées et triées. Traduit le refus d'autorisation.
    static func shareableWindows(excludingAppNames blacklist: Set<String>) async throws -> [ShareableWindow] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }
        let windows = content.windows.map {
            ShareableWindow(
                id: $0.windowID,
                title: $0.title ?? "",
                appName: $0.owningApplication?.applicationName ?? "Application inconnue",
                bundleIdentifier: $0.owningApplication?.bundleIdentifier,
                frame: $0.frame
            )
        }
        let kept = filtered(windows, excludingAppNames: blacklist)
        guard !kept.isEmpty else { throw SlideCaptureError.noShareableWindows }
        return prioritized(kept)
    }

    /// Écarte les fenêtres de OneToOne, celles de la liste noire (noms d'app, insensible
    /// à la casse), les fenêtres sans titre et celles trop petites pour un slide lisible.
    static func filtered(_ windows: [ShareableWindow], excludingAppNames blacklist: Set<String>) -> [ShareableWindow] {
        let excluded = ownAppNames.union(blacklist.map { $0.lowercased() })
        let minimum = SlideCaptureSettings.minimumWindowSide
        return windows.filter { w in
            !w.title.isEmpty
                && w.frame.width >= minimum && w.frame.height >= minimum
                && !excluded.contains(w.appName.lowercased())
        }
    }

    /// Applications de réunion en tête, puis surface décroissante : la fenêtre de
    /// réunion, la plus grande, arrive naturellement en premier.
    static func prioritized(_ windows: [ShareableWindow]) -> [ShareableWindow] {
        windows.sorted { l, r in
            if l.isMeetingApp != r.isMeetingApp { return l.isMeetingApp }
            return l.frame.width * l.frame.height > r.frame.width * r.frame.height
        }
    }
}
```

- [ ] **Step 5 : Implémenter `WindowFrameSource.swift`**

```swift
import CoreGraphics
import ScreenCaptureKit

/// Capture une fenêtre précise via ScreenCaptureKit, un appel par tick.
///
/// Le filtre est **reconstruit à chaque capture**. C'est volontaire : cela absorbe le
/// déplacement, le redimensionnement et le changement d'écran de la fenêtre source sans
/// aucun code de reconfiguration. Ne pas le mettre en cache « pour optimiser ».
///
/// ⚠️ `SCScreenshotManager` plante (`CGS_REQUIRE_INIT`) hors session graphique : les
/// tests ne construisent jamais ce type, ils remplacent `FrameSource`.
struct WindowFrameSource: FrameSource {

    let windowID: CGWindowID
    /// 2 sur un écran Retina, pour capturer à la résolution native.
    let scale: Int

    init(windowID: CGWindowID, scale: Int = 2) {
        self.windowID = windowID
        self.scale = max(1, scale)
    }

    func captureFrame() async throws -> CGImage? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }

        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil // la fenêtre a disparu
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width) * scale
        configuration.height = Int(window.frame.height) * scale
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 6 : `Info.plist`**

Ajouter, après la paire `NSMicrophoneUsageDescription`, avant `</dict>` :

```xml
	<key>NSScreenCaptureUsageDescription</key>
	<string>OneToOne capture les slides projetées pendant vos réunions pour les retranscrire et les joindre au compte-rendu.</string>
```

- [ ] **Step 7 : Vérifier le vert**

Run : `swift test --filter "SlideCaptureErrorTests|WindowCatalogTests" 2>&1 | tail -8`
Expected : 7 tests passed. Puis `swift build 2>&1 | grep -E "error:"` → vide.

- [ ] **Step 8 : Commit**

```bash
git add OneToOne/Services/SlideCapture/FrameSource.swift OneToOne/Services/SlideCapture/WindowCatalog.swift OneToOne/Services/SlideCapture/WindowFrameSource.swift Info.plist Tests/SlideCaptureErrorTests.swift Tests/WindowCatalogTests.swift
git commit -m "feat(capture): source ScreenCaptureKit par polling, catalogue de fenetres, traduction du refus"
```

---

### Task 4 : `ScreenCaptureService` réécrit — sessions, ticks, reprise

**Files:**
- Rewrite: `OneToOne/Services/ScreenCaptureService.swift`
- Delete: `OneToOne/Services/PerceptualHasher.swift`
- Create: `Tests/ScreenCaptureServiceTestDoubles.swift`
- Test: `Tests/ScreenCaptureServiceTests.swift`

**Interfaces:**
- Consumes: `FrameSource`, `SlideCaptureError` (Task 3), `SlideDetector`, `SlideCaptureSettings` (Task 2), `SlideFingerprint`, `NormalizedRect` (Task 1), modèles `Meeting`, `MeetingAttachment(url:kind:)`, `SlideCapture(index:capturedAt:imagePath:)`, `Meeting.ensuredStableID`, `OCRService.recognize(cgImage:)`, `MeetingAttachmentService.reindexAttachment(_:context:)`.
- Produces (utilisé par les vues, Tasks 6-7) :

```swift
@MainActor final class ScreenCaptureService: ObservableObject
  enum State: Equatable { case idle, running, paused(String), stopped ; var isPaused: Bool }
  struct SessionConfiguration: Equatable { var windowID: CGWindowID; var windowTitle: String; var crop: NormalizedRect; var sensitivity: SlideCaptureSettings.Sensitivity }
  enum SessionError: Error, Equatable { case sessionAlreadyOpen, noOpenSession }
  @Published private(set) var state: State
  @Published private(set) var currentAttachment: MeetingAttachment?
  @Published private(set) var configuration: SessionConfiguration?
  @Published var lastError: String?
  @Published private(set) var ocrProgress: (current: Int, total: Int)?
  var isCapturing: Bool            // running ou paused (compat barres)
  var hasOpenSession: Bool          // currentAttachment != nil
  var capturedSlidesCount: Int
  init(recordingsRoot: URL? = nil, frameSourceFactory: FrameSourceFactory = …, ocr: OCRFunction = …, reindex: ReindexFunction = …)
  func beginSession(configuration:meeting:context:appendTo: MeetingAttachment? = nil) throws
  func start(configuration:meeting:context:appendTo:) throws   // beginSession + boucle
  func resume()                     // depuis stopped
  func stop()                       // running/paused → stopped, boucle annulée
  func finish() async               // clôt : OCR, save, reindex, idle
  func updateSource(windowID:title:) // en stopped seulement
  func snapshot()                   // en running : écriture forcée
  func tick() async
  func deleteSlide(_:)
```

- [ ] **Step 1 : Doublures de test**

`Tests/ScreenCaptureServiceTestDoubles.swift` :

```swift
import Foundation
import CoreGraphics
@testable import OneToOne

/// Source scriptée : rend les images dans l'ordre, puis `nil` (source disparue).
final class ScriptedFrameSource: FrameSource, @unchecked Sendable {
    private var frames: [CGImage?]
    private var index = 0
    private let lock = NSLock()

    init(frames: [CGImage?]) { self.frames = frames }

    func captureFrame() async throws -> CGImage? {
        lock.withLock {
            guard index < frames.count else { return nil }
            defer { index += 1 }
            return frames[index]
        }
    }
}

/// Source qui peut aussi lever une erreur : couvre le chemin « échec de capture »,
/// distinct de « fenêtre disparue » (`nil`).
final class FailingFrameSource: FrameSource, @unchecked Sendable {
    enum Outcome { case frame(CGImage?), failure }
    private var outcomes: [Outcome]
    private var index = 0
    private let lock = NSLock()

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func captureFrame() async throws -> CGImage? {
        let outcome: Outcome? = lock.withLock {
            guard index < outcomes.count else { return nil }
            defer { index += 1 }
            return outcomes[index]
        }
        switch outcome {
        case .frame(let image): return image
        case .failure: throw SimulatedCaptureError()
        case nil: return nil
        }
    }
}

struct SimulatedCaptureError: Error, LocalizedError {
    var errorDescription: String? { "panne simulée" }
}

/// Source dont la capture se suspend sous le contrôle du test : rend d'abord
/// `immediateFrames`, puis se suspend sur `captureFrame()` jusqu'à `resume(with:)`.
/// Permet de mettre un tick « en vol » pendant que `finish()` s'exécute, sans dépendre
/// du minutage de l'ordonnanceur.
final class SuspendingFrameSource: FrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var immediateFrames: [CGImage?]
    private var index = 0
    private var continuation: CheckedContinuation<CGImage?, Error>?
    private var suspendedContinuation: CheckedContinuation<Void, Never>?

    init(immediateFrames: [CGImage?]) { self.immediateFrames = immediateFrames }

    func captureFrame() async throws -> CGImage? {
        var immediate: CGImage?
        var hasImmediate = false
        lock.withLock {
            if index < immediateFrames.count {
                immediate = immediateFrames[index]
                hasImmediate = true
                index += 1
            }
        }
        if hasImmediate { return immediate }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
                if let suspendedContinuation {
                    self.suspendedContinuation = nil
                    suspendedContinuation.resume()
                }
            }
        }
    }

    /// Ne rend la main qu'une fois un appel à `captureFrame()` effectivement suspendu.
    func waitUntilSuspended() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if self.continuation != nil { continuation.resume() }
                else { self.suspendedContinuation = continuation }
            }
        }
    }

    func resume(with image: CGImage?) {
        let continuation: CheckedContinuation<CGImage?, Error>? = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: image)
    }
}
```

- [ ] **Step 2 : Tests du service (échec attendu)**

`Tests/ScreenCaptureServiceTests.swift` :

```swift
import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import OneToOne

@Suite("ScreenCaptureService")
@MainActor
struct ScreenCaptureServiceTests {

    private let container: ModelContainer
    private let root: URL
    private let meeting: Meeting

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        meeting = Meeting(title: "Réunion", date: Date())
        container.mainContext.insert(meeting)
        try container.mainContext.save()
    }

    private var context: ModelContext { container.mainContext }

    private func banded(_ f: Double) -> CGImage { SlideImageFixtures.banded(fraction: f) }

    private func config(crop: NormalizedRect = .full) -> ScreenCaptureService.SessionConfiguration {
        .init(windowID: 42, windowTitle: "Teams", crop: crop, sensitivity: .normal)
    }

    /// Service branché sur une source de test ; OCR et réindexation neutralisés.
    private func makeService(source: any FrameSource) -> ScreenCaptureService {
        ScreenCaptureService(
            recordingsRoot: root,
            frameSourceFactory: { _ in source },
            ocr: { _ in "" },
            reindex: { _, _ in }
        )
    }

    private func pngNames(_ service: ScreenCaptureService) throws -> [String] {
        let dir = root.appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.sorted()
    }

    @Test("un tick avant beginSession est inerte")
    func tickBeforeSessionIsInert() async throws {
        let service = makeService(source: ScriptedFrameSource(frames: [banded(0.3)]))
        await service.tick()
        #expect(service.state == .idle)
        #expect(service.currentAttachment == nil)
        #expect(try pngNames(service).isEmpty)
    }

    @Test("beginSession crée l'attachment et le dossier tout de suite, sans capturer")
    func beginSessionCreatesAttachmentAndDirectory() async throws {
        let service = makeService(source: ScriptedFrameSource(frames: []))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        #expect(service.state == .running)
        let attachment = try #require(service.currentAttachment)
        #expect(attachment.kind == "slides")
        #expect(attachment.meeting === meeting)
        let dir = root.appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        #expect(FileManager.default.fileExists(atPath: dir.path))
        #expect(service.capturedSlidesCount == 0)
    }

    @Test("deux slides distincts donnent deux SlideCapture et deux PNG numérotés sur quatre chiffres")
    func writesOneSlidePerStableChange() async throws {
        let first = banded(0.2), second = banded(0.8)
        let service = makeService(source: ScriptedFrameSource(frames: [first, first, first, first, second, second, second, second]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<8 { await service.tick() }

        #expect(service.capturedSlidesCount == 2)
        let slides = try #require(service.currentAttachment).slides.sorted { $0.index < $1.index }
        #expect(slides.map(\.index) == [1, 2])
        let names = try pngNames(service)
        #expect(names.count == 2)
        #expect(names[0].hasPrefix("slide-0001-"))
        #expect(names[1].hasPrefix("slide-0002-"))
        #expect(slides.allSatisfy { FileManager.default.fileExists(atPath: $0.imagePath) })
    }

    @Test("le crop est appliqué à l'image écrite")
    func appliesCrop() async throws {
        let frame = SlideImageFixtures.solid(gray: 0.4, width: 800, height: 600)
        let service = makeService(source: ScriptedFrameSource(frames: [frame, frame, frame, frame]))
        try service.beginSession(configuration: config(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        let slide = try #require(service.currentAttachment?.slides.first)
        let fp = try #require(SlideFingerprint(contentsOf: URL(fileURLWithPath: slide.imagePath)))
        #expect(fp.samples.count == 1024)
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: slide.imagePath) as CFURL, nil)!
        let written = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(written.width == 400)
        #expect(written.height == 300)
    }

    @Test("la disparition de la fenêtre met en pause, sa réapparition remet en cours et efface l'erreur")
    func pausesAndResumesOnSourcePresence() async throws {
        let image = banded(0.3)
        let source = FailingFrameSource(outcomes: [.frame(image), .frame(nil), .failure, .frame(image)])
        let service = makeService(source: source)
        try service.beginSession(configuration: config(), meeting: meeting, context: context)

        await service.tick()
        #expect(service.state == .running)
        await service.tick() // nil
        guard case .paused(let reason) = service.state else { Issue.record("attendu paused, obtenu \(service.state)"); return }
        #expect(reason.contains("introuvable"))
        await service.tick() // échec d'API
        guard case .paused(let reason2) = service.state else { Issue.record("attendu paused, obtenu \(service.state)"); return }
        #expect(reason2.contains("panne simulée"))
        #expect(service.lastError != nil)
        await service.tick() // retour
        #expect(service.state == .running)
        #expect(service.lastError == nil)
    }

    @Test("stop publie stopped et garde la session ; resume reprend sur le même attachment")
    func stopThenResumeKeepsAttachment() async throws {
        let image = banded(0.3)
        let service = makeService(source: ScriptedFrameSource(frames: Array(repeating: image, count: 8)))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        let attachment = try #require(service.currentAttachment)
        #expect(attachment.slides.count == 1)

        service.stop()
        #expect(service.state == .stopped)
        #expect(service.currentAttachment === attachment)
        #expect(service.hasOpenSession)
        await service.tick() // inerte en stopped
        #expect(service.capturedSlidesCount == 1)

        service.resume()
        // Aucun await depuis resume() : la boucle relancée n'a pas encore tické. On l'annule
        // pour continuer à piloter les ticks à la main ; l'état running vient de resume().
        service.cancelLoopForTesting()
        #expect(service.state == .running)
        #expect(service.currentAttachment === attachment)
        #expect(throws: ScreenCaptureService.SessionError.sessionAlreadyOpen) {
            try service.beginSession(configuration: config(), meeting: meeting, context: context)
        }
    }

    @Test("beginSession refuse d'ouvrir une seconde session")
    func beginSessionTwiceThrows() throws {
        let service = makeService(source: ScriptedFrameSource(frames: []))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        #expect(throws: ScreenCaptureService.SessionError.sessionAlreadyOpen) {
            try service.beginSession(configuration: config(), meeting: meeting, context: context)
        }
    }

    @Test("après resume, les ticks continuent la numérotation et un retour arrière est un doublon")
    func ticksAfterResumeContinueNumbering() async throws {
        let first = banded(0.2), second = banded(0.8)
        let service = makeService(source: ScriptedFrameSource(frames: [first, first, first, first, second, second, second, second, first, first, first, first]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        service.stop()
        service.resume()
        service.cancelLoopForTesting() // aucun await depuis resume() : la boucle n'a pas tické
        #expect(service.state == .running)
        for _ in 0..<8 { await service.tick() } // second → slide 2 ; retour sur first → doublon
        let slides = try #require(service.currentAttachment).slides.sorted { $0.index < $1.index }
        #expect(slides.map(\.index) == [1, 2])
        #expect(try pngNames(service).count == 2)
    }

    @Test("finish clôt la session : idle, attachment relâché, un start suivant ouvre un nouvel attachment")
    func finishClosesSessionAndNextStartOpensNewAttachment() async throws {
        let image = banded(0.3)
        let service = makeService(source: ScriptedFrameSource(frames: Array(repeating: image, count: 8)))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        let firstAttachment = try #require(service.currentAttachment)
        #expect(firstAttachment.slides.count == 1)

        await service.finish()
        #expect(service.state == .idle)
        #expect(service.currentAttachment == nil)
        #expect(service.configuration == nil)
        await service.tick() // inerte
        #expect(firstAttachment.slides.count == 1)

        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        let secondAttachment = try #require(service.currentAttachment)
        #expect(secondAttachment !== firstAttachment)
        #expect(meeting.attachments.filter { $0.kind == "slides" }.count == 2)
    }

    @Test("un tick en vol pendant finish n'écrit ni PNG ni SlideCapture après la clôture")
    func inFlightTickCannotWriteAfterFinish() async throws {
        let first = banded(0.2), second = banded(0.8)
        // 4 ticks stables sur first → slide 1. 2 ticks sur second → armé, un tick stable :
        // le septième tick (en vol) est celui qui confirmerait le second slide.
        let source = SuspendingFrameSource(immediateFrames: [first, first, first, first, second, second])
        let service = makeService(source: source)
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<6 { await service.tick() }
        let attachment = try #require(service.currentAttachment)
        #expect(attachment.slides.count == 1)

        let inFlight = Task { @MainActor in await service.tick() }
        await source.waitUntilSuspended()

        await service.finish()
        let namesAtFinish = try pngNames(service)
        #expect(namesAtFinish.count == 1)

        source.resume(with: second)
        await inFlight.value

        #expect(try pngNames(service) == namesAtFinish, "PNG apparus APRÈS la clôture")
        #expect(attachment.slides.count == 1)
        #expect(service.state == .idle)
    }

    @Test("snapshot écrit l'image courante sans attendre la stabilisation, et le détecteur la connaît ensuite")
    func snapshotWritesImmediately() async throws {
        let image = banded(0.3)
        let service = makeService(source: ScriptedFrameSource(frames: [image, image, image, image, image]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        await service.tick() // une seule référence, rien d'écrit
        #expect(service.capturedSlidesCount == 0)
        await service.snapshotForTesting()
        #expect(service.capturedSlidesCount == 1)
        for _ in 0..<3 { await service.tick() } // stabilisation : doublon, pas de second fichier
        #expect(service.capturedSlidesCount == 1)
    }

    @Test("appendTo reprend un lot existant : numérotation après le dernier index, PNG existants connus du détecteur")
    func appendToExistingAttachmentSeedsDetector() async throws {
        // Lot préexistant : un attachment avec un PNG déjà sur disque.
        let dir = root.appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existingURL = dir.appendingPathComponent("slide-0001-090000.png")
        try SlideImageFixtures.writePNG(banded(0.2), to: existingURL)
        let previous = MeetingAttachment(url: URL(fileURLWithPath: "slides-old.slides"), kind: "slides")
        previous.meeting = meeting
        context.insert(previous)
        let existing = SlideCapture(index: 1, capturedAt: Date(), imagePath: existingURL.path)
        existing.attachment = previous
        context.insert(existing)
        try context.save()

        let known = banded(0.2), fresh = banded(0.8)
        let service = makeService(source: ScriptedFrameSource(frames: [known, known, known, known, fresh, fresh, fresh, fresh]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context, appendTo: previous)
        #expect(service.currentAttachment === previous)
        for _ in 0..<8 { await service.tick() }

        let slides = previous.slides.sorted { $0.index < $1.index }
        #expect(slides.map(\.index) == [1, 2]) // le slide connu n'est pas réécrit
        #expect(try pngNames(service).count == 2)
        #expect(try pngNames(service)[1].hasPrefix("slide-0002-"))
    }

    @Test("une racine non inscriptible fait échouer beginSession avant toute capture")
    func unwritableRootFailsEarly() throws {
        let service = ScreenCaptureService(
            recordingsRoot: URL(fileURLWithPath: "/dev/null/impossible"),
            frameSourceFactory: { _ in ScriptedFrameSource(frames: []) },
            ocr: { _ in "" },
            reindex: { _, _ in }
        )
        #expect(throws: (any Error).self) {
            try service.beginSession(configuration: config(), meeting: meeting, context: context)
        }
        #expect(service.state == .idle)
        #expect(service.currentAttachment == nil)
        #expect(meeting.attachments.isEmpty)
    }

    @Test("updateSource n'agit qu'en stopped et conserve la zone")
    func updateSourceOnlyWhenStopped() throws {
        let service = makeService(source: ScriptedFrameSource(frames: []))
        let crop = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        try service.beginSession(configuration: config(crop: crop), meeting: meeting, context: context)
        service.updateSource(windowID: 7, title: "Zoom")
        #expect(service.configuration?.windowID == 42) // ignoré en running
        service.stop()
        service.updateSource(windowID: 7, title: "Zoom")
        #expect(service.configuration?.windowID == 7)
        #expect(service.configuration?.windowTitle == "Zoom")
        #expect(service.configuration?.crop == crop)
    }
}
```

> Note : `cancelLoopForTesting()` et `snapshotForTesting()` sont deux points d'entrée
> internes (`internal`, visibles via `@testable`) : le premier annule la boucle sans changer
> l'état, le second exécute la capture forcée de `snapshot()` de façon **attendable**.
> `snapshot()` public reste une fonction synchrone qui lance une `Task`.

- [ ] **Step 3 : Vérifier l'échec**

Run : `swift build --build-tests 2>&1 | grep -E "error:" | head -5`
Expected : erreurs sur `recordingsRoot`, `SessionConfiguration`, `beginSession` inexistants.

- [ ] **Step 4 : Supprimer `PerceptualHasher` et réécrire le service**

```bash
git rm -q OneToOne/Services/PerceptualHasher.swift
```

`OneToOne/Services/ScreenCaptureService.swift` (remplacement intégral) :

```swift
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import os

private let captureLog = Logger(subsystem: "com.onetoone.app", category: "capture")

/// Coordinateur de la capture automatique de slides : relie la source d'images
/// (`FrameSource`), la zone (`NormalizedRect`), le détecteur (`SlideDetector`) et la
/// persistance (`SlideCapture` + OCR), et publie l'état de la session à l'interface.
///
/// **Invariant** : une session est ouverte (`currentAttachment != nil`) si et seulement
/// si l'état est `running`, `paused` ou `stopped`.
///
/// - `stop()` annule la boucle et publie `stopped` **sans** clore la session : `resume()`
///   reprend le même attachment, le même détecteur, la même numérotation.
/// - `finish()` clôt : attente OCR, sauvegarde, réindexation, puis `idle`.
/// - `tick()` est la plus petite unité de travail et est appelable directement : les tests
///   pilotent la capture sans horloge. Après chaque `await`, il revérifie le **jeton de
///   session** : un tick suspendu pendant `finish()` ne doit ni écrire ni publier.
@MainActor
final class ScreenCaptureService: ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case paused(String)
        case stopped

        var isPaused: Bool {
            if case .paused = self { return true }
            return false
        }
    }

    /// Ce qui définit une session : figé pendant la boucle, modifiable en `stopped`
    /// (fenêtre seulement, via `updateSource`).
    struct SessionConfiguration: Equatable {
        var windowID: CGWindowID
        var windowTitle: String
        var crop: NormalizedRect
        var sensitivity: SlideCaptureSettings.Sensitivity
    }

    enum SessionError: Error, Equatable, LocalizedError {
        case sessionAlreadyOpen
        case noOpenSession

        var errorDescription: String? {
            switch self {
            case .sessionAlreadyOpen: return "Une session de capture est déjà ouverte."
            case .noOpenSession: return "Aucune session de capture n'est ouverte."
            }
        }
    }

    typealias FrameSourceFactory = @Sendable (CGWindowID) -> any FrameSource
    typealias OCRFunction = @Sendable (CGImage) async throws -> String
    typealias ReindexFunction = @MainActor (MeetingAttachment, ModelContext) async -> Void

    // MARK: - État publié

    @Published private(set) var state: State = .idle
    /// Attachment `kind: "slides"` de la session ouverte. `nil` hors session.
    @Published private(set) var currentAttachment: MeetingAttachment?
    @Published private(set) var configuration: SessionConfiguration?
    @Published var lastError: String?
    @Published private(set) var ocrProgress: (current: Int, total: Int)?

    /// Compatibilité avec les barres : capture « active » = en cours ou en pause.
    var isCapturing: Bool { state == .running || state.isPaused }
    var hasOpenSession: Bool { currentAttachment != nil }
    /// Source de vérité : le nombre d'éléments dans `currentAttachment.slides`.
    var capturedSlidesCount: Int { currentAttachment?.slides.count ?? 0 }

    // MARK: - Dépendances injectables

    private let recordingsRoot: URL
    private let frameSourceFactory: FrameSourceFactory
    private let ocr: OCRFunction
    private let reindex: ReindexFunction

    // MARK: - État interne de session

    /// Régénéré à chaque `beginSession`, remis à `nil` par `finish()` **avant** la
    /// première attente. Toute étape après un `await` compare son jeton local à celui-ci.
    private var sessionToken: UUID?
    private var source: (any FrameSource)?
    private var detector = SlideDetector(settings: SlideCaptureSettings())
    private var settings = SlideCaptureSettings()
    private var slidesDirectory: URL?
    private var modelContext: ModelContext?
    /// Prochain index de slide, réservé **avant** tout `await` d'écriture : deux écritures
    /// en vol (tick + snapshot) ne peuvent pas se partager un numéro.
    private var nextIndex = 1
    private var loop: Task<Void, Never>?
    private var ocrTasks: [Task<Void, Never>] = []

    init(
        recordingsRoot: URL? = nil,
        frameSourceFactory: @escaping FrameSourceFactory = { WindowFrameSource(windowID: $0) },
        ocr: @escaping OCRFunction = { try await OCRService.recognize(cgImage: $0) },
        reindex: @escaping ReindexFunction = { attachment, context in
            try? await MeetingAttachmentService.reindexAttachment(attachment, context: context)
        }
    ) {
        self.recordingsRoot = recordingsRoot ?? ScreenCaptureService.defaultRecordingsRoot()
        self.frameSourceFactory = frameSourceFactory
        self.ocr = ocr
        self.reindex = reindex
    }

    // MARK: - Cycle de vie de la session

    /// Ouvre la session : attachment (nouveau ou `appendTo`), dossier créé **tout de
    /// suite** (une racine non inscriptible échoue avant toute capture), détecteur neuf
    /// (réamorcé depuis les PNG du lot repris), état `running`. Ne lance pas la boucle.
    func beginSession(
        configuration: SessionConfiguration,
        meeting: Meeting,
        context: ModelContext,
        appendTo existing: MeetingAttachment? = nil
    ) throws {
        guard state == .idle, currentAttachment == nil else { throw SessionError.sessionAlreadyOpen }

        let directory = recordingsRoot
            .appendingPathComponent(meeting.ensuredStableID.uuidString, isDirectory: true)
            .appendingPathComponent("slides", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attachment: MeetingAttachment
        if let existing {
            attachment = existing
        } else {
            attachment = MeetingAttachment(
                url: URL(fileURLWithPath: "slides-\(Date().timeIntervalSince1970).slides"),
                kind: "slides"
            )
            attachment.fileName = "Slides capture - \(Date().formatted(date: .abbreviated, time: .shortened))"
            attachment.meeting = meeting
            context.insert(attachment)
        }

        let settings = SlideCaptureSettings(sensitivity: configuration.sensitivity)
        self.settings = settings
        var detector = SlideDetector(settings: settings)
        if let existing {
            let known = existing.slides.compactMap { SlideFingerprint(contentsOf: URL(fileURLWithPath: $0.imagePath)) }
            detector.seed(known)
        }
        self.detector = detector

        self.configuration = configuration
        self.source = frameSourceFactory(configuration.windowID)
        self.slidesDirectory = directory
        self.modelContext = context
        self.nextIndex = attachment.slides.count + 1
        self.currentAttachment = attachment
        self.sessionToken = UUID()
        clearError()
        self.state = .running
        captureLog.info("Session de capture ouverte (append=\(existing != nil)) fenêtre=\(configuration.windowID)")
    }

    /// Ouvre la session et lance la boucle périodique.
    func start(
        configuration: SessionConfiguration,
        meeting: Meeting,
        context: ModelContext,
        appendTo existing: MeetingAttachment? = nil
    ) throws {
        try beginSession(configuration: configuration, meeting: meeting, context: context, appendTo: existing)
        launchLoop()
    }

    /// Reprend une session arrêtée : même attachment, même détecteur, même numérotation.
    func resume() {
        guard state == .stopped, currentAttachment != nil else { return }
        clearError()
        state = .running
        launchLoop()
        captureLog.info("Capture reprise")
    }

    /// Arrête la boucle. La session reste ouverte, les slides restent visibles.
    func stop() {
        loop?.cancel()
        loop = nil
        switch state {
        case .running, .paused:
            state = .stopped
            captureLog.info("Capture arrêtée (session conservée)")
        case .idle, .stopped:
            break
        }
    }

    /// Clôt la session : le jeton est invalidé **avant** la première attente, si bien
    /// qu'un tick en vol ne peut plus rien écrire ni publier. Attend les OCR, sauvegarde,
    /// réindexe, puis repasse `idle`.
    func finish() async {
        stop()
        guard let attachment = currentAttachment, let context = modelContext else { return }
        sessionToken = nil
        source = nil

        let tasks = ocrTasks
        ocrTasks = []
        if !tasks.isEmpty {
            ocrProgress = (0, tasks.count)
            for (index, task) in tasks.enumerated() {
                await task.value
                ocrProgress = (index + 1, tasks.count)
            }
        }
        ocrProgress = nil

        try? context.save()
        currentAttachment = nil
        configuration = nil
        slidesDirectory = nil
        state = .idle
        clearError()
        captureLog.info("Session de capture terminée : \(attachment.slides.count) slides")
        await reindex(attachment, context)
    }

    /// Change de fenêtre source sans toucher à la zone. Autorisé en `stopped` seulement.
    func updateSource(windowID: CGWindowID, title: String) {
        guard state == .stopped, var configuration else { return }
        configuration.windowID = windowID
        configuration.windowTitle = title
        self.configuration = configuration
        source = frameSourceFactory(windowID)
    }

    // MARK: - Capture

    /// Un cycle : capture, crop, empreinte, décision, écriture éventuelle.
    func tick() async {
        guard let token = sessionToken, let source, isCapturing else { return }

        let frame: CGImage?
        do {
            frame = try await source.captureFrame()
        } catch {
            guard sessionToken == token else { return }
            lastError = error.localizedDescription
            state = .paused("Capture impossible : \(error.localizedDescription)")
            return
        }

        guard sessionToken == token else { return }

        guard let frame else {
            state = .paused("Fenêtre source introuvable. La capture reprendra si elle réapparaît.")
            return
        }

        if state.isPaused {
            state = .running
            clearError()
        }

        guard let crop = configuration?.crop,
              let cropped = crop.apply(to: frame),
              let fingerprint = SlideFingerprint(image: cropped) else {
            lastError = "La zone de capture est vide ou invalide."
            return
        }

        guard detector.consume(fingerprint) == .newSlide else { return }
        await writeSlide(cropped, token: token)
    }

    /// Force l'écriture de l'image courante, sans attendre la stabilisation.
    func snapshot() {
        Task { await snapshotForTesting() }
    }

    /// Corps attendable de `snapshot()` (visible des tests).
    func snapshotForTesting() async {
        guard state == .running, let token = sessionToken, let source, let crop = configuration?.crop else { return }
        guard let frame = try? await source.captureFrame(), sessionToken == token,
              let cropped = crop.apply(to: frame) else { return }
        if let fingerprint = SlideFingerprint(image: cropped) {
            detector.seed([fingerprint])
        }
        await writeSlide(cropped, token: token)
    }

    /// Annule la boucle sans changer l'état (tests : piloter les ticks à la main).
    func cancelLoopForTesting() {
        loop?.cancel()
        loop = nil
    }

    func deleteSlide(_ slide: SlideCapture) {
        guard let context = modelContext ?? slide.modelContext else { return }
        let path = slide.imagePath
        context.delete(slide)
        try? FileManager.default.removeItem(atPath: path)
        rebuildAttachmentText()
        objectWillChange.send()
        try? context.save()
    }

    // MARK: - Boucle

    private func launchLoop() {
        guard loop == nil else { return }
        let interval = settings.tickInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // Le propriétaire a disparu : sortir, pas de tâche fantôme.
                guard let self else { break }
                await self.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: - Écriture

    private func writeSlide(_ image: CGImage, token: UUID) async {
        guard sessionToken == token,
              let attachment = currentAttachment,
              let context = modelContext,
              let directory = slidesDirectory else { return }

        let index = nextIndex
        nextIndex += 1
        let date = Date()
        let fileURL = directory.appendingPathComponent(ScreenCaptureService.fileName(index: index, date: date))

        do {
            try await ScreenCaptureService.encodePNG(image, to: fileURL)
        } catch {
            guard sessionToken == token else { return }
            lastError = "Écriture du slide \(index) impossible : \(error.localizedDescription)"
            return
        }

        guard sessionToken == token else {
            // La session a été close pendant l'encodage : ce slide ne lui appartient plus.
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let slide = SlideCapture(index: index, capturedAt: date, imagePath: fileURL.path)
        slide.attachment = attachment
        context.insert(slide)
        // La vue observe `capturedSlidesCount`, calculé depuis `attachment.slides`.
        objectWillChange.send()
        captureLog.info("Slide \(index) écrit")

        let ocr = self.ocr
        let task = Task { [weak self] in
            do {
                let text = try await ocr(image)
                await MainActor.run {
                    slide.ocrText = text
                    self?.rebuildAttachmentText()
                }
            } catch {
                captureLog.error("OCR du slide \(index) échoué : \(error.localizedDescription)")
            }
        }
        ocrTasks.append(task)
    }

    private func rebuildAttachmentText() {
        guard let attachment = currentAttachment else { return }
        let slides = attachment.slides.sorted(by: { $0.index < $1.index })
        var fullText = ""
        for slide in slides {
            let timestamp = slide.capturedAt.formatted(date: .omitted, time: .standard)
            fullText += "--- Slide \(slide.index) [\(timestamp)] ---\n"
            fullText += slide.ocrText + "\n\n"
        }
        attachment.extractedText = fullText
    }

    /// Seul endroit qui remet le message de panne à zéro : appelé sur **tous** les
    /// chemins de succès (ouverture, reprise, tick réussi après pause, clôture).
    private func clearError() {
        lastError = nil
    }

    // MARK: - Helpers statiques

    static func fileName(index: Int, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HHmmss"
        return "slide-\(String(format: "%04d", index))-\(formatter.string(from: date)).png"
    }

    /// Encodage PNG hors thread principal : quelques dizaines de millisecondes.
    nonisolated static func encodePNG(_ image: CGImage, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { throw SlideCaptureError.captureFailed("destination PNG non créable") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw SlideCaptureError.captureFailed("encodage PNG échoué")
            }
        }.value
    }

    private static func defaultRecordingsRoot() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0]
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }
}
```

> Compilation : les vues (`MeetingView`, barres, `ScreenCaptureConfigView`) référencent
> encore `service.start(mode:…)`, `selectedSource`, `CaptureMode`. Pour que la cible
> compile **dans cette tâche**, remplacer temporairement dans
> `OneToOne/Views/ScreenCaptureConfigView.swift` le corps de `startCapture()` par un
> `// TODO Task 6` vide et supprimer ses références à `service.selectedSource` /
> `ScreenCaptureService.CaptureMode` (remplacer l'état `mode` par une constante locale).
> Dans `MeetingView.swift` ligne 257, `onStopCapture: { Task { await captureService.stop() } }`
> devient `onStopCapture: { captureService.stop() }`. La Task 6 réécrit ce fichier
> intégralement ; ce stub ne vit que le temps de cette tâche.

- [ ] **Step 5 : Vérifier le vert**

Run : `swift build 2>&1 | grep -E "error:" ; swift test --filter ScreenCaptureServiceTests 2>&1 | tail -20`
Expected : build sans erreur, 14 tests passed.

- [ ] **Step 6 : Preuve par mutation, tick en vol**

Dans `tick()`, supprimer temporairement la ligne `guard sessionToken == token else { return }` qui suit le `do/catch` de `captureFrame()`. Run : `swift test --filter ScreenCaptureServiceTests 2>&1 | grep -E "inFlightTick|failed"`. Expected : `inFlightTickCannotWriteAfterFinish` **échoue** (message « PNG apparus APRÈS la clôture » ou `attachment.slides.count == 1` faux). Rétablir, relancer, vert.

- [ ] **Step 7 : Commit**

```bash
git add -A OneToOne/Services/ScreenCaptureService.swift OneToOne/Services/PerceptualHasher.swift OneToOne/Views/ScreenCaptureConfigView.swift OneToOne/Views/MeetingView.swift Tests/ScreenCaptureServiceTestDoubles.swift Tests/ScreenCaptureServiceTests.swift
git commit -m "feat(capture): ScreenCaptureService reecrit, sessions arret/reprise/terminer, jeton revérifie apres chaque await"
```

---

### Task 5 : Vue de tracé et lien vers les Réglages

**Files:**
- Create: `OneToOne/Views/CropSelectionView.swift`
- Create: `OneToOne/Services/SlideCapture/ScreenRecordingSettingsLink.swift`
- Test: `Tests/ScreenRecordingSettingsLinkTests.swift`

**Interfaces:**
- Consumes: `NormalizedRect` (Task 1).
- Produces: `struct CropSelectionView: View` — `init(image: CGImage, rect: Binding<NormalizedRect>, isLocked: Bool = false)`.
- Produces: `enum ScreenRecordingSettingsLink` — `static let candidateURLs: [URL]`, `static let manualPath: String`, `@MainActor static func open(using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool`.

- [ ] **Step 1 : Test du lien Réglages (échec attendu)**

`Tests/ScreenRecordingSettingsLinkTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("ScreenRecordingSettingsLink")
@MainActor
struct ScreenRecordingSettingsLinkTests {

    @Test("le panneau moderne est essayé d'abord, l'URL historique en repli")
    func candidateOrder() {
        let urls = ScreenRecordingSettingsLink.candidateURLs.map(\.absoluteString)
        #expect(urls == [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ])
    }

    @Test("open s'arrête à la première URL acceptée")
    func stopsAtFirstSuccess() {
        var tried: [String] = []
        let ok = ScreenRecordingSettingsLink.open { url in
            tried.append(url.absoluteString)
            return true
        }
        #expect(ok)
        #expect(tried.count == 1)
    }

    @Test("open essaie le repli puis rend false si tout échoue")
    func fallsBackThenFails() {
        var tried: [String] = []
        let ok = ScreenRecordingSettingsLink.open { url in
            tried.append(url.absoluteString)
            return false
        }
        #expect(!ok)
        #expect(tried.count == 2)
        #expect(ScreenRecordingSettingsLink.manualPath.contains("Enregistrement de l'écran"))
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

Run : `swift build --build-tests 2>&1 | grep -E "error:" | head -2`
Expected : `cannot find 'ScreenRecordingSettingsLink' in scope`.

- [ ] **Step 3 : Implémenter `ScreenRecordingSettingsLink`**

```swift
import AppKit
import Foundation

/// Ouvre la section « Enregistrement de l'écran » des Réglages Système.
///
/// Sur macOS 13+, l'ancien identifiant `com.apple.preference.security` ouvre les Réglages
/// sans forcément naviguer jusqu'à la bonne section ; l'extension moderne
/// `com.apple.settings.PrivacySecurity.extension` porte l'ancre `Privacy_ScreenCapture`.
/// On essaie donc le moderne, puis l'historique, et en dernier recours l'interface
/// affiche `manualPath`. C'est souvent l'unique bouton du seul écran bloquant : il ne
/// doit pas pouvoir être sans effet.
enum ScreenRecordingSettingsLink {

    static let candidateURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!,
    ]

    static let manualPath = "Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran"

    /// Essaie chaque URL dans l'ordre ; `true` dès qu'une ouverture est acceptée.
    @MainActor
    static func open(using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        for url in candidateURLs where opener(url) {
            return true
        }
        return false
    }
}
```

- [ ] **Step 4 : Implémenter `CropSelectionView`**

`OneToOne/Views/CropSelectionView.swift` :

```swift
import CoreGraphics
import SwiftUI

/// Aperçu de la fenêtre source sur lequel l'utilisateur trace la zone du slide.
///
/// Astuce de coordonnées : le `GeometryReader` porte lui-même le ratio de l'image, donc
/// `geometry.size` **est** la taille d'affichage de l'image. Aucun décalage aspect-fit à
/// calculer ; les coordonnées du glissement se convertissent directement en fractions.
/// Si ce modificateur était mal placé, tous les tracés seraient décalés du même offset,
/// erreur invisible au centre de l'image.
struct CropSelectionView: View {
    let image: CGImage
    @Binding var rect: NormalizedRect
    /// Vrai pendant une session : le geste reste reconnu mais ne modifie plus `rect`.
    var isLocked: Bool = false

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private var aspectRatio: CGFloat {
        guard image.height > 0 else { return 16 / 9 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    var body: some View {
        GeometryReader { geometry in
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay { selectionOverlay(in: geometry.size) }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(isLocked ? 0.85 : 1)
    }

    /// La zone retenue reste nette, tout ce qui l'entoure est assombri.
    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        let displayed = displayedRect(in: size)
        ZStack {
            Color.black.opacity(0.45)
                .reverseMask { Rectangle().path(in: displayed).fill(style: FillStyle()) }
            Rectangle()
                .path(in: displayed)
                .stroke(isLocked ? Color.secondary : Color.accentColor, lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    /// Le glissement en cours s'il y en a un, sinon la zone retenue.
    private func displayedRect(in size: CGSize) -> CGRect {
        if let start = dragStart, let current = dragCurrent {
            return CGRect(
                x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y)
            )
        }
        return rect.displayRect(in: size)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !isLocked else { return }
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil }
                guard !isLocked else { return }
                rect = NormalizedRect.fromDrag(from: value.startLocation, to: value.location, in: size, current: rect)
            }
    }
}

private extension View {
    /// Découpe un trou dans la vue à l'endroit du masque.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
```

- [ ] **Step 5 : Vérifier**

Run : `swift build 2>&1 | grep -E "error:" ; swift test --filter ScreenRecordingSettingsLinkTests 2>&1 | tail -6`
Expected : build sans erreur, 3 tests passed.

- [ ] **Step 6 : Commit**

```bash
git add OneToOne/Views/CropSelectionView.swift OneToOne/Services/SlideCapture/ScreenRecordingSettingsLink.swift Tests/ScreenRecordingSettingsLinkTests.swift
git commit -m "feat(capture): vue de trace de la zone sur apercu, lien vers les Reglages avec repli"
```

---

### Task 6 : Popover de configuration réécrit

**Files:**
- Rewrite: `OneToOne/Views/ScreenCaptureConfigView.swift`
- Delete: `OneToOne/Views/RectSelectorOverlay.swift`

**Interfaces:**
- Consumes: `ScreenCaptureService` (Task 4), `WindowCatalog`, `ShareableWindow`, `SlideCaptureError`, `WindowFrameSource` (Task 3), `CropSelectionView`, `ScreenRecordingSettingsLink` (Task 5), `AppSettings.slideCaptureSensitivity`, `settingsList.canonicalSettings`.
- Produces: `struct ScreenCaptureConfigView: View` — `init(service: ScreenCaptureService, meeting: Meeting)` (signature inchangée pour `MeetingView`).

- [ ] **Step 1 : Supprimer l'overlay plein écran**

```bash
git rm -q OneToOne/Views/RectSelectorOverlay.swift
```

- [ ] **Step 2 : Réécrire la vue**

`OneToOne/Views/ScreenCaptureConfigView.swift` (remplacement intégral) :

```swift
import CoreGraphics
import SwiftData
import SwiftUI

/// Popover de la capture automatique de slides. Trois faces selon l'état du service :
/// configurer (`idle`), suivre (`running` / `paused`), reprendre ou terminer (`stopped`),
/// plus un écran de refus d'autorisation qui remplace tout.
///
/// Règle : tout contrôle dont l'action n'aurait aucun effet est **désactivé**, l'état réel
/// est affiché, et une instruction désigne une action présente au même endroit.
struct ScreenCaptureConfigView: View {
    @ObservedObject var service: ScreenCaptureService
    var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var windows: [ShareableWindow] = []
    @State private var selectedWindowID: CGWindowID?
    @State private var preview: CGImage?
    @State private var previewError: String?
    @State private var crop: NormalizedRect = .full
    @State private var sensitivity: SlideCaptureSettings.Sensitivity = .normal
    @State private var appendToPrevious = false
    @State private var permissionDenied = false
    @State private var catalogError: String?
    @State private var startError: String?
    @State private var settingsOpenFailed = false

    private var settings: AppSettings? { settingsList.canonicalSettings }

    /// Dernier lot de slides de la réunion, s'il existe (pour « Ajouter au lot précédent »).
    private var previousAttachment: MeetingAttachment? {
        meeting.attachments.filter { $0.kind == "slides" }.sorted { $0.importedAt > $1.importedAt }.first
    }

    private var selectedWindow: ShareableWindow? {
        windows.first { $0.id == selectedWindowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if permissionDenied {
                permissionFace
            } else {
                switch service.state {
                case .idle: configureFace
                case .running, .paused: followFace
                case .stopped: stoppedFace
                }
            }
        }
        .padding()
        .frame(width: 420)
        .task { await refreshWindows() }
        .onAppear {
            sensitivity = settings?.slideCaptureSensitivity ?? .normal
            if let previous = previousAttachment {
                // Ajouter par défaut si le lot date de moins de quatre heures.
                appendToPrevious = Date().timeIntervalSince(previous.importedAt) < 4 * 3600
            }
        }
    }

    // MARK: - Face « configurer » (idle)

    private var configureFace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capturer les slides depuis…").font(.headline)

            windowPicker(onChange: { window in
                crop = .full
                Task { await loadPreview(of: window) }
            })

            if let preview {
                VStack(alignment: .leading, spacing: 6) {
                    CropSelectionView(image: preview, rect: $crop)
                        .frame(maxHeight: 220)
                    HStack {
                        Text("Tracez la zone du slide sur l'aperçu.")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("Toute la fenêtre") { crop = .full }
                            .buttonStyle(.link).font(.caption)
                            .disabled(crop == .full)
                    }
                }
            } else if let previewError {
                Text("Aperçu indisponible : \(previewError). La fenêtre entière sera capturée.")
                    .font(.caption).foregroundColor(.orange)
            } else if selectedWindowID != nil {
                ProgressView("Aperçu en cours…").controlSize(.small)
            }

            Divider()

            Picker("Sensibilité", selection: $sensitivity) {
                ForEach(SlideCaptureSettings.Sensitivity.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text("Élevée : détecte les petits changements. Faible : source bruitée ou très compressée.")
                .font(.caption2).foregroundColor(.secondary)

            if let previous = previousAttachment {
                Picker("Lot", selection: $appendToPrevious) {
                    Text("Nouveau lot").tag(false)
                    Text("Ajouter au lot précédent (\(previous.slides.count) slides, \(previous.importedAt.formatted(date: .omitted, time: .shortened)))").tag(true)
                }
                .pickerStyle(.radioGroup)
            }

            if let catalogError { errorLabel(catalogError) }
            if let startError { errorLabel(startError) }

            HStack {
                Button("Annuler") { dismiss() }
                Spacer()
                Button("Commencer") { startCapture() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedWindowID == nil)
            }
        }
    }

    // MARK: - Face « suivre » (running / paused)

    private var followFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine
            if let configuration = service.configuration {
                Text("Fenêtre : \(configuration.windowTitle)").font(.caption).foregroundColor(.secondary)
            }
            if let preview {
                CropSelectionView(image: preview, rect: $crop, isLocked: true)
                    .frame(maxHeight: 200)
            }
            Divider()
            // L'instruction et l'action sont au même endroit.
            HStack {
                Text("Arrêtez la capture pour changer la fenêtre.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Arrêter") { service.stop() }
                    .buttonStyle(.bordered)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
            }
        }
        .task { await loadPreviewOfCurrentSource() }
    }

    // MARK: - Face « arrêtée » (stopped)

    private var stoppedFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine
            if let configuration = service.configuration {
                let stillThere = windows.contains { $0.id == configuration.windowID }
                if stillThere {
                    Text("Fenêtre : \(configuration.windowTitle)").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("La fenêtre « \(configuration.windowTitle) » a disparu. Choisissez-en une autre : la zone tracée est conservée.")
                        .font(.caption).foregroundColor(.orange)
                    windowPicker(onChange: { window in
                        service.updateSource(windowID: window.id, title: window.displayName)
                        Task { await loadPreview(of: window) }
                    })
                }
            }
            if let preview {
                CropSelectionView(image: preview, rect: $crop, isLocked: true)
                    .frame(maxHeight: 200)
            }
            Divider()
            HStack {
                Button("Terminer", role: .destructive) {
                    Task { await service.finish(); dismiss() }
                }
                .help("Clôt le lot : OCR, sauvegarde, indexation. Un prochain démarrage ouvrira un nouveau lot.")
                Spacer()
                Button("Fermer") { dismiss() }
                Button("Reprendre") { service.resume() }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.configuration.map { config in !windows.contains { $0.id == config.windowID } } ?? true)
            }
        }
        .task { await loadPreviewOfCurrentSource() }
    }

    // MARK: - Face « autorisation refusée »

    private var permissionFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enregistrement de l'écran refusé", systemImage: "exclamationmark.shield")
                .font(.headline)
            Text("OneToOne a besoin de l'autorisation « Enregistrement de l'écran » pour capturer les slides. Après l'avoir accordée, relancez OneToOne.")
                .font(.callout)
            Button("Ouvrir les Réglages") {
                settingsOpenFailed = !ScreenRecordingSettingsLink.open()
            }
            .buttonStyle(.borderedProminent)
            if settingsOpenFailed {
                Text("Impossible d'ouvrir les Réglages automatiquement. Chemin : \(ScreenRecordingSettingsLink.manualPath)")
                    .font(.caption).foregroundColor(.orange)
            }
            HStack {
                Button("Réessayer") { Task { await refreshWindows() } }
                Spacer()
                Button("Fermer") { dismiss() }
            }
        }
    }

    // MARK: - Composants

    private var statusLine: some View {
        HStack(spacing: 8) {
            switch service.state {
            case .running:
                Circle().fill(Color.blue).frame(width: 8, height: 8)
                Text("Capture en cours · \(service.capturedSlidesCount) slides").font(.headline)
            case .paused(let reason):
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("En pause · \(service.capturedSlidesCount) slides").font(.headline)
                    Text(reason).font(.caption).foregroundColor(.secondary)
                }
            case .stopped:
                Circle().fill(Color.gray).frame(width: 8, height: 8)
                Text("Arrêtée · \(service.capturedSlidesCount) slides").font(.headline)
            case .idle:
                EmptyView()
            }
        }
    }

    private func windowPicker(onChange: @escaping (ShareableWindow) -> Void) -> some View {
        HStack {
            Picker("Fenêtre", selection: Binding<CGWindowID?>(
                get: { selectedWindowID },
                set: { newValue in
                    // Une désélection (nil) est un no-op : un rafraîchissement de la liste
                    // ne doit pas effacer le tracé. Seul un passage vers une fenêtre
                    // différente et non nulle réinitialise.
                    guard let newValue, newValue != selectedWindowID else { return }
                    selectedWindowID = newValue
                    if let window = windows.first(where: { $0.id == newValue }) { onChange(window) }
                }
            )) {
                Text("Sélectionner une fenêtre").tag(nil as CGWindowID?)
                let meeting = windows.filter(\.isMeetingApp)
                let others = windows.filter { !$0.isMeetingApp }
                if !meeting.isEmpty {
                    Section("Réunions") {
                        ForEach(meeting) { Text($0.displayName).tag($0.id as CGWindowID?) }
                    }
                }
                if !others.isEmpty {
                    Section("Autres fenêtres") {
                        ForEach(others) { Text($0.displayName).tag($0.id as CGWindowID?) }
                    }
                }
            }
            Button { Task { await refreshWindows() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Rafraîchir la liste des fenêtres")
        }
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.red)
    }

    // MARK: - Actions

    private func refreshWindows() async {
        catalogError = nil
        let blacklist = Set(settings?.captureBlacklist ?? [])
        do {
            windows = try await WindowCatalog.shareableWindows(excludingAppNames: blacklist)
            permissionDenied = false
        } catch let error as SlideCaptureError where error == .screenRecordingDenied {
            permissionDenied = true
        } catch let error as SlideCaptureError where error == .noShareableWindows {
            windows = []
            catalogError = "Aucune fenêtre partageable. Ouvrez la réunion, puis rafraîchissez."
        } catch {
            catalogError = error.localizedDescription
        }
    }

    private func loadPreview(of window: ShareableWindow) async {
        preview = nil
        previewError = nil
        do {
            guard let image = try await WindowFrameSource(windowID: window.id).captureFrame() else {
                previewError = "fenêtre introuvable"
                return
            }
            preview = image
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { permissionDenied = true }
            previewError = error.localizedDescription
        }
    }

    private func loadPreviewOfCurrentSource() async {
        guard let configuration = service.configuration else { return }
        crop = configuration.crop
        if let image = try? await WindowFrameSource(windowID: configuration.windowID).captureFrame() {
            preview = image
        }
    }

    private func startCapture() {
        guard let window = selectedWindow else { return }
        startError = nil
        settings?.slideCaptureSensitivity = sensitivity
        let configuration = ScreenCaptureService.SessionConfiguration(
            windowID: window.id,
            windowTitle: window.displayName,
            crop: crop,
            sensitivity: sensitivity
        )
        do {
            try service.start(
                configuration: configuration,
                meeting: meeting,
                context: context,
                appendTo: appendToPrevious ? previousAttachment : nil
            )
            dismiss()
        } catch {
            startError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3 : Vérifier**

Run : `swift build 2>&1 | grep -E "error:|warning: .*ScreenCaptureConfigView" ; echo "fin"`
Expected : aucune erreur.

- [ ] **Step 4 : Commit**

```bash
git add -A OneToOne/Views/ScreenCaptureConfigView.swift OneToOne/Views/RectSelectorOverlay.swift
git commit -m "feat(capture): popover de capture en trois faces, apercu et trace de zone, ecran de refus d'autorisation"
```

---

### Task 7 : Barres et `MeetingView` — état réel, reprendre, terminer

**Files:**
- Modify: `OneToOne/Views/Meeting/MeetingTopChromeBar.swift:279-340` (`captureButton`)
- Modify: `OneToOne/Views/Meeting/MeetingContextualRecorderBar.swift:19-53,119-132`
- Modify: `OneToOne/Views/MeetingView.swift:250-260` (appel de la barre), `:401-410` (`onDisappear`)

**Interfaces:**
- Consumes: `ScreenCaptureService.state / isCapturing / hasOpenSession / stop() / resume() / finish() / snapshot()` (Task 4).
- Produces: `MeetingContextualRecorderBar` gagne `onResumeCapture: () -> Void`.

- [ ] **Step 1 : Barre haute — pastille d'état et menu**

Dans `MeetingTopChromeBar.swift`, remplacer intégralement la propriété `captureButton` (lignes 281 à 339) par :

```swift
    @ViewBuilder
    private var captureButton: some View {
        if captureService.hasOpenSession {
            HStack(spacing: 4) {
                Button(action: onShowSlides) {
                    HStack(spacing: 4) {
                        Circle().fill(captureStatusColor).frame(width: 6, height: 6)
                        Text(captureStatusText)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(captureStatusColor.opacity(0.15)))
                    .foregroundColor(captureStatusColor)
                }
                .buttonStyle(.plain)
                .help(captureStatusHelp)

                Menu {
                    Button { onShowCaptureSetup() } label: {
                        Label("Configurer…", systemImage: "rectangle.dashed.badge.record")
                    }
                    if captureService.isCapturing {
                        Button { captureService.stop() } label: {
                            Label("Arrêter la capture", systemImage: "stop.circle")
                        }
                    } else {
                        Button { captureService.resume() } label: {
                            Label("Reprendre la capture", systemImage: "play.circle")
                        }
                        Button(role: .destructive) { Task { await captureService.finish() } } label: {
                            Label("Terminer le lot", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(captureStatusColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Options de capture")
            }
        } else if capturedSlidesCount > 0 {
            Button(action: onShowSlides) {
                Label("Capture", systemImage: "camera.viewfinder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .overlay(alignment: .topTrailing) {
                Text("\(capturedSlidesCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 4, y: -4)
            }
        } else {
            Button(action: onShowCaptureSetup) {
                Label("Capture", systemImage: "camera.viewfinder").font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Bleu en cours, orange en pause, gris arrêtée : l'état réel, pas déduit.
    private var captureStatusColor: Color {
        switch captureService.state {
        case .running: return .blue
        case .paused: return .orange
        case .stopped, .idle: return .gray
        }
    }

    private var captureStatusText: String {
        let count = captureService.capturedSlidesCount
        switch captureService.state {
        case .running: return "\(count) slides"
        case .paused: return "En pause · \(count)"
        case .stopped: return "Arrêtée · \(count)"
        case .idle: return ""
        }
    }

    private var captureStatusHelp: String {
        if case .paused(let reason) = captureService.state { return reason }
        return "Voir les slides capturées"
    }
```

- [ ] **Step 2 : Barre contextuelle — snapshot, arrêt, reprise**

Dans `MeetingContextualRecorderBar.swift` :

Ligne 28, après `let onStopCapture: () -> Void`, ajouter :

```swift
    /// Reprend une capture arrêtée (session conservée).
    let onResumeCapture: () -> Void
```

Ligne 36, remplacer `captureService.isCapturing` par `captureService.hasOpenSession` dans le calcul de `visible` (la barre reste visible en `stopped`, pour offrir « Reprendre »). Ligne 48 et 52, remplacer aussi `captureService.isCapturing` par `captureService.hasOpenSession`.

Remplacer `captureSegment` (lignes 120 à 132) par :

```swift
    private var captureSegment: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .foregroundColor(captureService.state.isPaused ? .orange : (captureService.isCapturing ? .blue : .gray))
            switch captureService.state {
            case .paused(let reason):
                Text("Capture en pause : \(captureService.capturedSlidesCount) slides")
                    .font(.caption)
                    .help(reason)
            case .stopped:
                Text("Capture arrêtée : \(captureService.capturedSlidesCount) slides").font(.caption)
            default:
                Text("Capture : \(captureService.capturedSlidesCount) slides").font(.caption)
            }
            Button(action: onSnapshot) { Image(systemName: "camera.fill") }
                .buttonStyle(.bordered)
                .disabled(captureService.state != .running)
                .help("Forcer la capture de l'image courante")
            if captureService.isCapturing {
                Button(action: onStopCapture) { Image(systemName: "stop.fill") }
                    .buttonStyle(.bordered)
                    .help("Arrêter la capture (le lot reste ouvert)")
            } else {
                Button(action: onResumeCapture) { Image(systemName: "play.fill") }
                    .buttonStyle(.bordered)
                    .help("Reprendre la capture sur le même lot")
            }
        }
    }
```

- [ ] **Step 3 : `MeetingView` — câblage et clôture à la fermeture**

Dans `MeetingView.swift`, à l'appel de `MeetingContextualRecorderBar` (vers la ligne 256-257), remplacer :

```swift
                onSnapshot: { captureService.snapshot() },
                onStopCapture: { Task { await captureService.stop() } },
```

par :

```swift
                onSnapshot: { captureService.snapshot() },
                onStopCapture: { captureService.stop() },
                onResumeCapture: { captureService.resume() },
```

(Si la Task 4 a déjà posé `onStopCapture: { captureService.stop() }`, ajouter seulement la ligne `onResumeCapture`.)

Ligne 282, remplacer `.animation(.easeInOut(duration: 0.15), value: captureService.isCapturing)` par `.animation(.easeInOut(duration: 0.15), value: captureService.hasOpenSession)`.

Dans `.onDisappear` (vers la ligne 401), ajouter en **première** ligne du bloc, avant `let id = meeting.persistentModelID` :

```swift
            // Une session de capture ouverte est close avec l'écran : rien ne reste en
            // vol, le lot est réindexé.
            if captureService.hasOpenSession { Task { await captureService.finish() } }
```

- [ ] **Step 4 : Vérifier la compilation et la suite complète**

Run : `swift build 2>&1 | grep -E "error:" ; echo "build fini"`
Expected : aucune erreur.

Run : `swift test 2>&1 | tail -15`
Expected : toutes les suites vertes (XCTest : 0 échec ; Swift Testing : 0 échec). Noter les totaux pour `STATUS.md`.

- [ ] **Step 5 : Commit**

```bash
git add OneToOne/Views/Meeting/MeetingTopChromeBar.swift OneToOne/Views/Meeting/MeetingContextualRecorderBar.swift OneToOne/Views/MeetingView.swift
git commit -m "feat(capture): barres avec etat reel de la capture, reprendre et terminer, cloture a la fermeture de l'ecran"
```

---

### Task 8 : ADR, validation manuelle, `STATUS.md`

**Files:**
- Create: `docs/adr/2026-09-02-capture-slides-polling-empreinte.md`
- Modify: `STATUS.md` (nouvelle section en tête, après « Dernière mise à jour »)
- Modify: `docs/adr/README.md` (une ligne dans l'index, même format que les entrées existantes)

- [ ] **Step 1 : ADR**

```markdown
# ADR — Capture de slides : polling à empreinte avec stabilisation, à la place du flux SCStream + pHash

Date : 2026-09-02 · Statut : accepté · Spec : `docs/superpowers/specs/2026-09-02-capture-auto-slides-design.md`

## Contexte

La capture de slides d'avril 2026 utilisait un flux `SCStream` continu et un pHash 64 bits
comparé à l'image précédente. Elle capturait en pleine transition, ne dédoublonnait pas un
retour arrière, était aveugle à une dérive lente, prenait la fenêtre entière (vignettes des
participants comprises) et perdait la zone en pixels d'écran dès que la fenêtre bougeait.

## Décision

1. **Polling** `SCScreenshotManager` toutes les 500 ms, filtre reconstruit à chaque tick :
   absorbe déplacement, redimensionnement et changement d'écran sans code dédié.
2. **Empreinte 32×32 gris** (interpolation `.high`), distance = écart moyen normalisé.
3. **Détecteur à états** : on n'écrit qu'un contenu **stabilisé après un changement**
   (2 ticks), armé dès le départ, réarmé sur dérive lente par rapport au dernier slide
   acquitté, anti-doublon contre l'historique. Deux seuils distincts : mouvement (réglable)
   et identité (fixe).
4. **Zone en fractions** de la fenêtre, tracée sur un aperçu, origine en haut à gauche.
5. **Sessions** : arrêter conserve le lot ; reprendre continue ; terminer clôt. Un jeton de
   session, invalidé avant la première attente de la clôture, est revérifié après chaque
   `await` du tick.

## Conséquences

- Une transition animée donne un slide, une vidéo aucun, le curseur rien.
- Sur une dérive continue (défilement lent), la capture devient périodique (~3 s).
- `PerceptualHasher` et `RectSelectorOverlay` supprimés ; `SlideCapture.perceptualHash`
  reste dans le schéma, vide.
- Le module cœur (`Services/SlideCapture/`) est pur et testé sans écran ni permission ;
  ScreenCaptureKit n'est touché que par `WindowFrameSource` et `WindowCatalog`.
- Origine : prototype Teams-Capture (validation réelle : 9 h 30 de fonctionnement, 8 images).
```

- [ ] **Step 2 : Build de l'app et validation manuelle**

Run : `Scripts/bump-and-build.sh dev`
Expected : `.app` installée dans `~/Applications` et lancée.

Dérouler, sur une vraie présentation (Teams, Zoom ou Meet, ou un Keynote/PowerPoint en
plein écran dans une autre fenêtre), et noter chaque résultat dans `STATUS.md` :

1. Ouvrir une réunion → « Capture » → autorisation demandée la première fois ; refuser une
   fois pour voir l'écran de refus et le bouton « Ouvrir les Réglages » ; accorder ; relancer.
2. Choisir la fenêtre, tracer une zone : vérifier que **le haut et le bas** du slide écrit
   correspondent au tracé (ouvrir le PNG dans `~/Library/Application Support/OneToOne/recordings/<uuid>/slides/`).
3. Faire défiler trois slides : trois fichiers, pas plus. Revenir sur le premier : rien de plus.
4. Déplacer puis redimensionner la fenêtre source : la zone suit.
5. Fermer la fenêtre source : pastille orange « En pause » ; la rouvrir : bleu, reprise seule.
6. Arrêter → « Arrêtée · N » ; Reprendre → numérotation continue ; Terminer → OCR, texte
   agrégé visible dans la galerie, lot clos.
7. Rouvrir « Capture » : « Ajouter au lot précédent » proposé ; un slide déjà présent n'est
   pas réécrit ; un nouveau l'est avec l'index suivant.
8. Fenêtre source **entièrement** recouverte par une autre : la capture continue-t-elle ?
   Noter le résultat (non couvert par la sonde du prototype).

- [ ] **Step 3 : `STATUS.md`**

Mettre à jour la ligne « Dernière mise à jour », puis insérer en tête une section
« Capture automatique de slides (2026-09-02) » qui donne : la branche, le commit, ce qui
est livré (référence à la spec et à l'ADR), les totaux exacts de `swift test` de la Task 7,
les résultats **réels** des huit points de validation manuelle (ce qui a marché, ce qui n'a
pas marché, ce qui n'a pas été fait), et la prochaine action (PR à ouvrir ; chantier séparé
« auto-start avec l'auto-record Teams » en attente).

Ajouter dans `docs/adr/README.md` une ligne pour le nouvel ADR, au format des lignes existantes.

- [ ] **Step 4 : Commit et PR**

```bash
git add docs/adr/2026-09-02-capture-slides-polling-empreinte.md docs/adr/README.md STATUS.md
git commit -m "docs(capture): ADR polling a empreinte, STATUS avec validation manuelle"
git push -u origin feat/capture-auto-slides
```

Ouvrir la PR avec `gh pr create` : titre « Capture automatique de slides : fenêtre + zone,
détection de stabilité, arrêt/reprise », corps = résumé de la spec (§1 problème, §2
décisions), lien vers la spec et l'ADR, totaux de tests, résultats de validation manuelle,
et la mention « Pas de dépendance nouvelle : module cœur copié depuis Teams-Capture ».

---

## Auto-revue du plan

**Couverture de la spec** : §3 module cœur → Tasks 1-3 ; §4.3 sensibilité persistée → Task 2 ; §4.7 catalogue → Task 3 ; §5 coordinateur (états, jeton, écriture 4 chiffres, encodage hors thread, réamorçage, clearError unique) → Task 4 ; §6.1 popover trois faces + refus → Task 6 ; §6.2 CropSelectionView → Task 5 ; §6.3 barres → Task 7 ; §6.4 clôture à la fermeture → Task 7 ; §7 Info.plist → Task 3 ; §8 tests + trois mutations → Tasks 1, 2, 4 ; §9 validation manuelle → Task 8 ; §11 ADR/STATUS → Task 8.

**Cohérence des types** : `SlideCaptureSettings.Sensitivity.movementThreshold` / `identityThreshold` (Task 2) utilisés par `SlideDetector` (Task 2) ; `ScreenCaptureService.SessionConfiguration(windowID:windowTitle:crop:sensitivity:)` (Task 4) construit par `ScreenCaptureConfigView.startCapture()` (Task 6) ; `ShareableWindow.displayName` / `isMeetingApp` (Task 3) utilisés dans le picker (Task 6) ; `service.stop()` synchrone (Task 4) appelé sans `Task` par les barres (Task 7) ; `snapshotForTesting()` et `cancelLoopForTesting()` (Task 4) utilisés par `ScreenCaptureServiceTests` (Task 4).
