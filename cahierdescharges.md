# Cahier des Charges - Application OneToOne (MacOS)

## 1. Objectif de l'Application
Créer un outil de gestion d'entretiens et de suivi de projets pour un manager d'architectes. L'application doit permettre de centraliser les informations projet, les actions à mener et de faciliter le reporting.

## 2. Fonctionnalités Clés
- **Gestion de Projets** : Suivi des codes, noms, statuts (Cadrage, Design, Build, Run) et phases.
- **Gestion des Entretiens (One-to-One)** :
    - Prise de notes simplifiée.
    - Intégration avec l'application **Mickey** pour l'enregistrement audio.
    - Historique des échanges par collaborateur.
- **Suivi d'Actions** :
    - Création de listes de tâches.
    - Synchronisation avec **Apple Reminders**.
- **Ingestion de Données par IA** :
    - Analyse de fichiers (PPTX, PDF) pour extraire et mettre à jour les statuts de projets (ex: Dashboards STTI).
    - Mise à jour automatique de la base de données locale.
- **Tableaux de Bord & Reporting** :
    - Visualisation des faits marquants.
    - Suivi de l'avancement pour le management.
    - Export en **PDF** et **Markdown**.
- **Visualisation & Liens** :
    - Support de **Mermaid** pour les diagrammes de flux.
    - Liens vers les documents techniques (DAT - Dossier d'Architecture Technique, DIT).
    - Vérification du statut des DIT.

## 3. Design & UX
- Style **macOS natif** (SwiftUI), épuré et moderne.
- Navigation intuitive entre les collaborateurs et les projets.
- Recherche globale performante.

## 4. Architecture Technique
- **Langage** : Swift (SwiftUI).
- **Persistence** : SwiftData.
- **Intégrations** :
    - Apple Reminders API (EventKit).
    - Mickey (AppleScript ou URL Schemes).
    - IA : Intégration d'un modèle pour le parsing de documents (via API type OpenAI/Anthropic ou local si possible).
    - Mermaid.js (via WebView ou rendu natif).

## 5. Plan d'Action (Roadmap)

### Phase 1 : Fondations & UI
- [x] Initialisation du projet Xcode (SwiftUI, SwiftData).
- [x] Mise en place de la structure de données (Collaborateur, Projet, Action, Note).
- [x] Création de l'interface principale (Sidebar, Listes, Détails).

### Phase 2 : Gestion des Actions & Intégrations Apple
- [x] Implémentation du système de notes.
- [x] Connexion avec Apple Reminders.
- [x] Mise en place du lien avec Mickey (Trigger d'enregistrement).

### Phase 3 : Ingestion IA & Documents
- [x] Module d'importation de fichiers (Drag & Drop) - Structure en place.
- [x] Pipeline d'extraction de données (Parsing PDF/PPTX via IA) - Service simulé avec données réelles S12.
- [x] Logique de mise à jour automatique des projets.

### Phase 4 : Reporting & Visualisation
- [x] Intégration de Mermaid pour les diagrammes.
- [x] Création du Dashboard (KPIs, Statuts).
- [x] Moteur d'export (PDF/Markdown).

### Phase 5 : Finalisation & Polissage
- [x] Design "Pixel Perfect" & Navigation (Sidebar enrichie).
- [ ] Tests de bout en bout.
- [ ] Optimisation des performances.
