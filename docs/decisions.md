# Registre des décisions d'architecture

> Généré par `Scripts/generer-decisions.py` depuis les en-têtes de `docs/adr/`. Ne pas éditer à la main :
> corriger l'ADR, puis relancer le script.

| Date | Décision | Statut | Fichier |
| --- | --- | --- | --- |
| 2026-09-09 | Un routeur pour la fenêtre principale | acceptée le 2026-09-09 (décision D0 de la refonte de la gestion des projets, validée par Laurent le 2026-09-09) | `docs/adr/2026-09-09-routeur-de-navigation.md` |
| 2026-09-09 | ⌘K va à la palette, l'assistant de réunion passe à ⌘⇧K | acceptée le 2026-09-09 (décision D1 de la refonte de la gestion des projets, validée par Laurent le 2026-09-09) | `docs/adr/2026-09-09-palette-commande-k.md` |
| 2026-09-09 | Refonte de la gestion des projets — bilan des décisions D0 à D18 | accepté, 2026-09-09 | `docs/adr/2026-09-09-gestion-projets-bilan.md` |
| 2026-09-09 | L'écran projet s'édite champ par champ, au clic, avec annulation | acceptée le 2026-09-09 (décision D9 de la refonte de la gestion des projets) | `docs/adr/2026-09-09-edition-in-place-fiche-projet.md` |
| 2026-09-08 | Refonte de l'écran de réunion — bilan des décisions D0 à D11 | accepté, 2026-09-08 | `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md` |
| 2026-09-07 | Pièces jointes de réunion : copiées, jamais référencées | validée le 2026-09-07 (décision D5 du programme de refonte, acceptée par Laurent le 2026-09-07) | `docs/adr/2026-09-07-pieces-copiees-jamais-referencees.md` |
| 2026-09-07 | Moteur de planches : Excalidraw embarqué dans un `WKWebView` | acceptée (décision D6 du plan directeur docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md) | `docs/adr/2026-09-07-moteur-de-planches-excalidraw-embarque.md` |
| 2026-09-05 | Niveau de raisonnement par profil et limite de sortie relevée | accepté le 2026-09-05, après investigation d’un rapport LM Studio resté en raisonnement plus de dix minutes, puis discussion avec l’utilisateur | `docs/adr/2026-09-05-raisonnement-configurable.md` |
| 2026-09-05 | ADR : inventaire du pipeline RAG | accepté (lecture seule du code existant — pas de changement) | `docs/adr/2026-09-05-rag-pipeline-inventaire.md` |
| 2026-09-05 | Endpoints IA configurables — LM Studio et OpenRouter | accepté pour les lots 1 à 4 | `docs/adr/2026-09-05-endpoints-ia-configurables.md` |
| 2026-09-05 | Catalogues IA, Ollama et retrait du moteur Direct | accepté le 2026-09-05, à la demande explicite de l’utilisateur après essai du premier écran IA | `docs/adr/2026-09-05-catalogues-ia-retrait-direct.md` |
| 2026-09-02 | ADR — Capture de slides : polling à empreinte avec stabilisation, à la place du flux SCStream + pHash | accepté | `docs/adr/2026-09-02-capture-slides-polling-empreinte.md` |
| 2026-08-11 | Suppression du modèle `Interview` | accepté | `docs/adr/2026-08-11-suppression-du-modele-interview.md` |
| 2026-08-08 | Verdict — une vue éditable par bloc tient-elle en AppKit ? | en attente | `docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md` |
| 2026-08-08 | Réécrire l'éditeur en reprenant l'architecture d'appflowy-editor | validée | `docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md` |
