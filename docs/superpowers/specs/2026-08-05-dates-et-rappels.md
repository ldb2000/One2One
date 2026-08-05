# Dates interactives et rappels

Date : 2026-08-05
Branche : `feat/editeur-slash-blocs`

> ## ⚠️ Annotation du 2026-08-06 — le découpage a été exécuté **à l'envers**
>
> Vérifié par lecture du code (`SlashController.insertDate`,
> `SlashDatePickerPresenter`, `DateReminder`, commit `e2ed854`) :
>
> | Étape de la spec | État réel |
> |---|---|
> | 1 — format de lien + parsing + aller-retour | **non faite** |
> | 2 — rendu distinct (fond, couleur) | **non faite** |
> | 3 — icône dessinée | non faite |
> | 4 — popover : calendrier, heure | **faite** (`NSPopover` + SwiftUI : champ texte éditable, `DatePicker` graphique, bascule « Inclure l'heure », éditeur d'heure) |
> | 5 — rappel affiché dans le popover, non déclenché | **faite** (`DateReminder`, 5 choix, menu « Rappel ») |
> | 6 — rappels planifiés | non faite |
>
> Les étapes 4 et 5 ont été livrées **avant** les étapes 1 et 2, ce que la spec
> présentait pourtant comme un ordre de dépendance. Conséquence mesurable :
> `SlashController.insertDate` insère toujours du **texte brut**
> (`"5 août 2026"`, `"6 août 2026 13:08"`) et **jette `selection.reminder`** — son
> propre doc-comment le dit. Le popover fait donc choisir à l'utilisateur un rappel
> qui n'est ni écrit, ni stocké, ni déclenché : il disparaît à la validation.
>
> C'est exactement l'avertissement que ce document formulait — « un rappel qui ne se
> déclenche pas est pire qu'un rappel absent » — sauf que le cas réel est pire encore,
> puisque le rappel n'est même pas conservé.
>
> **Deux issues, à trancher** : (a) exécuter l'étape 1 (le lien
> `onetoone://date/…?reminder=P1D`) pour que la donnée survive ; (b) retirer le menu
> « Rappel » du popover tant que (a) n'est pas fait, pour ne pas mentir à
> l'utilisateur. Le reste de ce document reste valide tel quel.

## Point de départ

`/date` existe et insère du **texte brut** (`5 août 2026`) via une `NSAlert`
portant un `NSDatePicker`. Ça marche, mais l'utilisateur veut le comportement
d'AppFlowy :

- une **pastille inline** cliquable, `@5 août 2026 📅`, et non du texte figé ;
- un **calendrier en popover** attaché à la pastille, pas une alerte modale ;
- une **heure optionnelle** (`@6 août 2026 13:08 ⏱`) ;
- un **rappel** : aucun, le jour même à 9h, la veille, deux jours avant, une
  semaine avant.

## Trois chantiers de coûts très différents

| # | Contenu | Coût | Dépendances |
|---|---|---|---|
| 1 | Représentation structurée + rendu distinct | modeste | aucune |
| 2 | Popover d'édition (calendrier, heure, rappel) | moyen | chantier 1 |
| 3 | Rappels réellement déclenchés | **élevé** | modèle de données |

Le chantier 3 est celui qui change de nature : une note est une `String`. Un
rappel qui doit sonner ne peut pas vivre uniquement dans du texte.

## Chantier 1 — représentation et rendu

### Format retenu

Un **lien markdown**, comme pour les mentions (`2026-08-05-mentions-collaborateurs.md`) :

```
[@5 août 2026](onetoone://date/2026-08-05)
[@6 août 2026 13:08](onetoone://date/2026-08-06T13:08)
[@5 août 2026](onetoone://date/2026-08-05?reminder=P1D)
```

Les mêmes trois raisons que pour les mentions : l'aller-retour des liens est
déjà acquis et testé ; le markdown reste standard et exportable ; les données
structurées (date ISO, heure, rappel) tiennent dans l'URL sans inventer de
syntaxe.

Le libellé visible est en français long, le contenu de l'URL en ISO 8601 —
lisible par une machine, stable au changement de locale.

**Écarté** : du texte brut, qui perd la donnée dès qu'on veut la relire ; et un
caractère marqueur porteur d'attributs, qui a causé quatre bugs distincts sur
cette branche.

### Rendu

La pastille d'AppFlowy a un fond, un liseré et une icône. En TextKit 1, dans ce
module :

- **fond et couleur** : attributs sur le run du lien, sans rien ajouter au
  storage — direct ;
- **icône** : ne doit **pas** entrer dans le storage, sinon elle fuit dans le
  markdown enregistré. À dessiner par `MarkdownLayoutManager`, comme les
  marqueurs de liste et le filet de citation. **À mesurer d'abord** : ces
  décorations sont dans la marge ; une icône inline en fin de run est un cas
  différent, et rien ne garantit qu'elle se place proprement.

