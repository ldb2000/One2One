import SwiftUI
import SwiftData

/// L'écran projet de pilotage (capture `1d-ecran-projet-pilotage.png`), qui
/// remplace `ProjectDetailView` comme écran par défaut d'un projet.
///
/// **C'est un routeur, comme `MeetingView`.** Il monte l'en-tête, la barre
/// d'onglets et le contenu de l'onglet actif ; il ne dessine aucune carte. Ce
/// qu'il porte en propre, et qui ne pouvait vivre ailleurs :
///
/// - **l'état dérivé** — `ProjectPilotageState`, construit une fois par
///   `ProjectPilotageBuilder` et recalculé quand le store bouge, jamais dans
///   un `body` (décision **D11**) ;
/// - **le brouillon et la bannière d'annulation** — chaque édition in-place
///   passe par `editer(_:)`, qui prend un instantané, applique, et garde
///   l'instantané cinq secondes pour `UndoBanner` (décision **D9**) ;
/// - **les trois gestes de l'en-tête** — épingler, démarrer une réunion,
///   archiver ou supprimer.
///
/// `ProjectDetailView` n'est pas supprimée : elle **est** l'onglet « Fiche
/// complète », sans sa heatmap (remplacée par la tuile Rythme) ni sa barre
/// d'outils (Archiver et Supprimer sont passés dans le menu `···`).
struct ProjectScreen: View {

    // MARK: - Entrées

    let project: Project
    let tab: ProjectTab

