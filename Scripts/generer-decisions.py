#!/usr/bin/env python3
"""Génère docs/decisions.md depuis les en-têtes de docs/adr/*.md.

Registre lisible des décisions : date (nom du fichier), titre (premier `# `),
statut (premier champ « Statut » de l'en-tête, où qu'il soit dans sa ligne —
« Date : … · Statut : accepté · Spec : … » sur une seule ligne compte).

La valeur du statut se poursuit sur les lignes de continuation (un en-tête peut
être replié) puis s'arrête au premier séparateur de champ rencontré **hors
parenthèses** (`·`, `|`, ` — `) ou à la fin de sa première phrase. Un ADR validé
n'a donc pas à être reformaté pour ce script : c'est le script qui s'adapte.
Les `|` restants sont échappés pour ne pas casser la table.

Ré-exécuté par le skill documenter-application à chaque ADR ajouté.
"""
import re
from pathlib import Path

racine = Path(__file__).resolve().parent.parent
adr = racine / "docs" / "adr"

STATUT = re.compile(r"Statut\s*:")
# Début d'un autre champ d'en-tête : « Portée : », « Date : », « - Lot : »…
CHAMP = re.compile(r"^\s*[-*]*\s*[A-ZÀ-Ý][\wÀ-ſ' ]{0,30}\s*:")


def sans_markdown(ligne: str) -> str:
    return re.sub(r"[*_`]", "", ligne)


def coupe(valeur: str) -> str:
    """Tronque au premier séparateur de champ ou à la fin de la première phrase.

    Les séparateurs à l'intérieur de parenthèses ne comptent pas : « accepté
    (lecture seule du code existant — pas de changement) » reste entier.
    """
    profondeur = 0
    for i, c in enumerate(valeur):
        if c in "([":
            profondeur += 1
        elif c in ")]":
            profondeur = max(0, profondeur - 1)
        elif profondeur == 0:
            if c in "·|":
                return valeur[:i]
            if valeur.startswith(" — ", i) or valeur.startswith(" – ", i):
                return valeur[:i]
            if c == "." and (i + 1 == len(valeur) or valeur[i + 1] == " "):
                return valeur[: i + 1]
    return valeur


def cellule(texte: str) -> str:
    return texte.replace("|", "\\|")


def statut_de(lignes: list[str]) -> str:
    for i, brute in enumerate(lignes):
        propre = sans_markdown(brute)
        m = STATUT.search(propre)
        if not m:
            continue
        morceaux = [propre[m.end():].strip()]
        for suite in lignes[i + 1:]:
            s = sans_markdown(suite)
            if not s.strip() or s.lstrip().startswith("#") or CHAMP.match(s):
                break
            morceaux.append(s.strip())
        return coupe(" ".join(morceaux).strip()).strip().rstrip(" .,;")
    return "—"


def titre_de(lignes: list[str], defaut: str) -> str:
    for l in lignes:
        if l.startswith("# "):
            return l[2:].strip()
    return defaut


lignes = []
for f in sorted(adr.glob("*.md"), reverse=True):
    if f.name == "README.md":
        continue
    m = re.match(r"(\d{4}-\d{2}-\d{2})-", f.name)
    date = m.group(1) if m else "—"
    contenu = f.read_text(encoding="utf-8").splitlines()
    titre = cellule(titre_de(contenu, f.stem))
    statut = cellule(statut_de(contenu))
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
