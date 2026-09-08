#!/usr/bin/env python3
"""Génère docs/decisions.md depuis les en-têtes de docs/adr/*.md.

Registre lisible des décisions : date (nom du fichier), titre (premier `# `),
statut (première ligne contenant « Statut », balises markdown retirées).
Ré-exécuté par le skill documenter-application à chaque ADR ajouté.
"""
import re, sys
from pathlib import Path

racine = Path(__file__).resolve().parent.parent
adr = racine / "docs" / "adr"
lignes = []
for f in sorted(adr.glob("*.md"), reverse=True):
    if f.name == "README.md":
        continue
    m = re.match(r"(\d{4}-\d{2}-\d{2})-", f.name)
    date = m.group(1) if m else "—"
    titre, statut = f.stem, "—"
    for l in f.read_text(encoding="utf-8").splitlines():
        if l.startswith("# ") and titre == f.stem:
            titre = l[2:].strip()
        if "Statut" in l and statut == "—":
            s = re.sub(r"[*_`]", "", l)
            s = re.sub(r"^\W*Statut\s*:\s*", "", s).strip().rstrip(".")
            statut = s
    lignes.append(f"| {date} | {titre} | {statut} | `docs/adr/{f.name}` |")

sortie = racine / "docs" / "decisions.md"
sortie.write_text(
    "# Registre des décisions d'architecture\n\n"
    "> Généré par `Scripts/generer-decisions.py` depuis les en-têtes de `docs/adr/`. Ne pas éditer à la main :\n"
    "> corriger l'ADR, puis relancer le script.\n\n"
    "| Date | Décision | Statut | Fichier |\n| --- | --- | --- | --- |\n" + "\n".join(lignes) + "\n",
    encoding="utf-8",
)
print(f"{len(lignes)} décisions → {sortie.relative_to(racine)}")
