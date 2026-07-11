# Éditeur de notes markdown avec bascule Édition / Aperçu

Date : 2026-07-10

## Contexte

Les zones « Notes live » et « Préparation » de la réunion utilisent
`MarkdownEditorView` (→ `MarkdownTextEditor` → `EditorRepresentable`, un
`NSTextView` à stylage WYSIWYG partiel) piloté par `MarkdownToolbar`. En
pratique l'éditeur affiche le markdown quasi brut (`[ACTION]`, `*` visibles) sans
jamais offrir un rendu propre. L'utilisateur veut écrire du markdown puis basculer
vers un **aperçu rendu**, l'aperçu étant le mode par défaut.

## Objectif

Fournir, pour **Notes live** et **Préparation** uniquement, un éditeur avec deux
modes commutables :
- **Aperçu** (défaut) : markdown rendu proprement (titres, puces, gras).
- **Édition** : saisie du markdown avec la barre d'outils actuelle (B/I/titres/
  listes + tags Action/Risque/Decision/Projet), insertion à la position du curseur.

## Design

Nouveau composant réutilisable **`MarkdownNoteEditor`** :

```
MarkdownNoteEditor(text: Binding<String>, editorID: String, features: Set<MarkdownFeature>)
  ├─ En-tête : Picker segmenté « Aperçu | Édition »  (+ MarkdownToolbar si Édition)
  └─ Corps :
       • Aperçu  → MarkdownText(markdown: text)        // moteur déjà utilisé (Résumé, Rapport)
       • Édition → MarkdownTextEditor(text)            // NSTextView brut existant
                     .markdownFeatures(features)
                     .markdownEditorID(editorID)       // la toolbar cible cet éditeur
```

- **État** : `@State private var mode` local, éphémère. Défaut = **Aperçu**, **sauf
  si la note est vide** → démarre en **Édition** (évite un écran blanc).
- **Aperçu vide** (note vide mais mode Aperçu forcé) : placeholder discret
  « Aucune note — passe en Édition pour écrire. »
- **Réutilisation maximale** : le mode Édition = l'éditeur `NSTextView` actuel
  (déjà brut, toolbar au curseur fonctionnelle). Le « revoir tout le code » se
  traduit par l'ajout du couple **toggle + Aperçu** autour, pas par la réécriture
  du NSTextView.

## Périmètre

- **Touché** : `MeetingView` (case `.liveNotes`) et `MeetingPrepTab` (Préparation)
  → remplacent leur `MarkdownToolbar` + `MarkdownEditorView` par `MarkdownNoteEditor`.
- **Inchangé** : entretiens, `PrepWindow`, édition du Rapport, `DetailsViews` —
  gardent l'éditeur actuel. Aucun risque de régression ailleurs.
- Le moteur de stylage live (`StyleRenderer`, `ShortcutDetector`) n'est **pas**
  supprimé (encore utilisé par les autres call-sites).

## Composants & responsabilités

- `MarkdownNoteEditor` (nouveau) : orchestre mode + toolbar + corps. Ne connaît
  ni SwiftData ni la réunion — juste un `Binding<String>` + `editorID` + `features`.
- `MarkdownText` (existant) : rendu lecture seule.
- `MarkdownTextEditor` + `MarkdownToolbar` (existants) : édition.

## Comportement / cas limites

- Bascule Édition→Aperçu : le binding est déjà à jour (debounce éditeur) → l'aperçu
  reflète le texte. Bascule Aperçu→Édition : idem.
- Note vidée puis re-vide : reste éditable (mode Édition conservé tant que la vue
  vit ; ré-ouverture applique la règle « vide → Édition »).
- `features` : `.prep` pour Préparation et Notes live (checkboxes, titres h2/h3).

## Tests / vérification

- Vérif manuelle in-app (mode itératif) : Notes live et Préparation affichent
  l'aperçu par défaut ; bascule vers Édition montre la toolbar ; la saisie
  markdown se rend correctement en Aperçu ; les tags/puces s'affichent.
- Pas de test unitaire dédié (composant purement visuel, sans logique métier).

## Hors périmètre (YAGNI)

- Suppression du moteur WYSIWYG / refonte des autres éditeurs.
- Persistance du mode Aperçu/Édition entre sessions.
- Split view édition+aperçu simultanés.
