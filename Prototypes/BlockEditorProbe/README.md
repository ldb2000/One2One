# BlockEditorProbe — sonde jetable

Ce paquet **n'est pas du code de production**. Il répond par oui ou non à une
seule question : une vue éditable par bloc (`NSTextView` par bloc) tient-elle
en AppKit ?

- Spec : `docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`
- Plan : `docs/superpowers/plans/2026-08-08-prototype-editeur-par-blocs.md`
- Livrable réel : un ADR de verdict dans `docs/adr/`.

## Commandes

```bash
cd Prototypes/BlockEditorProbe
swift test                                  # ProbeCore, pur, quelques secondes
swift run block-editor-probe                # fenêtre interactive, 12 blocs
swift run block-editor-probe --blocks 40    # fenêtre interactive, 40 blocs
swift run block-editor-probe --scale        # 200 blocs, trois mesures, sortie texte
```

## Péremption

**Ce répertoire doit être supprimé une fois l'ADR de verdict écrit.** S'il est
encore là et que l'ADR existe, c'est un oubli.
