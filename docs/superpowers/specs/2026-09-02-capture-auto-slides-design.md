# Design — Capture automatique de slides (fenêtre + zone, détection de stabilité)

Date : 2026-09-02
Branche : `feat/capture-auto-slides`
Source de la conception : `~/Documents/dev/perso/Teams-Capture/One2One-specs.md`
(spécifications de portage écrites depuis le prototype Teams Capture, 62 tests verts).

## 1. Problème

Pendant une réunion, un présentateur partage des slides que les participants n'ont pas.
OneToOne sait déjà capturer des slides (`ScreenCaptureService`, avril 2026), mais le
mode « Auto » actuel est faible et le mode « Manuel » oblige à cliquer à chaque slide :

- flux `SCStream` continu, comparaison pHash **uniquement avec l'image précédente**, aucune
  attente de stabilisation : capture en pleine transition, pas de dédoublonnage d'un retour
  arrière, aveugle à une dérive lente ;
- en mode « Fenêtre », la fenêtre entière est prise, vignettes des participants comprises ;
- en mode « Zone d'écran », la zone est en pixels d'écran et casse dès que la fenêtre bouge ;
- arrêter la capture **clôt** la session : impossible de reprendre et d'ajouter des slides au
  même lot.

Objectif : choisir une fenêtre (Teams, Zoom, Meet ou autre), tracer la zone du slide **sur
un aperçu de cette fenêtre**, et obtenir **une image par slide, sans aucun clic** pendant la
réunion, avec arrêt et reprise sur le même lot.

## 2. Décisions

