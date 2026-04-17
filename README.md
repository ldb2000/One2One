# Application OneToOne (MacOS)

Cette application est conçue pour aider les managers d'architectes à suivre les projets et les entretiens individuels.

## Structure du Projet

- `OneToOneApp.swift` : Point d'entrée de l'application et configuration du conteneur SwiftData.
- `Models/` : Définition des modèles de données (`Project`, `Collaborator`, `Interview`, `ActionTask`).
- `Views/` : Interfaces utilisateur SwiftUI.
    - `Sidebar.swift` : Navigation principale.
    - `ProjectListView.swift` : Liste des projets avec recherche.
    - `DetailsViews.swift` : Vues détaillées pour les projets, collaborateurs et entretiens.
    - `MermaidView.swift` : Rendu des diagrammes Mermaid.
- `Services/` : Logique métier et intégrations.
    - `ExternalServices.swift` : Intégration avec Apple Reminders et l'application Mickey.
    - `AIIngestionService.swift` : Pipeline pour l'importation de données via IA.
- `Resources/` : Données d'exemple et assets.

## Fonctionnalités Implémentées

1. **Suivi de Projets** :
    - Gestion des statuts (Vert, Jaune, Rouge).
    - Suivi des phases (Cadrage, Design, Build, Run).
    - Indicateurs pour les documents techniques (DAT/DIT).
2. **Entretiens (One-to-One)** :
    - Prise de notes interactive.
    - Contrôle de l'application **Mickey** pour l'enregistrement audio.
3. **Actions & Rappels** :
    - Système de tâches lié aux projets.
    - Intégration avec **Apple Reminders** pour ne rien oublier sur son Mac.
4. **Ingestion IA** :
    - Capacité à ingérer des fichiers PDF/PPTX (Dashboards STTI) pour mettre à jour automatiquement les projets.
5. **Visualisation** :
    - Intégration de diagrammes **Mermaid** pour visualiser les flux projet.

## Utilisation

1. Ouvrez le projet dans Xcode.
2. Compilez pour macOS.
3. Importez vos premiers collaborateurs et projets.
4. Utilisez le bouton "Import" (à implémenter dans la version finale) pour charger les dashboards hebdomadaires.
