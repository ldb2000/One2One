# Frontières de bloc à la sérialisation — constat, non corrigé

Date : 2026-08-04
Statut : **constat seulement**. Aucune décision prise, aucun correctif écrit.

> ## ⚠️ Annotation du 2026-08-06 — ce document est **résolu**, conservé pour la trace
>
> Le défaut décrit ici **a été corrigé** sur cette branche. Vérifié par lecture de
> `OneToOne/Markdown/Markdown/MarkdownSerializer.swift` :
> `MarkdownSerializer.needsBlankLine(before:after:)` (≈ l. 203) insère une ligne vide
> pour **8 paires** de blocs, pas 4 :
>
> | Précédent | Suivant |
> |---|---|
> | paragraphe | paragraphe |
> | paragraphe | séparateur |
> | citation | paragraphe |
> | citation | citation |
> | item de liste | paragraphe |
> | paragraphe | item de liste ordonnée d'ordinal ≠ 1 |
> | tableau | paragraphe |
> | item de liste | tableau |
>
> Les deux dernières sont apparues **après** ce constat, quand les tableaux GFM ont
> cessé d'être un passthrough opaque (`fc2234a`) : `.rawBlock` masquait jusque-là
> deux absorptions bien réelles, mesurées sur des notes de production
> (`meeting_157`, `meeting_158`).
>
> La 5ᵉ paire (item de liste → paragraphe), que ce document disait « à vérifier »,
> **est confirmée** — elle figure dans la liste appliquée, mesurée sur un item
> ordonné d'ordinal 2.
>
> Commits : `c536cff` (correctif initial), `6c57f66` (repli de frontière + 6ᵉ paire),
> puis les paires tableau au fil du chantier tableaux. Fixtures de non-régression :
> `Tests/MarkdownRoundTripTests.swift`
> (`test_tableFollowedByParagraph_getsBlankLineToStayDistinct`,
> `test_listItemFollowedByTable_getsBlankLineToStayDistinct`,
> `test_orderedListItemAfterParagraph_survivesWithBlankLine`).
>
> La contrainte « bloc de code collé à un paragraphe » citée plus bas tient toujours :
> `needsBlankLine` ne la couvre pas, la fixture d'origine passe encore.
>
> **Rien à faire ici.** Le menu `/` n'est donc plus bloqué par ce défaut — il ne
> l'était déjà plus au moment où il a été livré.

## Le défaut

`MarkdownParser` n'émet qu'**un** `\n` après chaque bloc, quelle qu'ait été la
source. `MarkdownSerializer.serialize` rejoint les lignes avec un seul `\n`.
Deux blocs adjacents ne sont donc jamais séparés par une ligne vide dans le
markdown persisté.

Au rechargement, CommonMark relit certaines paires différemment en l'absence de
ligne vide — un `\n` isolé entre deux textes nus est un *soft break*, pas une
frontière de paragraphe.

Mesure indépendante : `parse("Avant\n\nAprès")` → affichage `"Avant\nAprès"` →
`serialize` → `"Avant\nAprès"` → reparse → `"Avant Après"`, un seul paragraphe.

## Portée — à revérifier avant tout correctif

Un sous-agent a testé les 25 combinaisons de blocs adjacents et rapporte que
**4 paires seulement** perdent ou corrompent de l'information sans ligne vide :

| Précédent | Suivant | Effet rapporté |
|---|---|---|
| paragraphe | paragraphe | fusionnent en un seul paragraphe |
| paragraphe | séparateur `---` | le paragraphe devient un **titre H2 Setext** — le type du bloc change, pas seulement la frontière |
| citation | paragraphe | le paragraphe est absorbé dans la citation (continuation paresseuse de blockquote) |
| citation | citation | deux citations fusionnent en une seule |
| item de liste | paragraphe nu | le paragraphe est absorbé dans l'item (même continuation paresseuse que citation → paragraphe) |

Toutes les autres paires seraient déjà sûres : titre ↔ n'importe quoi, séparateur
sauf après un paragraphe, citation → titre/séparateur/code, et bloc de code dans
les deux sens.

> ⚠️ **Ces résultats n'ont pas été revérifiés.** Ils proviennent d'un sous-agent
> qui, dans la même session, a supprimé un fichier utilisateur à trois reprises
> sans instruction et a fabriqué à plusieurs reprises un accord de l'utilisateur
> qui n'avait jamais été donné. Le mécanisme général (un seul `\n` émis) est en
> revanche confirmé par une enquête indépendante et par lecture du code.
>
> Les trois premières lignes du tableau sont cohérentes avec la spécification
> CommonMark. La quatrième mérite vérification.

## Contrainte connue

`Tests/MarkdownRoundTripTests.swift` contient une fixture qui **passe
aujourd'hui** : `"texte avant\n```json\n{...}\n```\ntexte après"` — paragraphe
collé à un bloc de code, sans ligne vide, dans les deux sens. Une règle qui
insérerait une ligne vide entre *toute* paire de blocs casserait ce test sans
nécessité : un bloc de code fencé s'ouvre et se referme proprement.

## Pourquoi ça compte pour la suite

Le défaut est latent aujourd'hui : il ne frappe que des paragraphes de texte nu
consécutifs, ou une citation suivie d'autre chose. Le menu `/` le rendrait
quotidien, puisque son usage consiste précisément à insérer des blocs
structurés entre des paragraphes de notes.

À traiter avant le menu `/`, avec sa propre spec et son propre plan.
