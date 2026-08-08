# Réécrire l'éditeur en reprenant l'architecture d'appflowy-editor

**Statut** : validée
**Date** : 2026-08-08
**Auteur de la décision** : l'auteur du dépôt

## Contexte

Trois chantiers successifs ont porté sur le rendu des blocs mermaid dans
l'éditeur Markdown : superposition carte/source, géométrie du cadre, ancrage
sur le mauvais repère TextKit. Chaque correctif était juste, mesuré et relu ;
le résultat restait décevant.

Le point commun de ces trois défauts n'est pas une erreur de programmation.
C'est que **les blocs sont simulés à l'intérieur d'un seul `NSTextView`** :
espacements de paragraphe détournés pour réserver de la place, rect de fragment
confondu avec rect de texte, dessin qui déborde sur le bloc voisin, clips à
élargir à la main. Cette classe de bug n'existe que là.

## Décision

Réécrire l'éditeur en reprenant l'architecture d'
[appflowy-editor](https://github.com/AppFlowy-IO/appflowy-editor) : arbre de
nœuds, `Delta` pour le texte inline, transactions et undo explicites, registre
de constructeurs de vues, une vue par bloc.

**La licence AGPL-3.0 d'appflowy-editor est acceptée pour ce dépôt.**

Le fichier de licence du dépôt n'est **pas** modifié à ce stade : la bascule
devient effective au premier point qui contient réellement du code dérivé
(le modèle de document). Le prototype qui suit cette décision n'en contient
aucune ligne.

## Alternatives étudiées

1. **Continuer à corriger l'existant.** Rejetée : trois chantiers l'ont
   essayée, chacun corrigeant un symptôme réel de la même cause.
2. **Sortir seulement les blocs-cartes (mermaid, tableaux, images) du flux
   TextKit en `NSView` ancrées.** Non rejetée — c'est le **repli** si le
   prototype échoue. Supprime la classe de bug sans réécriture, mais laisse
   l'architecture inchangée.
3. **Passer à TextKit 2.** Rejetée : change le moteur de mise en page sans
   changer le fait que les blocs restent simulés dans une seule vue.
4. **Éditeur en WebView.** Rejetée : abandonne l'intégration macOS native
   (saisie, correcteur, services) pour un problème de mise en page.

## Conséquences

Positives :

- supprime à la racine la classe de bug des trois derniers chantiers ;
- les points 1 à 3 (modèle, transactions, undo) sont réellement transposables
  depuis appflowy-editor ;
- une vue par bloc rend la géométrie de chaque bloc indépendante.

Négatives :

- le dépôt bascule sous AGPL-3.0 dès le premier code dérivé ;
- coût réel : 12 365 lignes sur 45 fichiers, 41 fichiers de tests, six
  consommateurs hors module (`MeetingView`, `DetailsViews`, `PrepWindow`,
  `MarkdownNoteEditor`, `EditableTextField`, `CollaboratorMentionSource`) ;
- **le risque central est solitaire** : la sélection et la navigation du
  curseur à travers les blocs, gratuites en Flutter, sont à reconstruire
  entièrement en AppKit. Sur ce point précis, appflowy-editor n'a rien à nous
  apprendre et il n'existe aucun code à transposer.

## Décisions annulées

Cet ADR annule trois décisions structurantes de `STATUS.md` :

- n°1 « le Markdown reste la source de vérité ; aucun modèle de blocs
  persistant séparé n'est introduit » ;
- n°2 « TextKit 1 est conservé » ;
- n°4 « aucun code AppFlowy n'est repris ».

La décision n°3 (les couleurs libres ne sont pas sérialisées) et la n°5 (les
liens internes restent routés par une closure injectée) restent valides.

## Suite

Le premier sous-projet est un **prototype jetable** qui sonde le risque
central, spécifié dans
`docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`. Son
verdict fera l'objet d'un ADR distinct.