| # | Décision |
| --- | --- |
| 1 | La capture est **toujours automatique**. Le sélecteur Manuel / Auto disparaît. Le bouton snapshot reste, comme forçage ponctuel. |
| 2 | La zone se trace sur un **aperçu de la fenêtre choisie** et se stocke en **fractions** `0…1` de la fenêtre. Par défaut : fenêtre entière. |
| 3 | Le mode « Zone d'écran précise » (rectangle en pixels d'écran, sans fenêtre) est **supprimé**. `RectSelectorOverlay.swift` avec lui. |
| 4 | **Arrêter** ne clôt pas la session : on peut **Reprendre** sur le même lot. **Terminer** clôt. |
| 5 | Si la réunion a déjà un lot de slides, le popover propose **« Ajouter au lot précédent »** (détecteur réamorcé depuis les PNG existants) ou « Nouveau lot ». Couvre la relance de l'app. |
| 6 | Le module cœur de Teams-Capture est **copié dans la cible OneToOne** avec ses tests. Pas de dépendance SwiftPM nouvelle. L'interface est réécrite aux conventions de OneToOne. |
| 7 | Le pipeline aval de OneToOne est **conservé** : `SlideCapture` SwiftData, OCR, texte agrégé, indexation RAG, export PDF et mail. `SessionWriter` et le PDF de Teams-Capture ne sont pas portés. |
| 8 | Deux seuils **distincts** dès le départ : mouvement (image N contre N−1) et identité (anti-doublon contre l'historique). Corrige le piège 5 des specs sources. |
| 9 | Démarrage automatique lié à l'auto-record Teams : **hors périmètre**, chantier séparé. |

Approches écartées : dépendance SwiftPM locale sur Teams-Capture (dépendance nouvelle,
module Swift 6 face à une app en mode Swift 5, isolation d'acteur entre modules) ; rustine
du service actuel (garderait `SCStream` qui ne suit pas le redimensionnement, sans zone liée
à la fenêtre).

## 3. Architecture

```
OneToOne/Services/SlideCapture/            ← module cœur, pur, sans UI
  SlideFingerprint.swift      empreinte 32×32 gris, distance normalisée
  NormalizedRect.swift        zone en fractions, géométrie du tracé, crop
  SlideCaptureSettings.swift  constantes, sensibilité, deux seuils
  SlideDetector.swift         machine à états de la détection, aucune I/O
  FrameSource.swift           protocole FrameSource, ShareableWindow, SlideCaptureError
  WindowFrameSource.swift     capture d'une fenêtre par SCScreenshotManager
  WindowCatalog.swift         énumération et tri des fenêtres partageables

OneToOne/Services/ScreenCaptureService.swift   ← coordinateur (réécrit, nom conservé)
OneToOne/Views/ScreenCaptureConfigView.swift   ← popover de configuration (réécrit)
OneToOne/Views/CropSelectionView.swift         ← aperçu + tracé de la zone (nouveau)
OneToOne/Models/AppSettings.swift              ← + slideCaptureSensitivityRaw
Info.plist                                     ← + NSScreenCaptureUsageDescription

Supprimés : Services/PerceptualHasher.swift, Views/RectSelectorOverlay.swift
```

Frontière : `ScreenCaptureService` est le seul type qui connaisse l'enchaînement et
SwiftData. `SlideDetector` ne connaît que des empreintes ; `WindowFrameSource` que
ScreenCaptureKit ; les vues que l'état publié.

## 4. Module cœur

### 4.1 `SlideFingerprint`

Réduction de l'image recadrée en 32×32 échantillons gris (1024 octets) par un `CGContext`
avec `interpolationQuality = .high` (moyenne réelle des pixels : c'est ce qui rend l'empreinte
insensible au curseur ; ne pas baisser). Distance = `Σ|a−b| / (1024 × 255)`, dans `0…1`.

Mesures de référence à reproduire en tests : curseur 12×18 pt sur 400×300 → distance
≈ 0,0014 ; bandeau de 2 % de la hauteur → ≈ 0,0194.

### 4.2 `NormalizedRect`

`x, y, width, height` en fractions, bornées à la construction (une zone invalide est
inconstructible). Origine **en haut à gauche** (SwiftUI local et `CGImage.cropping(to:)`).
Fonctions pures : `init(from:to:in:)` depuis un glissement, `fromDrag(…, minimumFraction:
0.05, current:)` qui rejette un glissement accidentel, `displayRect(in:)`, `pixelRect(…)`,
`apply(to:)`. `Codable` : c'est la forme mémorisée entre arrêt et reprise.

### 4.3 `SlideCaptureSettings`

| Constante | Valeur |
| --- | --- |
| Période de polling | 500 ms |
| Ticks stables requis | 2 (première écriture possible au 3e tick, soit 1,5 s) |
| Seuil de mouvement, sensibilité élevée / normale / faible | 0,010 / 0,020 / 0,045 |
| Seuil d'identité (anti-doublon) | 0,020, **indépendant** de la sensibilité |
| Fraction minimale d'un tracé | 5 % par axe |
| Côté minimal d'une fenêtre proposée | 200 pt |

`Sensitivity: String, CaseIterable` (`low`, `normal`, `high`) avec libellés français.
Persistée dans `AppSettings.slideCaptureSensitivityRaw: String = "normal"` + wrapper calculé
(convention `…Raw`). Champ avec valeur par défaut → migration légère, pas de `SchemaV2`.

### 4.4 `SlideDetector`

Repris tel quel des specs sources, avec le second seuil :

```
consume(empreinte) :
  pas de précédente → mémoriser, .settling
  d = distance(courante, précédente)
  d >= seuilMouvement → armer, compteur = 0, .settling
  sinon :
    non armé et distance(courante, acquittée) >= seuilMouvement → armer, compteur = 0
    compteur += 1
    armé et compteur >= ticksStables :
      désarmer, compteur = 0
      une empreinte enregistrée à moins de seuilIdentité → acquitter, .duplicate
      sinon → enregistrer, acquitter, .newSlide
    sinon .ignore
  mémoriser courante comme précédente
```

Invariants à verrouiller par tests de **séquence complète** de décisions, pas par
comptage : armé dès la construction (le slide de titre est écrit) ; un doublon n'est signalé
qu'une fois ; l'acquittement est mis à jour sur doublon **comme** sur nouveau slide ; une
dérive lente finit par produire un slide.

API de réamorçage : `mutating func seed(_ recorded: [SlideFingerprint])` ajoute des
empreintes à l'historique sans changer l'état de stabilisation. Sert à « Ajouter au lot
précédent ».

### 4.5 `FrameSource`, `ShareableWindow`, `SlideCaptureError`

```swift
protocol FrameSource: Sendable {
    /// nil = la source a disparu (mettre en pause). Erreur = échec d'API (visible, ne stoppe pas).
    func captureFrame() async throws -> CGImage?
}
struct ShareableWindow: Identifiable, Equatable, Sendable {
    let id: CGWindowID; let title: String; let appName: String
    let bundleIdentifier: String?; let frame: CGRect
}
enum SlideCaptureError: Error, Equatable, LocalizedError {
    case screenRecordingDenied, noShareableWindows, captureFailed(String)
    static func isPermissionDenial(_ error: any Error) -> Bool
}
```

`isPermissionDenial` est pure : `SCStreamErrorDomain` **et** code `−3801`
(`SCStreamError.Code.userDeclined`), ou une `SlideCaptureError.screenRecordingDenied` déjà
traduite. Même code dans un autre domaine → pas un refus. Aucun chemin ne convertit un échec
en `nil`.

### 4.6 `WindowFrameSource`

Un appel `SCScreenshotManager.captureImage(contentFilter:configuration:)` par tick, filtre
`desktopIndependentWindow` **reconstruit à chaque capture** (absorbe déplacement,
redimensionnement, changement d'écran ; ne pas mettre en cache). Configuration : taille de la
fenêtre × facteur d'échelle, curseur masqué, `captureResolution = .best`, ombres ignorées,
fond opaque. Fenêtre absente de `SCShareableContent` → `nil`.

### 4.7 `WindowCatalog`

`shareableWindows(excludingAppNames:)` : `onScreenWindowsOnly: false` comme
`WindowFrameSource` (une réunion Teams en plein écran vit sur son propre Space et n'est pas
« à l'écran »), côté ≥ 200 pt, titre non vide, calque `0` seulement (pas de panneau flottant
ni d'incrustation), hors-écran gardé uniquement pour une fenêtre de réunion, exclusion des
fenêtres de OneToOne (`onetoone`, `one2one`) et de `AppSettings.captureBlacklist`.
Tri `prioritized(_:)`, fonction pure testée : réunion en tête (bundle `com.microsoft.teams2`,
`com.microsoft.teams`, `us.zoom.xos`, ou titre contenant « Meet »), puis surface décroissante.

## 5. Coordinateur : `ScreenCaptureService`

`@MainActor final class ScreenCaptureService: ObservableObject`, nom et point d'injection
conservés (`MeetingView`, `MeetingTopChromeBar`, `MeetingContextualRecorderBar`).

### 5.1 État publié

```swift
enum State: Equatable { case idle, running, paused(String), stopped }
@Published private(set) var state: State
@Published private(set) var currentAttachment: MeetingAttachment?
@Published var lastError: String?
@Published private(set) var ocrProgress: (current: Int, total: Int)?
var isCapturing: Bool { state == .running || state.isPaused }   // compat barres
var hasOpenSession: Bool { currentAttachment != nil }
var capturedSlidesCount: Int { currentAttachment?.slides.count ?? 0 }
```

**Invariant** : une session est ouverte (`currentAttachment != nil`) si et seulement si
l'état est `running`, `paused` ou `stopped`.

### 5.2 Configuration d'une session

```swift
struct SessionConfiguration: Equatable {
    var windowID: CGWindowID
    var windowTitle: String
    var crop: NormalizedRect
    var sensitivity: SlideCaptureSettings.Sensitivity
}
```

Conservée dans le service pendant toute la session (arrêt compris). Modifiable en `stopped`
uniquement : `updateSource(windowID:title:)` pour reprendre sur une autre fenêtre si la
première a disparu, en gardant la zone.

### 5.3 Opérations

| Opération | Préconditions | Effet |
| --- | --- | --- |
| `beginSession(configuration:meeting:context:appendTo:)` | `idle` | Crée l'attachment `kind: "slides"` **ou** reprend `appendTo` (réamorce le détecteur depuis ses PNG), crée le dossier `recordings/<uuid>/slides/` **tout de suite** (échec immédiat si non inscriptible), `lastError = nil`, état `running`. Ne lance pas la boucle. |
| `start(…)` | `idle` | `beginSession` puis lance la boucle. |
| `resume()` | `stopped` **et** jeton non `nil` | Republie `running`, relance la boucle. Même attachment, même détecteur. Le jeton écarte la fenêtre d'attente OCR de `finish()`, qui publie `stopped` avant d'attendre. Idem pour `updateSource(windowID:title:)`. |
| `stop()` | `running`, `paused` | Annule la boucle, publie `stopped`. Rien d'autre. |
| `finish()` | session ouverte | `stop()`, invalide la session (jeton à `nil` **avant** toute attente), attend les tâches OCR avec `ocrProgress` — un OCR qui se termine là écrit **bien** son texte : la tâche OCR ne consulte pas le jeton, elle vérifie la vivacité de ses modèles —, sauvegarde, annule toute boucle relancée entre-temps, `currentAttachment = nil`, réindexation RAG, état `idle`. |
| `abandon()` | — | Ferme sans **rien** sauvegarder ni réindexer : boucle et tâches OCR annulées, tout relâché, état `idle`. Chemin de la réunion supprimée (`MeetingView.onDisappear`), dont la cascade emporte l'attachment. |
| `snapshot()` | `running` | Capture immédiate, hors boucle : recadre et écrit sans consulter le détecteur, puis `seed` l'empreinte dans l'historique. |
| `tick()` | — | Un cycle. Appelable directement par les tests. |
| `deleteSlide(_:)` | — | Inchangé. |

### 5.4 `tick()`

```
jeton = self.sessionToken ; guard jeton != nil
image = try await source.captureFrame()
  erreur → si jeton toujours courant : lastError = message ; state = .paused("Capture impossible : …")
guard jeton toujours courant
image == nil → state = .paused("Fenêtre source introuvable. La capture reprendra si elle réapparaît.")
si state est .paused → state = .running ; lastError = nil
recadrer (crop.apply) → empreinte ; échec → lastError = "La zone de capture est vide ou invalide."
detector.consume(empreinte) == .newSlide → écrire
  écriture : encodage PNG hors thread principal (CGImageDestination) ; après l'await,
  guard jeton toujours courant, puis insertion SlideCapture + OCR + texte agrégé
```

Le jeton de session est un `UUID` régénéré à chaque `beginSession` et remis à `nil` par
`finish()` **avant** la première attente. Chaque étape après un `await` revérifie le jeton
**et que l'état est toujours running/paused** : un tick suspendu pendant `finish()` ou
`stop()` n'écrit ni ne publie rien (piège 12 des specs sources) — sans le contrôle d'état, un
tick relâché après `stop()` publierait `.paused` par-dessus `.stopped`, dont `resume()` ne
sait pas repartir. `guard !Task.isCancelled` ne suffirait pas : `tick()` est aussi appelé hors
boucle.

La boucle : `Task { [weak self] in while !Task.isCancelled { guard let self else { break }
await self.tick(); sleep(période) } }`. Le test du propriétaire à chaque itération empêche
une tâche fantôme.

### 5.5 Écriture et persistance

Inchangé dans l'esprit, précisé :

- fichiers `slide-NNNN-HHmmss.png` (**quatre** chiffres), index de départ =
  `(attachment.slides.map(\.index).max() ?? 0) + 1` — le maximum et non le nombre de slides,
  qu'une suppression rendrait faux (index déjà pris) ;
- l'encodage PNG (`CGImageDestination`) s'exécute dans une tâche détachée ; l'insertion
  SwiftData revient sur le `MainActor` ;
- `SlideCapture.perceptualHash` reste dans le schéma, n'est plus alimenté (chaîne vide).
  `BackupService` continue de le sérialiser tel quel ;
- OCR par slide et `rebuildAttachmentText()` comme aujourd'hui ;
- réamorçage : `SlideFingerprint(image:)` sur chaque PNG existant de l'attachment repris
  (déjà recadrés à l'écriture), passé à `detector.seed(_:)`.

### 5.6 Message d'erreur

`lastError` est remis à `nil` dans une **seule** fonction privée appelée sur tous les chemins
de succès : `beginSession`, `resume`, tick réussi après pause, `finish`. Jamais posé sans
passer par elle ailleurs qu'aux points de panne.

## 6. Interface

### 6.1 Popover `ScreenCaptureConfigView`

Trois faces selon l'état du service.

**`idle` — configurer**

- Liste des fenêtres (`WindowCatalog`) avec bouton de rafraîchissement manuel. Sélection
  par `CGWindowID`. Une désélection (valeur nulle) est un **no-op** ; la zone n'est remise à
  `.full` que lors d'un passage vers une fenêtre **différente et non nulle**.
- Aperçu de la fenêtre choisie : une capture `WindowFrameSource` au moment de la sélection,
  affichée par `CropSelectionView`, bouton « Toute la fenêtre ». Si l'aperçu échoue :
  message, la zone reste `.full`, « Commencer » reste possible.
- Sensibilité : `Picker` segmenté trois niveaux, lu et écrit dans `AppSettings`.
- Si la réunion possède déjà un attachment `slides` : `Picker` « Nouveau lot » / « Ajouter
  au lot précédent (N slides, HH:mm) », défaut « Ajouter » si le lot date de moins de
  quatre heures, « Nouveau » sinon.
- « Commencer » désactivé tant qu'aucune fenêtre n'est choisie.

**`running` / `paused` — suivre**

- État réel : « Capture en cours · N slides » ou « En pause · raison ».
- Contrôles de configuration **désactivés** (ils n'auraient aucun effet, la configuration
  est figée pendant la boucle). Un bandeau le dit, et le bouton « Arrêter » est **au même
  endroit** que le bandeau.

**`stopped` — reprendre ou terminer**

- « Arrêtée · N slides ». Boutons « Reprendre » et « Terminer ».
- Si la fenêtre source n'est plus dans le catalogue : liste des fenêtres proposée pour en
  choisir une autre (`updateSource`), zone conservée, aperçu mis à jour.
- La zone et la sensibilité restent verrouillées (le détecteur est celui de la session).

**Autorisation refusée** (toutes faces) : remplace le contenu par une explication et un bouton
« Ouvrir les Réglages » : `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture`,
repli sur `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` si
l'ouverture renvoie `false`, sinon le chemin manuel affiché en clair (Réglages Système →
Confidentialité et sécurité → Enregistrement de l'écran).

### 6.2 `CropSelectionView`

`GeometryReader` **portant lui-même** `.aspectRatio(ratioImage, contentMode: .fit)`, de sorte
que `geometry.size` soit exactement la taille d'affichage : aucun calcul de décalage. Zone
retenue nette, pourtour assombri, glissement en cours dessiné en direct, `fromDrag` à la fin
du geste. Paramètre `isLocked` pendant une session.

### 6.3 Barres existantes

- `MeetingTopChromeBar.captureButton` : pastille bleue en `running`, **orange** avec la
  raison en infobulle en `paused`, grise « Arrêtée · N » en `stopped`. Menu : « Configurer… »
  ouvre le popover ; « Arrêter » en `running`/`paused` ; « Reprendre » et « Terminer » en
  `stopped`.
- `MeetingContextualRecorderBar.captureSegment` : visible si session ouverte ; snapshot
  actif seulement en `running` ; bouton stop en `running`/`paused`, remplacé par
  « Reprendre » en `stopped`. Le « Terminer » n'est proposé que dans le menu de la barre
  haute et le popover, pour éviter un clic malheureux dans la barre contextuelle.
- `MeetingView` : `onStopCapture` appelle `stop()` (plus `finish`) ; nouveaux relais
  `onResumeCapture`, `onFinishCapture` ; `currentSlides` inchangé (source de vérité :
  `currentAttachment` pendant la session).

### 6.4 Sortie de la réunion

Fermer la fenêtre de réunion avec une session ouverte appelle `finish()` (comportement
actuel de l'arrêt) : rien ne reste en vol, et le lot est réindexé.

## 7. Autorisation, bundle

- `Info.plist` : `NSScreenCaptureUsageDescription` = « OneToOne capture les slides projetées
  pendant vos réunions pour les retranscrire et les joindre au compte-rendu. »
- `CFBundleIdentifier` = `com.onetoone.app`, déjà stable ; `Scripts/bump-and-build.sh`
  produit le `.app` nécessaire : `SCScreenshotManager` plante hors session graphique
  (`CGS_REQUIRE_INIT`). Les tests ne l'appellent jamais.

## 8. Tests

Swift Testing, dans `Tests/`, sans écran, sans permission, sans horloge.

| Fichier | Cas |
| --- | --- |
| `SlideFingerprintTests` | curseur 12×18 sur 400×300 < 0,010 ; bandeau 2 % ≈ 0,019 ; distance(a,a) = 0 ; symétrie ; noir/blanc = 1 |
| `NormalizedRectTests` | même zone sur deux tailles d'image ; bornage ; **ancrage absolu asymétrique** (glissement dans le quart supérieur gauche d'une vue non carrée, quatre composantes contre quatre nombres distincts) ; `fromDrag` sous 5 % rend `current` ; crop d'une image de test en tenant compte de l'axe Y de `CGContext` |
| `SlideDetectorTests` | séquences complètes : statique → `[settling, ignore, newSlide, ignore…]` ; transition animée → un seul `newSlide` ; vidéo → aucun ; retour arrière → `duplicate` une fois puis slide suivant ; **dérive lente** +0,005 × 40 → au moins un `newSlide` ; sensibilité élevée ne rend pas l'anti-doublon laxiste (deux seuils) ; `seed` rend doublon un slide déjà connu |
| `SlideCaptureErrorTests` | table de vérité : domaine SC + −3801 → refus ; domaine SC + autre → non ; autre domaine + −3801 → **non** ; erreur déjà traduite → selon le cas |
| `WindowCatalogTests` | `prioritized` : Teams, Zoom, Meet en tête ; surface décroissante ; exclusion OneToOne et liste noire ; côté < 200 écarté |
| `ScreenCaptureServiceTests` (source factice + `ModelContainer` en mémoire) | tick inerte avant `beginSession` ; `nil` → `paused`, image → `running` et `lastError` effacé ; erreur → `paused` avec message ; arrêt → `stopped`, reprise → `running`, numérotation continue sur le **même** attachment ; retour arrière après reprise → doublon ; `finish` → `idle`, `start` suivant → **nouvel** attachment ; **tick en vol pendant `finish`** n'écrit rien ; `snapshot` écrit hors détecteur ; réamorçage depuis PNG existants ; dossier non inscriptible → `beginSession` échoue avant toute capture |

**Preuve par mutation**, obligatoire pour trois tests avant de les déclarer verts : dérive
lente (retirer le réarmement sur l'acquitté), axe Y (inverser `y` dans `displayRect`), tick en
vol (retirer la revérification du jeton après l'`await` d'écriture). Chaque test doit rougir
sous la mutation, puis reverdir.

## 9. Validation manuelle (une fois, sur une vraie présentation)

Tracé : vérifier **le haut et le bas** du rectangle capturé. Déplacer puis redimensionner la
fenêtre source, la zone doit suivre. Cycle arrêt → reprise → terminer. État affiché pendant la
capture, pause quand on ferme la fenêtre source, reprise quand on la rouvre. Chemin de refus
d'autorisation. Fenêtre source entièrement recouverte par une autre (non couvert par la sonde
des specs sources).

## 10. Hors périmètre

Démarrage automatique de la capture depuis `TeamsAutoRecordCoordinator` ; réassemblage d'un
PDF depuis un dossier (l'export PDF existant lit `SlideCapture`) ; élément de barre de menus ;
réglage de la période ou du nombre de ticks dans l'interface.

## 11. Fichiers touchés

| Fichier | Action |
| --- | --- |
| `OneToOne/Services/SlideCapture/*.swift` (7) | nouveaux |
| `OneToOne/Services/ScreenCaptureService.swift` | réécrit |
| `OneToOne/Services/PerceptualHasher.swift` | supprimé |
| `OneToOne/Views/ScreenCaptureConfigView.swift` | réécrit |
| `OneToOne/Views/CropSelectionView.swift` | nouveau |
| `OneToOne/Views/RectSelectorOverlay.swift` | supprimé |
| `OneToOne/Views/MeetingView.swift`, `Meeting/MeetingTopChromeBar.swift`, `Meeting/MeetingContextualRecorderBar.swift` | retouches (état, reprendre, terminer) |
| `OneToOne/Models/AppSettings.swift` | + `slideCaptureSensitivityRaw` |
| `Info.plist` | + `NSScreenCaptureUsageDescription` |
| `Tests/SlideFingerprintTests.swift`, `NormalizedRectTests.swift`, `SlideDetectorTests.swift`, `SlideCaptureErrorTests.swift`, `WindowCatalogTests.swift`, `ScreenCaptureServiceTests.swift` | nouveaux |
| `docs/adr/2026-09-02-capture-slides-polling-empreinte.md` | ADR : remplacement du flux `SCStream` + pHash par le polling à empreinte avec stabilisation |
| `STATUS.md` | mis à jour en fin de session |
