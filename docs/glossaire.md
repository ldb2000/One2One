# Glossaire — termes métier et symboles

| Terme (français) | Définition | Symbole Swift |
| --- | --- | --- |
| Réunion | unité de travail : audio, notes, transcription, rapport | `Meeting` |
| Note horodatée | ligne de note liée à l'audio par `t` | `MeetingNote` |
| Tête de lecture | position courante sur l'axe audio, partagée par tout l'écran | `MeetingPlayhead` |
| Action | tâche issue d'une réunion, avec source (`sourceRef`) | `ActionTask` |
| Fil 1:1 | suite des entretiens avec un collaborateur | `OneOnOneThread` |
| Engagement | promesse tenue ou non, par côté (manager / collaborateur) | `Commitment` |
| Sujet d'ordre du jour | point à aborder, reporté s'il n'est pas traité | `OneOnOneAgendaItem` |
| Humeur | cran de moral saisi en séance | `MoodEntry` |
| Objectif | objectif suivi sur le fil | `OneOnOneObjective` |
| Pièce | fichier, lien ou capture rattaché à une réunion | `MeetingAttachment` |
| Capture | image d'écran horodatée, texte extrait par OCR | `SlideCapture` |
| Planche | tableau blanc d'un atelier, stocké sur disque | `Board` |
| Fiche projet | jalons, interlocuteurs, budget, périmètre d'un projet | `Project`, `ProjectMilestone`, `ProjectContact` |
| Espace / mode | Réunion, Rapport, Ressources × Préparer, En séance, Relire | `MeetingScreenModel` |
| Séance | le mode « En séance » d'une réunion : prise de notes et capture pendant qu'elle a lieu | `MeetingScreenModel.Mode.live` |