    @Environment(MainRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var meetings: [Meeting]
    @Query private var suggestions: [MailIndexSuggestion]
    @Query(sort: \Collaborator.name) private var collaborators: [Collaborator]

    @State private var etat = ProjectPilotageState()
    /// L'instantané d'avant enregistrement, restauré par `UndoBanner`.
    @State private var undoSnapshot: ProjectCardDraft?
    @State private var confirmerLaSuppression = false
    @State private var confirmerLArchivage = false
    @State private var fileDeMails = false
    /// Le champ que la vue « À risque » demande d'ouvrir en édition (lot 5),
    /// une fois **consommé** au routeur. Remis à `nil` par la carte qui l'a
    /// honoré : une consigne ne vaut qu'une fois.
    @State private var champActif: ProjectField?

    // MARK: - Rendu

    var body: some View {
        VStack(spacing: 0) {
            entete
            contenu
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(One2OneToken.bgCanvas)
        .overlay(alignment: .bottom) { banniere }
        .onAppear { recharger(); consommerLeChamp() }
        .onChange(of: router.pendingFocusField) { _, _ in consommerLeChamp() }
        .onChange(of: project.persistentModelID) { _, _ in recharger() }
        .onChange(of: meetings.count) { _, _ in recharger() }
        .onChange(of: suggestions.count) { _, _ in recharger() }
        .onChange(of: project.tasks.count) { _, _ in recharger() }
        .onChange(of: project.mails.count) { _, _ in recharger() }
        .confirmationDialog(ProjectHeader.confirmerLaSuppression,
                            isPresented: $confirmerLaSuppression) {
            Button(ProjectHeader.supprimer, role: .destructive) { supprimer() }
            Button(ProjectHeader.conserver, role: .cancel) {}
        } message: {
            Text(ProjectHeader.detailDeLaSuppression)
        }
        .confirmationDialog(ProjectHeader.confirmerLArchivage,
                            isPresented: $confirmerLArchivage) {
            Button(ProjectHeader.archiver) { basculerLArchivage() }
            Button(ProjectHeader.annuler, role: .cancel) {}
        } message: {
            Text(ProjectHeader.detailDeLArchivage)
        }
        .sheet(isPresented: $fileDeMails) {
            MailSuggestionReviewSheet { fileDeMails = false }
        }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProjectHeader(project: project,
                          etat: etat,
                          onPortfolio: { router.open(.portfolio) },
                          onEntite: { router.open(.portfolio) },
                          onEpingler: epingler,
                          onDemarrerUneReunion: demarrerUneReunion,
                          onArchiver: archiver,
                          onSupprimer: { confirmerLaSuppression = true },
                          onFicheComplete: { choisir(.fiche) },
                          onStatut: { valeur in editer { $0.statusRaw = valeur } },
                          champActif: champActif,
                          onChampConsomme: { champActif = nil })
            ProjectTabs(courant: tab, etat: etat, onChoisir: choisir)
        }
        .padding(.horizontal, PilotageTab.margeH)
        .padding(.top, PilotageTab.margeHaute)
    }

    @ViewBuilder
    private var contenu: some View {
        switch tab {
        case .pilotage:
            PilotageTab(etat: etat,
                        collaborateurs: collaborators,
                        suggestions: suggestionsDeRole,
                        onToutVoir: { choisir(.actions) },
                        onHistorique: { choisir(.meetings) },
                        onCocher: solder,
                        onOuvrirReunion: { ouvrirLaReunion($0.stableID, id: $0.id) },
                        onPerimetre: { texte in editer { $0.scopeText = texte } },
                        onOuvrirCollaborateur: { router.open(.collaborator($0)) },
                        onAffecter: affecter,
                        onSponsor: { nom in editer { $0.sponsor = nom } },
                        onRisque: { niveau in editer { $0.riskLevelRaw = niveau } },
                        onDescriptionDeRisque: { texte in editer { $0.riskDescription = texte } },
                        onRattacherLesMails: { fileDeMails = true },
                        onFicheComplete: { choisir(.fiche) },
                        champActif: champActif,
                        onChampConsomme: { champActif = nil })
        case .meetings:
            ProjectMeetingsTab(lignes: reunionsDuProjet.map(ProjectMeetingRow.init),
                               onOuvrir: { ouvrirLaReunion($0.stableID, id: $0.id) })
        case .actions:
            ProjectActionsTab(ouvertes: lignesDActions(ouvertes: true),
                              terminees: lignesDActions(ouvertes: false),
                              onBasculer: basculer)
        case .mails:
            ProjectMailsTab(mails: project.mails
                                .sorted { $0.dateReceived > $1.dateReceived }
                                .map(ProjectMailRow.init),
                            onRattacher: { fileDeMails = true })
        case .documents:
            ProjectDocumentsTab(project: project)
        case .fiche:
            ProjectDetailView(project: project)
        }
    }

    @ViewBuilder
    private var banniere: some View {
        if let instantane = undoSnapshot {
            UndoBanner(onUndo: { annuler(instantane) },
                       onExpire: { undoSnapshot = nil })
                .frame(maxWidth: 380)
                .padding(.bottom, 14)
        }
    }

    // MARK: - État dérivé

    private var reunionsDuProjet: [Meeting] {
        ProjectPilotageBuilder.reunionsDuProjet(project, parmi: meetings, today: Date())
    }

    /// Le collaborateur que la chaîne libre du xlsx désigne, par rôle
    /// (décision **D3**) : c'est lui que le `＋` de la carte Interlocuteurs
    /// propose en tête.
    private var suggestionsDeRole: [String: Collaborator] {
        var table: [String: Collaborator] = [:]
        if let chef = ProjectPeople.suggestedManager(for: project, among: collaborators) {
            table["Chef de projet"] = chef
        }
        if let architecte = ProjectPeople.suggestedArchitect(for: project, among: collaborators) {
            table["Architecte technique"] = architecte
        }
        return table
    }

    /// Prend la consigne d'édition posée par la vue « À risque » et la
    /// retient jusqu'à ce que la carte concernée l'honore.
    ///
    /// **Consommée au routeur tout de suite** : revenir sur cet écran par
    /// « retour » ne doit pas rouvrir un champ qu'on venait de refermer.
    /// `.milestone` est consommé sans effet — la « Fiche complète » n'a pas
    /// d'éditeur de jalons, seul `ProjectCardPanel` en a un (réserve du lot).
    private func consommerLeChamp() {
        guard let champ = router.consumePendingFocusField() else { return }
        champActif = champ
    }

    private func recharger() {
        etat = ProjectPilotageBuilder.build(project: project,
                                            meetings: meetings,
                                            suggestions: suggestions,
                                            today: Date())
    }

    /// Les lignes de l'onglet Actions. La carte de pilotage se limite à quatre
    /// et n'affiche que les ouvertes ; l'onglet montre tout, dans le même
    /// format.
    private func lignesDActions(ouvertes: Bool) -> [ProjectPilotageState.ActionRow] {
        let debut = Calendar.current.startOfDay(for: Date())
        let taches = project.tasks.filter { ouvertes ? $0.status == .open : $0.status != .open }
        return ProjectPilotageBuilder.lignesDActions(taches, debutDuJour: debut,
                                                     limite: taches.count)
    }

    // MARK: - Navigation

    /// Change d'onglet **sans** empiler l'histoire : parcourir six onglets ne
    /// doit pas coûter six « retour ».
    private func choisir(_ onglet: ProjectTab) {
        router.switchTab(onglet)
    }

    /// Ouvre une réunion par le jeton de lancement — le chemin de la barre
    /// latérale, de la recherche dans les CR et des notifications.
    private func ouvrirLaReunion(_ stableID: UUID?, id: PersistentIdentifier) {
        let cible = stableID
            ?? meetings.first { $0.persistentModelID == id }?.ensuredStableID
        guard let cible else { return }
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(meetingID: cible,
                                                                    autoStartRecording: false)
    }

    // MARK: - Gestes de l'en-tête

    private func epingler() {
        project.pinned.toggle()
        enregistrer()
    }

    /// Crée une réunion projet **datée de maintenant** et l'ouvre, sans
    /// démarrer l'enregistrement : c'est le geste « on s'y met », pas
    /// « j'enregistre ».
    private func demarrerUneReunion() {
        let reunion = Meeting(title: project.name, date: Date(), notes: "")
        reunion.kind = .project
        context.insert(reunion)
        reunion.project = project
        enregistrer()
        QuickLaunchRouter.shared.pendingToken =
            OneToOneLaunchToken(meetingID: reunion.ensuredStableID, autoStartRecording: false)
    }

    /// Archiver **demande confirmation**, désarchiver non.
    ///
    /// Archiver retire le projet du Portfolio et de la barre latérale : il
    /// disparaît de tous les écrans où on le cherchait, et rien ne le signale
    /// une fois le menu refermé. Désarchiver ne fait que le ramener — un geste
    /// qui rend visible n'a pas à se justifier.
    private func archiver() {
        if project.isArchived {
            basculerLArchivage()
        } else {
            confirmerLArchivage = true
        }
    }

    private func basculerLArchivage() {
        project.isArchived.toggle()
        enregistrer()
    }

    private func supprimer() {
        context.delete(project)
        try? context.save()
        router.open(.portfolio)
    }

    // MARK: - Gestes des cartes

    private func solder(_ ligne: ProjectPilotageState.ActionRow) {
        guard let tache = project.tasks.first(where: { $0.persistentModelID == ligne.id })
        else { return }
        tache.status = .done
        tache.completedAt = Date()
        enregistrer()
        recharger()
    }

    private func basculer(_ ligne: ProjectPilotageState.ActionRow) {
        guard let tache = project.tasks.first(where: { $0.persistentModelID == ligne.id })
        else { return }
        tache.status = tache.status == .done ? .open : .done
        tache.completedAt = tache.status == .done ? Date() : nil
        enregistrer()
        recharger()
    }

    private func affecter(_ role: String, _ collaborateur: Collaborator?) {
        editer { brouillon in
            switch role {
            case "Chef de projet":       brouillon.managerID = collaborateur?.persistentModelID
            case "Architecte technique": brouillon.architectID = collaborateur?.persistentModelID
            default: break
            }
        }
    }

    // MARK: - Édition in-place (décision D9)

    /// Le **seul** point d'écriture des champs de la fiche : un instantané, la
    /// transformation, l'application, la bannière. Une transformation qui ne
    /// change rien n'écrit pas et n'affiche pas de bannière — un `⏎` sur un
    /// champ intact ne doit rien proposer d'annuler.
    private func editer(_ transformer: (inout ProjectCardDraft) -> Void) {
        let avant = ProjectCardDraft.snapshot(of: project)
        var brouillon = avant
        transformer(&brouillon)
        guard brouillon != avant else { return }
        brouillon.stampScopeIfChanged(from: avant)
        brouillon.apply(to: project, in: context)
        undoSnapshot = avant
        recharger()
    }

    private func annuler(_ instantane: ProjectCardDraft) {
        instantane.apply(to: project, in: context)
        undoSnapshot = nil
        recharger()
    }

    private func enregistrer() {
        do {
            try context.save()
            SpotlightIndexService.shared.index(project: project)
        } catch {
            print("[ProjectScreen] enregistrement échoué : \(error)")
        }
    }
}
