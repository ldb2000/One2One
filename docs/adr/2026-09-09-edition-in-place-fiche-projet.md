# L'écran projet s'édite champ par champ, au clic, avec annulation

**Statut :** acceptée le 2026-09-09 (décision **D9** de la refonte de la gestion des projets)
**Portée :** `EditableInPlace`, `EditableTextField`, `EditableTextEditor`, `ProjectCardDraft`,
`ProjectCardPanel`, `ProjectScreen`, `ScopeCard`, `RiskCard`, `InterlocutorsCard`,
`ProjectDocumentsTab`, `Project.scopeUpdatedAt`
**Références :** `docs/superpowers/specs/2026-09-09-gestion-projets-design.md` §2 (constats 13
et 14), §3 (D9) · `docs/superpowers/specs/gestion-projets-2026-09/handoff/README.md` §1d
(« Édition ») et §Interactions · `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`

## Contexte

L'écran projet de la capture `1d-ecran-projet-pilotage.png` se lit d'abord : un périmètre, un
risque, trois interlocuteurs, cinq lignes d'identité. Le handoff demande qu'il s'**édite au
clic sur la valeur**, `⏎` pour valider, `esc` pour annuler, et un bandeau d'annulation de cinq
secondes après enregistrement. Le dépôt avait déjà deux façons d'éditer une fiche projet, et
aucune des deux ne convenait telle quelle.

**`ProjectDetailView` lie ses champs directement à `@Bindable project`.** Chaque frappe écrit
dans le store. Il n'y a rien à annuler, rien à confirmer, et le bouton « Enregistrer » de sa
barre d'outils ne fait que forcer un `save()` déjà fait. C'est le formulaire à plat que la
refonte range dans un onglet, pas le mécanisme qu'elle généralise.

**`ProjectCardPanel` a le bon mécanisme et la mauvaise granularité.** Son `ProjectCardDraft` est
une `struct` détachée du modèle : rien n'est écrit avant `apply(to:in:)`, et l'instantané
d'avant enregistrement alimente `UndoBanner` cinq secondes. C'est exactement le contrat voulu.
Mais l'édition y est une **bascule globale** — un bouton « Édition » fait passer tout le panneau
en saisie —, le brouillon ne couvre que sept champs (statut, budgets, périmètre, thèmes, jalons,
interlocuteurs, risques), et le panneau **exige un `Meeting`** : il est né dans une réunion.

Trois contraintes techniques pesaient en plus :

- **`EditableTextField` et `EditableTextEditor` sont des `NSViewRepresentable`** (constat §2.14).
  Ils ignorent le `.font()` de l'environnement SwiftUI : une fonte Plex posée par-dessus n'a
  aucun effet, et c'est ce qui a fait sortir le titre de réunion en fonte système pendant quatre
  lots de la refonte précédente.
- **Ni l'un ni l'autre ne rapportait `⏎` ou `esc`.** `NSTextField` les laisse remonter la chaîne
  de responders, ce dont `ProjectCardPanel` **dépend** : son `.onExitCommand` ferme le panneau,
  et vingt-cinq autres usages du champ comptent sur ce comportement.
- **`ProjectCardStatus` replie « Unknown » sur « À surveiller ».** Le brouillon portait le
  statut sous cette forme à trois valeurs ; enregistrer réécrivait donc « Yellow » sur un projet
  dont personne n'avait touché le statut. Soixante-deux projets du store réel sont dans ce cas.

## Décision

**Un modificateur `EditableInPlace`, le brouillon existant étendu, et l'annulation par
instantané — le tout sans bascule d'édition.**

1. **`Views/DesignSystem/EditableInPlace.swift`** enveloppe un rendu de lecture quelconque. Clic
   sur la valeur → champ actif, prérempli. `⏎` (une ligne) ou `⌘⏎` (un paragraphe) valide ;
   `esc` referme le champ **et rien d'autre**. Une saisie identique à la valeur lue n'écrit pas
   et n'ouvre pas de bandeau : un `⏎` sur un champ intact ne doit rien proposer d'annuler
   (`doitValider(saisie:valeur:)`, testée).
2. **`EditableTextField` et `EditableTextEditor` gagnent `onSubmit` / `onCancel`**, `nil` par
   défaut. Le coordinateur ne consomme la touche que si le rappel existe : le comportement
   historique — et le `.onExitCommand` de `ProjectCardPanel` — est intact, ce qu'un test fige.
   `EditableTextEditor` gagne aussi une fonte et un fond transparent.
