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

## Alternatives étudiées

- **Dépendance SwiftPM locale sur le prototype Teams-Capture.** Écartée : nouvelle
  dépendance du dépôt, module Swift 6 contre application Swift 5, isolation d'acteurs à
  faire traverser la frontière entre les deux — le coût d'intégration dépassait celui d'une
  réécriture du module cœur, déjà petit et pur.
- **Patcher le service `SCStream` + pHash existant.** Écartée : elle aurait conservé un flux
  qui ne suit pas le redimensionnement de la fenêtre et aucun recadrage lié à la fenêtre
  elle-même — les deux défauts structurants à l'origine de cette ADR restaient entiers,
  patcher le comparateur d'images seul n'y change rien.

## Conséquences

- Une transition animée donne un slide, une vidéo aucun, le curseur rien.
- Sur une dérive continue (défilement lent), la capture devient périodique (~3 s).
- `PerceptualHasher` et `RectSelectorOverlay` supprimés ; `SlideCapture.perceptualHash`
  reste dans le schéma, vide.
- Le module cœur (`Services/SlideCapture/`) est pur et testé sans écran ni permission ;
  ScreenCaptureKit n'est touché que par `WindowFrameSource` et `WindowCatalog`.
- Origine : prototype Teams-Capture (validation réelle : 9 h 30 de fonctionnement, 8 images).