**Repli acceptable si l'icône inline résiste** : fond coloré et couleur
distincte, sans icône. La pastille reste identifiable et cliquable.

### Distinguer date et mention

Les deux sont des liens. `StyleRenderer` doit les styliser différemment, en
lisant le schéma de l'URL (`onetoone://date/` contre
`onetoone://collaborator/`). Prévoir cette distinction dès le début, sinon les
deux fonctionnalités se marcheront dessus.

## Chantier 2 — popover d'édition

Clic sur la pastille → `NSPopover` ancré sur le rectangle du run, contenant :

- un calendrier (`NSDatePicker` en `.clockAndCalendar`, ou une vue SwiftUI) ;
- une bascule **« Inclure l'heure »** ;
- un menu **« Rappel »** : aucun / le jour même à 9h / la veille / 2 jours
  avant / 1 semaine avant.

Valider réécrit le lien en place. Le popover remplace l'`NSAlert` actuelle,
qui reste le repli pour l'insertion initiale si l'ancrage pose problème.

**Point technique à mesurer** : obtenir le rectangle écran d'un run inline pour
y ancrer le popover. `firstRect(forCharacterRange:actualRange:)` le fait pour
le curseur — vérifié sur cette pile — mais pour une plage de plusieurs
caractères, à confirmer.

**Attention** : le popover ne doit pas voler le focus au texte, même piège que
le panneau du menu `/`. `SlashPanel` a la parade (`canBecomeKey = false`,
`.nonactivatingPanel`) ; s'en inspirer.

## Chantier 3 — rappels réellement déclenchés

C'est ici que ça cesse d'être une affaire d'éditeur.

Un rappel écrit dans une note doit **sonner**. Or une note est une `String`
dans SwiftData : rien ne la surveille, rien ne planifie. Trois questions à
trancher avant d'écrire une ligne :

1. **Où vit le rappel ?** Uniquement dans le texte, avec un balayage des notes
   au démarrage et à chaque sauvegarde ? Ou dans un modèle SwiftData dédié,
   synchronisé avec le texte ? Le second est plus fiable et plus coûteux ; le
   premier risque de désynchroniser texte et notifications.
2. **Que se passe-t-il si la mention est supprimée du texte ?** Le rappel doit
   disparaître. Un modèle séparé demande une réconciliation ; un balayage la
   fait naturellement.
3. **Quelle infrastructure existe déjà ?** Le projet a
   `Services/MeetingNotificationService.swift` — **à lire avant de concevoir**.
   S'il sait déjà planifier des notifications locales, le chantier se réduit
   beaucoup.

**Recommandation** : ne pas s'engager sur le chantier 3 avant d'avoir répondu à
ces trois questions par la lecture du code existant. Les chantiers 1 et 2
livrent déjà une date interactive et éditable ; le rappel peut n'être qu'une
donnée affichée, non déclenchée, dans un premier temps — à condition de le
**dire** dans l'interface plutôt que de laisser croire qu'il sonnera.

Un rappel qui ne se déclenche pas est pire qu'un rappel absent.

## Pièges connus de ce code

Tous mesurés sur cette branche :

1. **`insertText` fusionne les `typingAttributes`** — une pastille insérée après
   du code inline hériterait `.mdInlineCode`. `SlashController.stripRiskyTypingAttributes`
   est la parade.
2. **Rien de visuel ne doit entrer dans le storage.** Quatre bugs distincts en
   sont venus. L'icône se dessine, elle ne s'insère pas.
3. **Les tests pixel dépendent de l'apparence système.** `NSColor.labelColor`
   devient blanc en mode sombre ; un test qui peint sur fond blanc mesure zéro.
   Envelopper dans `NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance`.
4. **Le mécanisme natif n'est pas garanti.** `NSTextList` ne peint rien en
   TextKit 1 — mesuré. Vérifier avant de concevoir sur une API AppKit.

## Découpage proposé

| # | Étape | Livrable |
|---|---|---|
| 1 | Format de lien + parsing + aller-retour | une date insérée survit à l'enregistrement, avec sa donnée structurée |
| 2 | Rendu distinct (fond, couleur), sans icône | la date se voit comme un élément, pas comme du texte |
| 3 | Icône dessinée, si la mesure le permet | confort |
| 4 | Popover : calendrier, heure | la date s'édite en place |
| 5 | Rappel affiché dans le popover, non déclenché | la donnée est saisie et conservée |
| 6 | Rappels réellement planifiés | après réponse aux trois questions ci-dessus |

Les étapes 1 et 2 remplacent déjà l'insertion en texte brut actuelle par
quelque chose de relisable et d'éditable plus tard.

## Hors périmètre

- Récurrence des rappels.
- Fuseaux horaires — tout est en heure locale.
- Retrouver toutes les notes contenant une date à venir (le lien le permettra,
  c'est une fonctionnalité à part).
- Synchronisation avec le calendrier système.