3. **`ProjectCardDraft` couvre les champs de l'écran projet** : nom, sponsor, phase, type,
   niveau et description de risque, jours prévus, fin de design, entité, chef de projet et
   architecte. Les trois derniers sont des `PersistentIdentifier` — `Entity` n'a pas de
   `stableID` — résolus **par requête** à l'écriture, jamais par `ModelContext.model(for:)`, qui
   rend un objet faulté quand l'identité vient d'un autre conteneur.
4. **Le statut passe en `statusRaw`**, source de vérité ; `status` n'en est plus qu'une vue à
   trois valeurs. Un projet « Unknown » traverse désormais un enregistrement sans changer
   d'étiquette.
5. **`ProjectScreen.editer(_:)` est le seul point d'écriture** : instantané, transformation,
   `apply`, bandeau. `UndoBanner` réapplique l'instantané tel quel — d'où
   `stampScopeIfChanged(from:)`, qui horodate le périmètre dans le **brouillon** et non dans
   `apply` : sinon l'annulation redaterait le texte qu'elle vient de restaurer.
6. **`ProjectCardPanel.meeting` devient optionnel.** Sans réunion, l'assistant n'est pas
   sollicité et la feuille de propositions ne s'ouvre pas ; tout le reste du panneau fonctionne.
7. **`Project.scopeUpdatedAt: Date?`** date la dernière édition du périmètre — le pied
   « dernière mise à jour hier » de la capture. Champ optionnel : migration légère, pas de
   `SchemaV4` (constat §2.23).

## Conséquences

**Ce qu'on gagne.** Un seul contrat d'édition sur tout l'écran projet, et il est structurel :
tant que personne n'appelle `apply`, `Project` ne bouge pas. Chaque champ édité a son bandeau
d'annulation, y compris ceux — l'affectation d'un chef de projet, le niveau de risque — qui
n'étaient éditables que dans un formulaire sans retour arrière. La vue « À risque » du lot 5 en
hérite : « Compléter » n'aura qu'à appeler `editer`.

**Ce qu'on paie.**

- **`⌘⏎` et non `⏎` pour un paragraphe.** Le handoff écrit `⏎` sans distinguer ; un périmètre
  de trois phrases doit pouvoir contenir des retours à la ligne. Le champ actif l'annonce
  (« ⌘⏎ pour valider · esc pour annuler ») ; c'est un écart au handoff, assumé.
- **Un modificateur générique de plus** dans `Views/DesignSystem/`, à côté de `UndoBanner`. Il
  n'a qu'un seul écran pour appelant aujourd'hui.
- **`ProjectCardDraft` grossit** : quinze champs plus trois collections. Il reste `Equatable`,
  donc « y a-t-il quelque chose à enregistrer ? » se répond toujours par `==`.
- **La résolution par requête** parcourt les entités et les collaborateurs à chaque
  enregistrement. Quelques dizaines de lignes ; à revoir si le store en compte des milliers.

## Alternatives écartées

1. **Étendre la bascule `isEditing` de `ProjectCardPanel` à l'écran projet.** C'est le
   mécanisme déjà écrit, et il a déjà son bandeau. Mais la capture 1d ne montre **aucun** bouton
   « Édition », et faire basculer un écran entier pour changer un niveau de risque, c'est le
   formulaire à plat sous un autre nom.
2. **Lier les champs à `@Bindable project`, comme `ProjectDetailView`.** Zéro ligne de
   mécanisme. Mais alors « annuler » n'existe plus, et le critère du chantier précédent
   — « aucune modification de la fiche projet n'est écrite sans validation humaine explicite » —
   tombe sur le nouvel écran après avoir été tenu sur l'ancien.
3. **Une feuille modale par champ.** Un clic ouvre un dialogue, on valide, on ferme. Sans
   ambiguïté sur `⏎`, et sans toucher aux deux `NSViewRepresentable`. Mais trois clics pour
   corriger un mot, et la lecture est masquée pendant l'édition : c'est l'inverse de « lecture
   d'abord ».
4. **Un `TextField` SwiftUI plutôt que `EditableTextField`.** `onSubmit` existe déjà dessus.
   Écarté par le constat qui a fait naître `EditableTextField` : un `TextField` natif ne reçoit
   pas fiablement les événements clavier dans la colonne de détail d'un `NavigationSplitView`,
   et c'est exactement là que vit l'écran projet.
