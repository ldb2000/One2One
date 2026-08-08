# Mesures TextKit

Programmes autonomes qui **mesurent** un comportement de TextKit 1 au lieu de le
supposer. Ils se lancent seuls, hors du paquet :

```bash
swift docs/mesures/mesure-textkit.swift
```

Ils ont été écrits pendant le chantier d'aération des blocs de l'éditeur
(2026-08-08), où trois affirmations plausibles se sont révélées fausses. Les
garder permet de rejouer la mesure plutôt que de refaire le raisonnement.

| Script | Ce qu'il établit |
|---|---|
| `mesure-textkit.swift` | `lineFragmentRect` **inclut** `paragraphSpacingBefore` et `paragraphSpacing` ; seul `lineFragmentUsedRect` commence au sommet du texte. Ancrer une géométrie sur le rect de fragment la peint au-dessus du bloc précédent, du montant de l'espace réservé. |
| `mesure-f2-leviers.swift` | TextKit **ignore** `paragraphSpacingBefore` sur le premier paragraphe du conteneur. Deux leviers réservent l'espace malgré tout : le délégué `paragraphSpacingBeforeGlyphAt` (géométrie identique à l'attribut) et `exclusionPaths` (décale le fragment entier). |
| `mesure-f2-delegue.swift` | Le délégué **remplace** la valeur de l'attribut au lieu de s'y ajouter : un délégué qui renvoie 0 ailleurs qu'en tête réserve 0, pas la valeur de l'attribut. D'où le délégué passe-plat retenu, qui relit l'attribut et le renvoie. |
