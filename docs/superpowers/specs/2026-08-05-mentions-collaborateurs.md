# Mentions de collaborateurs avec `@`

Date : 2026-08-05
Branche : `feat/editeur-slash-blocs`

## Objectif

Taper `@` dans une note ouvre une liste déroulante des collaborateurs connus.
Les lettres suivantes filtrent par nom. La sélection insère une mention.
Si le nom tapé ne correspond à personne, une entrée permet de **créer** le
collaborateur et de le mentionner dans la foulée.

## Ce qui existe et se réutilise tel quel

L'infrastructure du menu `/`, livrée sur cette branche, résout déjà le même
problème : détecter un caractère déclencheur, afficher un panneau flottant
non-activant sous le curseur, filtrer à la frappe sans perdre le focus,
naviguer au clavier, insérer.

| Brique | Rôle | Réutilisation |
|---|---|---|
| `Slash/SlashPanel.swift` | `NSPanel` non-activant, positionnement, liste | telle quelle, ou généralisée |
| `Slash/SlashPanelPositioning` | placement sous le curseur, clamp écran | telle quelle |
| `Slash/SlashController.swift` | détection, clavier, insertion, annulation du debounce | **patron à suivre** |
| `Core/EditorRepresentable.swift` | `doCommandBy`, `textDidChange`, `teardown` | points d'accroche déjà en place |

Le modèle `Collaborator` (`Models/OtherModels.swift:31`) porte `name`, `role`,
`email`, `isArchived`, `photoPath`, `pinLevel`.

`Services/CollaboratorMatcher.swift` existe — **vérifier s'il fait déjà de la
recherche par nom** avant d'en écrire une.

## Décisions de conception

### Représentation dans le markdown

Une mention est un **lien markdown** :

```
[@Marie Dupont](onetoone://collaborator/<stableID>)
```

Trois raisons :

1. **L'aller-retour est déjà acquis.** Les liens sont parsés et resérialisés
   par le module depuis l'origine, avec `mdLink` porté par les runs.
   L'échappement de `[`, `]`, `(`, `)` est structurel, pas littéral — vérifié
   par les fixtures existantes.
2. **C'est du markdown standard.** Un export, un rapport, une copie vers un
   autre outil restent lisibles. Le texte visible reste `@Marie Dupont`.
3. **Le lien est résolvable.** Cliquer dessus pourra ouvrir la fiche du
   collaborateur, et un service pourra retrouver toutes les notes mentionnant
   quelqu'un.

Le schéma d'URL `onetoone://collaborator/<uuid>` est à confirmer contre ce que
le projet utilise déjà — **vérifier** s'il existe un schéma enregistré.

**Écarté** : un caractère marqueur `U+FFFC` porteur d'attributs, comme les
images. Il faudrait inventer une syntaxe de sérialisation, et cette branche a
corrigé quatre bugs distincts causés par ce mécanisme. Le lien ne coûte rien
de nouveau.

**Écarté aussi** : du texte nu `@Marie`. Aucun lien vers le modèle, donc pas de
résolution, et un homonyme casse tout.

### Résilience au renommage

Le `stableID` est la vérité, le nom affiché n'est qu'un libellé. Si un
collaborateur est renommé, les mentions existantes gardent l'ancien nom
jusqu'à réécriture — comportement acceptable et sans perte, à documenter.

**Ne pas** tenter de réécrire les notes à la volée lors d'un renommage : ce
serait une modification de masse silencieuse des données de l'utilisateur.

### Création d'un collaborateur inconnu

Quand la recherche ne renvoie rien, une entrée en fin de liste propose
**« Créer "Nom tapé" »**. La valider crée le `Collaborator` et insère la
mention.

Le module `OneToOne/Markdown/` ne connaît **pas** SwiftData et ne doit pas le
connaître. La création passe donc par une **closure injectée**, sur le modèle
du sélecteur d'image (`SlashController.presentImageOpenPanel`) :

```swift
// fournie par EditorRepresentable depuis la couche vue
var createCollaborator: ((String) -> MentionCandidate?)?
var searchCollaborators: ((String) -> [MentionCandidate])
```

