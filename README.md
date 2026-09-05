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

### Configuration IA

Dans **Paramètres → Configuration IA**, choisissez **LM Studio**, **OpenRouter** ou
**Ollama**. Le catalogue se charge automatiquement ; recherchez et sélectionnez un
modèle (ou saisissez son identifiant).
Le test utilise le brouillon ; cliquez sur **Enregistrer** pour l’activer.

- **LM Studio** : lancez son serveur et rendez un modèle disponible. Adresse initiale :
  `http://localhost:1234/v1`. Le jeton est facultatif sauf si vous avez activé
  l’authentification sur le serveur.
- **OpenRouter** : renseignez sa clé API ; la connexion utilise
  `https://openrouter.ai/api/v1`. Les textes et le contexte des demandes sont envoyés
  au service distant. Les clés sont conservées dans le Trousseau, pas dans les exports.
  La recherche dans le catalogue public ne nécessite pas de clé.
- **Ollama** : lancez le serveur et installez le modèle souhaité. Adresse initiale :
  `http://localhost:11434/v1`. Catalogue, recherche et test fonctionnent comme pour LM Studio.
- Chaque fournisseur conserve sa configuration enregistrée. Les anciennes connexions
  cloud restent dans la liste « Historique ». Le moteur Direct est retiré ; ses anciens
  réglages ouvrent LM Studio avec un modèle à choisir. Aucun poids du cache partagé
  HuggingFace n'est supprimé automatiquement.
- Pour classer automatiquement les mails avec un endpoint distant, activez l’option
  correspondante dans les réglages Mail. Sinon, les règles locales restent utilisées.
- La transcription, la diarisation, les embeddings de recherche, l’OCR et la connexion
  de l’agent de tâches conservent leur fonctionnement actuel.

Une sauvegarde restaurée conserve les profils ; les clés doivent être ressaisies.
Le classement distant des mails doit être réactivé après restauration.

### Démarrage

1. Ouvrez le projet dans Xcode.
2. Compilez pour macOS.
3. Importez vos premiers collaborateurs et projets.
4. Utilisez le bouton "Import" (à implémenter dans la version finale) pour charger les dashboards hebdomadaires.
