# Design — Tags/thèmes de réunions + auto-tagging IA

Date : 2026-07-27 · Branche : `feat/Actions-enhanced`

## Objectif

Permettre de **tagger les réunions par thème** pour les regrouper, indépendamment
du projet, du type (`MeetingKind`) et des participants. Tags **libres, multiples,
riches** (couleur + gestion centralisée), avec **suggestion IA** des thèmes à
partir du compte-rendu.

État actuel : aucun concept de tag/thème. Le regroupement se fait seulement par
Projet, Type et Collaborateur (chips de filtre dans `MeetingsListView`).

## Modèle de données

Nouveau `@Model MeetingTag` (dans `OneToOne/Models/`), conventions de l'app :

```swift
@Model final class MeetingTag {
    var stableID: UUID? = nil          // backfill via ensuredStableID
    var name: String = ""
    var colorHex: String = ""          // via Color(hex:)/toHex() (ColorHex.swift)
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Meeting.tags)
    var meetings: [Meeting] = []

    init(name: String, colorHex: String) { … stableID = UUID() … }
    var ensuredStableID: UUID { … }    // pattern Project/Collaborator/Meeting
}
```

Côté `Meeting` (dans `OtherModels.swift`) :

```swift
@Relationship(deleteRule: .nullify) var tags: [MeetingTag] = []
```

- Relation **many-to-many**, `.nullify` des deux côtés : supprimer un tag le retire
  des réunions (jamais l'inverse) ; supprimer une réunion la retire des tags.
- **Unicité du `name`** (insensible casse/accents) garantie **applicativement**
  (find-or-create), pas de contrainte SwiftData.
- `stableID` en `UUID?` optionnel volontairement (cf. [[swiftdata_optional_uuid_caveat]] :
  un `UUID` non-optionnel avec valeur par défaut casse la migration SwiftData).

## Migration

Ajouter `MeetingTag.self` à `SchemaV1.models` (`CurrentSchema.models`). Ajout
**additif** : nouveau type + relation to-many défaut vide → **lightweight
migration** automatique. Pas de `SchemaV2` ni `MigrationStage`.

## UI

### 1. Édition sur la réunion (`MeetingTopChromeBar`)

- Rangée de **chips colorées** (fond = `colorHex` désaturé, texte = `name`),
  placée près du badge Type dans le breadcrumb ; passe à la ligne si nécessaire.
- Bouton `+` → **popover** :
  - champ de recherche filtrant les tags existants (non archivés) ;
  - liste des tags correspondants (clic = lier à la réunion) ;
  - si le texte ne matche aucun tag : action **« Créer “<texte>” »** (nom + sélecteur
    de couleur, couleur pré-remplie depuis la palette déterministe).
- Chaque chip liée : clic sur ✕ = délier (retire de `meeting.tags`, save).

### 2. Liste des réunions (`MeetingsListView`)

- Nouvelle chip de filtre **« Thème »** (menu, calqué sur les filtres Type/Projet/
  Collaborateur existants) → `@State filterTag: MeetingTag?`. Ajoutée à
  `filteredMeetings`.
- Toggle **« Grouper par thème »** : quand actif, la liste est sectionnée par tag
  (une section par tag, une section « Sans thème »). Une réunion multi-tags
  apparaît dans chaque section correspondante.

### 3. Gestion (Réglages, calqué sur `ReportTemplateListView`)

`TagManagementView` : liste CRUD des tags —
- renommer, recolorer, archiver / supprimer ;
- **fusionner** deux tags (réaffecte les réunions du tag source vers le tag cible,
  puis supprime le source) ;
- compteur de réunions par tag.

## Auto-tagging IA

### Service — `MeetingTagSuggester`

Calqué sur `ManagerCategoryClassifier` (non-throwing, `AIClientProtocol`
injectable, timeout, matching insensible casse/accents).

```swift
enum MeetingTagSuggester {
    static let timeout: TimeInterval = 5
    static func suggest(
        summary: String,
        existingTags: [String],
        settings: AppSettings,
        client: AIClientProtocol = AIClient.live
    ) async -> [String]        // [] sur erreur/timeout/vide
}
```

- **Entrée** : `meeting.summary` si non vide, sinon `mergedTranscript` tronqué
  aux ~4000 premiers caractères (assez pour cerner les thèmes sans exploser le prompt).
- **Prompt** : demande 3–5 thèmes **courts**, en réutilisant les tags existants
  fournis quand ils sont pertinents ; réponse = liste (séparée par virgules/retours).
- **Sortie** : labels parsés → match contre `existingTags` (réutilisation) ; les
  non-matchés sont des **nouveaux** thèmes proposés.

### Déclenchement

- **Auto** : à la fin de `generateReport()` (succès), lancé en tâche de fond,
  **non bloquant** pour l'UI. Rejoué **à chaque** génération de rapport.
- **Manuel** : bouton **« ✨ Suggérer des thèmes »** dans le popover de tags.

### Application (suggest → confirm, non destructif)

- Les propositions s'affichent en **chips « fantômes »** (contour pointillé) sur la
  rangée de tags de la réunion.
- Clic sur un chip fantôme = **accepter** → find-or-create `MeetingTag`
  (couleur auto déterministe depuis la palette pour un nouveau) + lien à la
  réunion + save.
- Croix sur un chip fantôme = **ignorer**.
- Les propositions sont **éphémères** : stockées en `@State` dans `MeetingView`
  (`suggestedTagNames: [String]`), **non persistées**, régénérables via le bouton.
  Un label déjà présent dans `meeting.tags` n'est pas re-proposé.

### Palette couleurs (nouveaux tags)

Petite palette fixe (~8–10 teintes) ; choix **déterministe** par hash stable du
`name` → couleur reproductible sans demander à l'utilisateur (modifiable ensuite
via la gestion).

## Découpage des unités

- `MeetingTag.swift` — modèle + `ensuredStableID` + helper couleur.
- `TagColorPalette.swift` — palette + sélection déterministe par nom.
- `MeetingTagSuggester.swift` — service IA (pur, testable, client injectable).
- `MeetingTagEditor` (vue) — chips + popover ajouter/créer + chips fantômes.
- `TagManagementView.swift` — CRUD + fusion (Réglages).
- Modifs ciblées : `Meeting` (relation `tags`), `SchemaV1.models`,
  `MeetingsListView` (filtre + groupement), `MeetingView`/`generateReport()`
  (déclenchement auto + `@State` suggestions).

## Hors scope

- Filtre **multi-tags** (AND/OR) — un seul tag filtré pour commencer.
- Persistance des suggestions IA entre redémarrages.
- Auto-application silencieuse des tags IA (on reste sur confirmation utilisateur).

## Tests

- `MeetingTagSuggester` : parsing de réponse (virgules/retours/puces), matching
  casse/accents vs tags existants, réponse vide / hors-sujet → `[]` (client mocké
  via `AIClientProtocol`, comme les tests existants de classification).
- `TagColorPalette` : déterminisme (même nom → même couleur) et bornes.
- Fusion de tags : réaffectation correcte des réunions + suppression du source
  (test au niveau modèle en `ModelContext` in-memory).
- Find-or-create : pas de doublon sur `name` insensible casse/accents.