`MentionCandidate` est une structure plate du module — identifiant, nom, rôle —
sans dépendance au modèle SwiftData. La couche vue fait la conversion.

**Point à trancher à l'implémentation** : créer un collaborateur est une action
qui modifie durablement les données. Faut-il une confirmation, ou la validation
explicite de l'entrée « Créer … » suffit-elle ? Je penche pour la seconde —
l'entrée est distincte des autres et nommée sans ambiguïté — mais c'est à
mesurer à l'usage.

### Déclenchement

`@` en début de ligne ou précédé d'une espace, comme le `/`. Un `@` en milieu
de mot ne déclenche rien, pour ne pas gêner la saisie d'une adresse courriel.

**À vérifier à l'implémentation** : le comportement quand on tape une adresse
courriel complète après une espace (`écrire à @marie` est une mention, mais
`contact@exemple.fr` ne doit pas déclencher — le `@` y est en milieu de mot,
donc la règle tient, mais il faut le tester).

### Recherche

Insensible à la casse **et aux accents** — `SlashCatalog` a déjà la fonction de
repli, la réutiliser. Recherche sur le nom ; à évaluer, aussi sur le rôle et
le courriel.

Les collaborateurs archivés (`isArchived`) sont exclus par défaut.

Tri : les épinglés d'abord (`pinLevel`), puis alphabétique. **À confirmer** —
un tri par fréquence de mention serait plus utile mais demande de compter.

## Pièges connus de ce code

Tous mesurés sur cette branche, tous applicables ici :

1. **`insertText` fusionne les `typingAttributes`.** Une mention insérée après
   du code inline hériterait `.mdInlineCode`. `SlashController` a la parade
   (`stripRiskyTypingAttributes`) — l'appliquer.
2. **La requête transite vers SwiftData.** Le texte `@mar` passe par
   `serialize` → binding, débouncé à 0,3 s. Annuler la tâche de debounce tant
   que le panneau est ouvert, comme le fait `SlashController`.
3. **Effacer la requête** doit passer par `insertText("", replacementRange:)` —
   une mutation directe du `textStorage` ne déclenche ni le délégué, ni
   l'annulation.
4. **Ne pas passer par `MarkdownEditorRegistry`** — singleton non isolé, clés
   fournies par l'appelant. Le contrôleur reçoit son éditeur à l'init.

## Tests attendus

Logique pure, testable sans interface :

- déclenchement selon le contexte (début de ligne, après espace, milieu de mot,
  adresse courriel) ;
- filtrage par nom, insensible casse et accents ;
- exclusion des archivés, ordre de tri ;
- l'entrée « Créer … » n'apparaît que sans correspondance exacte ;
- la mention insérée fait l'aller-retour markdown sans échappement parasite ;
- la mention n'hérite pas des attributs de frappe (après code inline, après gras) ;
- la closure de création est appelée avec le nom tapé, et son refus (`nil`)
  n'insère rien.

Le panneau lui-même n'est pas testable dans ce projet — le dire, ne pas
inventer de couverture.

**Vérification par mutation obligatoire**, comme pour le reste de la branche :
neutraliser chaque partie et confirmer qu'un test échoue.

## Découpage proposé

| # | Contenu |
|---|---|
| 1 | `MentionCandidate`, recherche et filtrage — logique pure |
| 2 | Généralisation du panneau, ou second panneau sur le même modèle |
| 3 | `MentionController` — détection, clavier, insertion |
| 4 | Branchement, closures de recherche et de création côté vue |
| 5 | Rendu visuel de la mention dans l'éditeur (couleur, pastille) |

L'étape 5 est du confort : une mention s'affichera d'abord comme un lien
ordinaire, ce qui est déjà correct.

## Hors périmètre

- Notifier la personne mentionnée.
- Retrouver toutes les notes mentionnant quelqu'un (le lien le permettra, mais
  c'est une fonctionnalité à part).
- Mentionner un projet ou une réunion — même mécanisme, autre chantier.
- Réécriture des mentions au renommage d'un collaborateur.
