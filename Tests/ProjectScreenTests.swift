import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import OneToOne

/// L'écran projet à six onglets (capture `1d-ecran-projet-pilotage.png`).
///
/// Ce qu'un test peut tenir sans session graphique : les libellés **au mot
/// près**, les mesures du handoff §1d, les teintes prises dans les tables du
/// lot 2, la règle de badge des onglets, le comportement du routeur, et le
/// fait que la fiche complète a bien perdu sa heatmap et sa barre d'outils.
@Suite("Écran projet — en-tête, onglets et cartes")
@MainActor
struct ProjectScreenTests {

    // MARK: - Outillage

    private var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    private func contexteEnMemoire() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    /// Le semis complet, et l'état du projet de la capture 1d.
    private func semis() throws -> (contexte: ModelContext,
                                    projet: Project,
                                    etat: ProjectPilotageState) {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try #require(try contexte.fetch(FetchDescriptor<Project>()).first {
            $0.stableID == RefonteDemoSeed.portfolioFocusProjectStableID
        })
        let etat = ProjectPilotageBuilder.build(
            project: projet,
            meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
            suggestions: try contexte.fetch(FetchDescriptor<MailIndexSuggestion>()),
            today: Date())
        return (contexte, projet, etat)
    }

    // MARK: - Les six onglets

    @Test("Les six onglets portent les libellés de la capture, dans son ordre")
    func libellesDesOnglets() {
        #expect(ProjectTab.allCases.map(\.label) == [
            "Pilotage", "Réunions & CR", "Actions", "Mails", "Documents", "Fiche complète",
        ])
    }

    /// Deux onglets seulement portent un badge : les actions ouvertes et les
    /// mails rattachés.
    @Test("Les badges d'onglets comptent les actions ouvertes et les mails")
    func badgesDOnglets() throws {
        let semis = try semis()
        #expect(ProjectTabs.badge(.actions, etat: semis.etat) == 6)
        #expect(ProjectTabs.badge(.mails, etat: semis.etat) == 2)
        for onglet in [ProjectTab.pilotage, .meetings, .documents, .fiche] {
            #expect(ProjectTabs.badge(onglet, etat: semis.etat) == nil)
        }
    }

    @Test("Un compteur à zéro n'affiche pas de badge")
    func badgeZero() {
        let vide = ProjectPilotageState()
        #expect(ProjectTabs.badge(.actions, etat: vide) == nil)
        #expect(ProjectTabs.badge(.mails, etat: vide) == nil)
    }

    @Test("Le badge des actions est bleu, celui des mails est neutre")
    func teintesDesBadges() {
        #expect(ProjectTabs.fondDeBadge(.actions) == One2OneToken.actionBg)
        #expect(ProjectTabs.encreDeBadge(.actions) == One2OneToken.actionInk)
        #expect(ProjectTabs.fondDeBadge(.mails) == One2OneToken.hair)
        #expect(ProjectTabs.encreDeBadge(.mails) == One2OneToken.ink4)
    }

    @Test("La barre d'onglets tient les mesures du handoff §1d")
    func mesuresDesOnglets() {
        #expect(ProjectTabs.taille == 13)
        #expect(ProjectTabs.ecart == 22)
        #expect(ProjectTabs.epaisseurSoulignement == 2)
        #expect(ProjectTabs.tailleBadge == 10.5)
    }

    // MARK: - L'en-tête

    @Test("L'en-tête porte les libellés de la capture")
    func libellesDeLEnTete() {
        #expect(ProjectHeader.racine == "Portfolio")
        #expect(ProjectHeader.epingler == "Épingler")
        #expect(ProjectHeader.epingle == "Épinglé")
        #expect(ProjectHeader.demarrerUneReunion == "Démarrer une réunion")
        #expect(ProjectHeader.plus == "···")
        #expect(ProjectHeader.archiver == "Archiver")
        #expect(ProjectHeader.desarchiver == "Désarchiver")
        #expect(ProjectHeader.supprimer == "Supprimer")
        #expect(ProjectHeader.ouvrirLaFiche == "Ouvrir la fiche complète")
    }

    @Test("L'en-tête tient les mesures du handoff §1d")
    func mesuresDeLEnTete() {
        #expect(ProjectHeader.tailleTitre == 21)
        #expect(ProjectHeader.tailleFilDAriane == 11)
        #expect(ProjectHeader.taillePilule == 12)
        #expect(ProjectHeader.tailleBouton == 12.5)
    }

    /// La pilule de statut : le libellé français de `ProjectStatus`
    /// (« Au vert »), la pastille de `StatusIcon`, les fonds du handoff.
    @Test("La pilule de statut est « Au vert » sur fond okBg")
    func piluleDeStatut() throws {
        let semis = try semis()
        let statut = try #require(ProjectStatus(raw: semis.projet.status))
        #expect(statut.displayLabel == "Au vert")
        #expect(ProjectHeader.fondDeStatut(.green) == One2OneToken.okBg)
        #expect(ProjectHeader.encreDeStatut(.green) == One2OneToken.okDeep)
        #expect(ProjectHeader.fondDeStatut(.yellow) == One2OneToken.warnBg)
        #expect(ProjectHeader.encreDeStatut(.yellow) == One2OneToken.warnInk)
        #expect(ProjectHeader.fondDeStatut(.red) == One2OneToken.reportBg)
        #expect(ProjectHeader.encreDeStatut(.red) == One2OneToken.reportInk)
        // Hors table, le neutre de D14.
        #expect(ProjectHeader.fondDeStatut(nil) == One2OneToken.surfaceAlt)
        #expect(ProjectHeader.encreDeStatut(nil) == One2OneToken.ink4)
    }

    /// Le fil d'Ariane du projet de la capture : `Portfolio / ASP / P25_193`.
    @Test("Le fil d'Ariane nomme le portefeuille, l'entité et le code")
    func filDAriane() throws {
        let semis = try semis()
        let entete = ProjectHeader(project: semis.projet, etat: semis.etat,
                                   onPortfolio: {}, onEntite: {}, onEpingler: {},
                                   onDemarrerUneReunion: {}, onArchiver: {},
                                   onSupprimer: {}, onFicheComplete: {})
        #expect(entete.entite == "ASP")
        #expect(semis.projet.code == "P25_193")
    }

    @Test("Un projet sans entité ni domaine le dit plutôt que d'afficher un vide")
    func filDArianeSansEntite() throws {
        let contexte = try contexteEnMemoire()
        let projet = Project(code: "T_001", name: "Sans entité", domain: "",
                             phase: "Build", status: "Green")
        contexte.insert(projet)
        let entete = ProjectHeader(project: projet, etat: ProjectPilotageState(),
                                   onPortfolio: {}, onEntite: {}, onEpingler: {},
                                   onDemarrerUneReunion: {}, onArchiver: {},
                                   onSupprimer: {}, onFicheComplete: {})
        #expect(entete.entite == ProjectHeader.sansEntite)
    }

    // MARK: - Les quatre tuiles

    @Test("Les quatre tuiles portent les libellés de la capture")
    func libellesDesTuiles() {
        #expect(KPITiles.labelActions == "ACTIONS OUVERTES")
        #expect(KPITiles.labelDerniereReunion == "DERNIÈRE RÉUNION")
        #expect(KPITiles.labelRythme == "RYTHME")
        #expect(KPITiles.labelCharge == "CHARGE")
    }

    @Test("Les tuiles tiennent les mesures du handoff §1d")
    func mesuresDesTuiles() {
        #expect(KPITiles.gap == 10)
        #expect(KPITiles.tailleValeur == 22)
        #expect(KPITiles.tailleSousLigne == 11.5)
        #expect(KPITiles.largeurBarre == 7)
        #expect(KPITiles.hauteurBarres == 26)
        #expect(KPITiles.hauteurJauge == 4)
    }

    /// La tuile « RYTHME » : huit barres, dégradé `okBg → ok`. Une semaine
    /// sans réunion garde une barre visible — un trou se lirait comme une
    /// donnée manquante.
    @Test("Le dégradé du rythme va de okBg à ok, et une barre vide reste visible")
    func degradeDuRythme() {
        #expect(KPITiles.teinteDeBarre(0, maximum: 3) == One2OneToken.okBg)
        #expect(KPITiles.teinteDeBarre(3, maximum: 3) == One2OneToken.okBg.mix(with: One2OneToken.ok, by: 1))
        #expect(KPITiles.hauteurDeBarre(0, maximum: 3) == 2)
        #expect(KPITiles.hauteurDeBarre(3, maximum: 3) == KPITiles.hauteurBarres)
        #expect(KPITiles.hauteurDeBarre(1, maximum: 3) < KPITiles.hauteurDeBarre(2, maximum: 3))
    }

    // MARK: - Les cartes de la colonne principale

    @Test("Les cartes portent les libellés et les liens de la capture")
    func libellesDesCartes() {
        #expect(OpenActionsCard.titre == "ACTIONS EN COURS")
        #expect(OpenActionsCard.lien == "Tout voir")
        #expect(RecentMeetingsCard.titre == "DERNIÈRES RÉUNIONS")
        #expect(RecentMeetingsCard.lien == "Historique")
        #expect(ScopeCard.titre == "PÉRIMÈTRE & CONTEXTE")
    }

    @Test("Les cartes tiennent les mesures du handoff §1d")
    func mesuresDesCartes() {
        #expect(OpenActionsCard.cote == 14)
        #expect(OpenActionsCard.tailleTitre == 13)
        #expect(OpenActionsCard.tailleSousLigne == 11.5)
        #expect(OpenActionsCard.tailleEcheance == 11)
        #expect(RecentMeetingsCard.largeurDate == 44)
        #expect(RecentMeetingsCard.tailleDate == 11)
        #expect(RecentMeetingsCard.tailleResume == 12)
        #expect(ScopeCard.tailleTexte == 13)
        #expect(PilotageMetrics.margeH == 13)
        #expect(PilotageMetrics.margeV == 12)
        #expect(PilotageMetrics.ecartCartes == 14)
        #expect(PilotageTab.ecartColonnes == 16)
        #expect(PilotageTab.margeH == 22)
        #expect(PilotageTab.margeHaute == 16)
        #expect(PilotageTab.margeBasse == 22)
    }

    /// Rouge pour un retard, encre lisible pour une date, encre effacée pour
    /// une action sans échéance.
    @Test("L'échéance d'une action prend trois teintes")
    func teintesDEcheance() {
        #expect(OpenActionsCard.teinteDEcheance(.retard(3)) == One2OneToken.reportInk)
        #expect(OpenActionsCard.teinteDEcheance(.date("14/09")) == One2OneToken.ink3)
        #expect(OpenActionsCard.teinteDEcheance(.aucune) == One2OneToken.inkMuted)
    }

    @Test("Le pied du périmètre invite à éditer")
    func piedDuPerimetre() {
        #expect(EditableInPlace<Text>.aide == "Cliquer pour éditer")
        #expect(ScopeCard.taillePied == 11.5)
    }

    // MARK: - La colonne latérale

    @Test("Les quatre cartes latérales portent les libellés de la capture")
    func libellesDeLaColonne() {
        #expect(InterlocutorsCard.titre == "INTERLOCUTEURS")
        #expect(InterlocutorsCard.raccourci == "1:1 ▸")
        #expect(RiskCard.titre == "RISQUE")
        #expect(RiskCard.modifier == "Modifier")
        #expect(LinkedMailsCard.titre == "MAILS LIÉS")
        #expect(IdentityCard.titre == "IDENTITÉ")
        #expect(IdentityCard.lien == "Voir la fiche complète ▸")
    }

    @Test("La colonne latérale fait 330 pt, ses avatars 26")
    func mesuresDeLaColonne() {
        #expect(SideColumn.largeur == 330)
        #expect(SideColumn.largeur == One2OneToken.actionsRailWidth)
        #expect(AvatarStack.diametreProjet == 26)
        // Le chevauchement suit le diamètre : deux pastilles de 26 pt ne se
        // touchent pas comme deux de 19.
        #expect(AvatarStack.chevauchement(pour: 19) == -6)
        #expect(AvatarStack.chevauchement(pour: 26) < -6)
    }

    /// Le rôle et la sous-ligne d'un mail sont à 11 pt : sous le plancher de
    /// 11,5 pt d'`inkMuted`, donc en `ink4` (même arbitrage qu'au lot 1).
    ///
    /// Les deux constantes sont vérifiées **et** le périmètre est balayé : une
    /// taille littérale posée sous 11,5 pt à trois lignes d'un `inkMuted` est
    /// exactement la faute que la règle §1.2 vise, et elle ne change l'état
    /// d'aucun modèle — donc aucune autre suite ne la verrait.
    @Test("Aucun texte sous 11,5 pt n'est en inkMuted")
    func plancherDInkMuted() throws {
        #expect(InterlocutorsCard.tailleRole == 11)
        #expect(LinkedMailsCard.tailleSousLigne == 11)
        // Les tailles nommées qui accompagnent un `inkMuted` sont au-dessus.
        for taille in [KPITiles.tailleSousLigne, OpenActionsCard.tailleSousLigne,
                       ScopeCard.taillePied, LinkedMailsCard.tailleInvite,
                       PilotageCardHeader.tailleLien, IdentityCard.tailleLien,
                       EditableInPlace<Text>.tailleIndice] {
            #expect(taille >= 11.5)
        }

        let motif = try NSRegularExpression(pattern: "\\.plex(?:Sans|Mono)\\((\\d+(?:\\.\\d+)?)")
        for fichier in try fichiersDuPerimetre() {
            let lignes = fichier.texte.components(separatedBy: "\n")
            for (index, ligne) in lignes.enumerated() where ligne.contains("One2OneToken.inkMuted") {
                let contexte = lignes[max(0, index - 3)...index].joined(separator: "\n")
                let ns = contexte as NSString
                for correspondance in motif.matches(in: contexte,
                                                    range: NSRange(location: 0, length: ns.length)) {
                    let taille = Double(ns.substring(with: correspondance.range(at: 1))) ?? 0
                    #expect(taille >= 11.5,
                            "\(fichier.nom):\(index + 1) pose inkMuted à \(taille) pt")
                }
            }
        }
    }

    /// Les sources de `Views/Project/`, y compris ses deux sous-dossiers.
    private func fichiersDuPerimetre() throws -> [(nom: String, texte: String)] {
        let base = racine.appendingPathComponent("OneToOne/Views/Project")
        var resultat: [(nom: String, texte: String)] = []
        let enumerateur = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let url = enumerateur?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            resultat.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        #expect(resultat.count >= 12, "le périmètre de l'écran projet a bougé")
        return resultat
    }

    /// L'invite de rattachement est posée sur `actionBg`, comme la capture.
    @Test("L'encart de rattachement est en actionBg")
    func encartDeRattachement() throws {
        let source = try source("OneToOne/Views/Project/Pilotage/SideColumn.swift")
        #expect(source.contains("One2OneToken.actionBg"))
        #expect(LinkedMailsCard.etincelle == "✦")
    }

    // MARK: - Le routeur

    /// Changer d'onglet ne doit pas coûter un « retour » par onglet.
    @Test("Changer d'onglet n'empile pas l'histoire")
    func changerDOngletNEmpilePas() {
        let routeur = MainRouter(defaults: reglagesEnMemoire())
        let id = UUID()
        routeur.open(.project(id, .pilotage))
        let profondeur = routeur.history.count
        routeur.switchTab(.actions)
        #expect(routeur.route == .project(id, .actions))
        #expect(routeur.history.count == profondeur)
        routeur.switchTab(.mails)
        #expect(routeur.route == .project(id, .mails))
        #expect(routeur.history.count == profondeur)
    }

    @Test("Changer d'onglet est sans effet hors d'un écran projet, ou sur l'onglet courant")
    func changerDOngletSansObjet() {
        let routeur = MainRouter(defaults: reglagesEnMemoire())
        routeur.open(.portfolio)
        routeur.switchTab(.actions)
        #expect(routeur.route == .portfolio)

        let id = UUID()
        routeur.open(.project(id, .fiche))
        let profondeur = routeur.history.count
        routeur.switchTab(.fiche)
        #expect(routeur.route == .project(id, .fiche))
        #expect(routeur.history.count == profondeur)
    }

    /// La route porte l'onglet demandé : c'est ce qui permet à « Tout voir »
    /// et à la recette `p1d` de désigner un onglet.
    @Test("La route de recette p1d ouvre le projet de la capture sur Pilotage")
    func routeDeRecette() throws {
        let cible = RecetteScreen.ecranProjet.cible
        guard case .fenetrePrincipale(let route) = cible else {
            Issue.record("p1d ne vise pas la fenêtre principale")
            return
        }
        #expect(route == .project(RefonteDemoSeed.portfolioFocusProjectStableID, .pilotage))
    }

    // MARK: - Le montage

    @Test("La route d'un projet monte l'écran à six onglets, plus la fiche seule")
    func routeMonteLEcran() throws {
        let source = try source("OneToOne/Views/Navigation/MainDetailView.swift")
        #expect(source.contains("ProjectScreen(project: projet, tab: onglet)"))
        #expect(!source.contains("ProjectDetailView(project: projet)"))
    }

    @Test("L'écran projet se construit sur le projet de la capture")
    func ecranSeConstruit() throws {
        let semis = try semis()
        let ecran = ProjectScreen(project: semis.projet, tab: .pilotage)
        #expect(ecran.project.code == "P25_193")
        #expect(ecran.tab == .pilotage)
    }

    // MARK: - La fiche complète

    /// La heatmap **n'est pas supprimée** — le tableau de bord l'emploie
    /// encore — mais elle a quitté la fiche projet, remplacée par la tuile
    /// « RYTHME ».
    @Test("La fiche complète a perdu sa heatmap, que le tableau de bord garde")
    func heatmapRetireeDeLaFiche() throws {
        let fiche = try source("OneToOne/Views/DetailsViews.swift")
        #expect(!fiche.contains("MeetingHeatmapView("))
        let barre = try source("OneToOne/Views/Sidebar.swift")
        #expect(barre.contains("MeetingHeatmapView("))
    }

    /// Archiver retire le projet du Portfolio **et** de la barre latérale : il
    /// disparaît de tous les écrans où on le cherchait, et rien ne le signale
    /// une fois le menu refermé. Désarchiver ne fait que le ramener.
    @Test("Archiver demande confirmation, désarchiver non")
    func confirmationDArchivage() throws {
        #expect(ProjectHeader.confirmerLArchivage == "Archiver ce projet ?")
        #expect(ProjectHeader.archiver == "Archiver")
        #expect(ProjectHeader.annuler == "Annuler")
        #expect(ProjectHeader.detailDeLArchivage
                == "Le projet quitte le Portfolio et la barre latérale. "
                 + "Rien n'est supprimé : « Désarchiver » le ramène.")
        #expect(ProjectHeader.confirmerLaSuppression == "Supprimer ce projet ?")
        #expect(ProjectHeader.conserver == "Conserver")

        let source = try source("OneToOne/Views/Project/ProjectScreen.swift")
        // Deux dialogues, et le second n'est armé que pour un projet actif.
        #expect(source.contains("isPresented: $confirmerLArchivage"))
        #expect(source.contains("isPresented: $confirmerLaSuppression"))
        #expect(source.contains("if project.isArchived {\n            basculerLArchivage()"),
                "un projet archivé se désarchive sans question")
    }

    /// « Archiver » et « Supprimer » sont passés dans le menu `···` de
    /// l'en-tête ; « Enregistrer » est descendu dans le corps de la fiche.
    @Test("La fiche complète a perdu sa barre d'outils")
    func toolbarRetiree() throws {
        let fiche = try source("OneToOne/Views/DetailsViews.swift")
        #expect(!fiche.contains("ToolbarItemGroup"))
        #expect(fiche.contains("static let enregistrer = \"Enregistrer\""))
        let ecran = try source("OneToOne/Views/Project/ProjectScreen.swift")
        #expect(ecran.contains("confirmationDialog"))
    }

    // MARK: - Les onglets secondaires

    @Test("Les onglets secondaires portent leurs libellés et leurs états vides")
    func libellesDesOngletsSecondaires() {
        #expect(ProjectMeetingsTab.vide == "Aucune réunion tenue sur ce projet.")
        #expect(ProjectActionsTab.titreOuvertes == "ACTIONS OUVERTES")
        #expect(ProjectActionsTab.titreTerminees == "TERMINÉES")
        #expect(ProjectMailsTab.rattacher == "Rattacher des mails")
        #expect(ProjectDocumentsTab.titre == "PIÈCES JOINTES")
        #expect(ProjectDocumentsTab.ajouter == "Ajouter une pièce jointe")
        #expect(ProjectDocumentsTab.categories == ["DAT", "DIT", "Document"])
    }

    /// L'onglet « Réunions & CR » date à l'année : il montre tout
    /// l'historique, pas les trois réunions du trimestre.
    @Test("L'onglet Réunions date à l'année, la carte de pilotage au jour")
    func datesDesDeuxListes() throws {
        let semis = try semis()
        let reunions = ProjectPilotageBuilder.reunionsDuProjet(
            semis.projet,
            parmi: try semis.contexte.fetch(FetchDescriptor<Meeting>()),
            today: Date())
        #expect(reunions.count == 9)
        let lignes = reunions.map(ProjectMeetingRow.init)
        #expect(lignes.first?.dateLabel.count == 10)      // « 08/09/2026 »
        #expect(semis.etat.meetings.first?.dateLabel.count == 5)   // « 08/09 »
        #expect(lignes.first?.badge == .copil)
    }

    @Test("L'onglet Mails écrit l'expéditeur en entier")
    func mailsEnEntier() throws {
        let semis = try semis()
        let lignes = semis.projet.mails
            .sorted { $0.dateReceived > $1.dateReceived }
            .map(ProjectMailRow.init)
        #expect(lignes.count == 2)
        #expect(lignes[0].sujet == "RE : périmètre v1 — annuaire")
        #expect(lignes[0].meta.hasPrefix("contact@alp.example · "))
    }

    // MARK: - Outillage des réglages

    /// Un `UserDefaults` en mémoire : la suite ne doit pas écrire dans les
    /// réglages de l'utilisateur (correction du lot 2).
    private func reglagesEnMemoire() -> UserDefaults { ReglagesEnMemoire() }
}
