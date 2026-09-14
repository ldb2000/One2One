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
| Portfolio | l'écran des projets : tableau triable, facettes, vues enregistrées — il a remplacé l'arbre par entité de la barre latérale | `PortfolioView`, `PortfolioRow`, `PortfolioBuilder` |
| Palette | la fenêtre de commande `⌘K` : projets, actions, recherche dans les comptes rendus | `CommandPalette`, `PaletteModel` |
| À risque | un projet dont un jalon est dépassé, sans réunion depuis 30 jours, ou dont la fiche est incomplète | `AtRiskView`, `AtRiskBuilder`, `AtRiskItem` |
| Épinglé | un projet mis en tête de la barre latérale par son porteur | `Project.pinned`, `PinnedProjectsList` |
| Récents | les derniers projets ouverts, retenus hors du store | `RecentProjects`, `RecentProjectsList` |
| Micro préféré | l'entrée audio choisie dans les Réglages pour tous les enregistrements ; vide = défaut système | `AppSettings.preferredAudioInputUID`, `AudioInputRouting` |
| Bascule par segment | à la disparition du micro en cours, le WAV est clos et un second s'ouvre sur l'entrée de repli, les segments sont fusionnés à l'arrêt ; le flux live ne s'interrompt pas | `AudioRecorderService.switchInput`, `TapSink.rotate`, `mergeSegments` |
| Source audio | un micro détecté par CoreAudio : identifiant stable, nom, intégré ou non, défaut système ou non | `AudioInputDevice`, `AudioInputDeviceService` |
