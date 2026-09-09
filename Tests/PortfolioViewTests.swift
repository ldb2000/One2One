import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import OneToOne

/// Les libellés, les mesures et l'état de l'écran Portfolio (capture
/// `1a-portfolio.png`).
///
/// Un écran ne se photographie pas depuis un test ; ce qui s'y vérifie, c'est
/// ce que les vues **exposent** : les libellés au mot près, les mesures du
/// handoff en constantes, et le comportement du modèle d'écran (debounce,
/// facettes, tri, sélection, vues enregistrées). Même approche que
/// `AppShortcutsTests` et `ProjectsSidebarSectionTests`.
@Suite("Écran Portfolio")
@MainActor
struct PortfolioViewTests {

    // MARK: - Outillage

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func modeleSurLeSemis() throws -> (PortfolioModel, ModelContext) {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let modele = PortfolioModel()
        modele.recharger(projects: try contexte.fetch(FetchDescriptor<Project>()),
                         meetings: try contexte.fetch(FetchDescriptor<Meeting>()))
        return (modele, contexte)
    }

    // MARK: - Les libellés de l'en-tête

    @Test("L'en-tête : le titre, le segmenté et le bouton, au mot près")
    func libellesDeLEntete() {
        #expect(PortfolioHeader.titre == "Projets")
        #expect(PortfolioHeader.nouveauProjet == "＋ Nouveau projet")
        #expect(PortfolioModel.Mode.allCases.map(\.libelle) == ["Tableau", "Groupé par entité"])
    }

    @Test("Le sous-titre annonce les actifs, les entités et les archivés")
    func sousTitre() throws {
        let (modele, _) = try modeleSurLeSemis()
        #expect(modele.summary == "62 actifs · 8 entités · 14 archivés")
        #expect(modele.summary.contains("actifs"))
        #expect(modele.summary.contains("entités"))
        #expect(modele.summary.contains("archivés"))
    }

    @Test("Les mesures de l'en-tête sont celles du handoff")
    func mesuresDeLEntete() {
        #expect(PortfolioHeader.hauteur == 48)
        #expect(PortfolioHeader.tailleTitre == 17)
        #expect(PortfolioHeader.tailleSousTitre == 12)
        #expect(PortfolioHeader.tailleBouton == 12)
    }

    // MARK: - Les libellés de la barre de filtres

    @Test("Le champ de recherche porte l'invite de la capture, sur 230 px")
    func champDeRecherche() {
        #expect(PortfolioFilterBar.invite == "Nom, code, sponsor...")
        #expect(PortfolioFilterBar.largeurChamp == 230)
        #expect(PortfolioFilterBar.hauteur == 42)
        #expect(PortfolioFilterBar.tailleChip == 12)
    }

    @Test("Les cinq facettes, dans l'ordre de la capture")
    func facettes() {
        #expect(PortfolioFacet.allCases.map(\.libelle)
                    == ["Entité", "Risque", "Phase", "Statut", "Chef de projet"])
    }

    @Test("Le menu de vues enregistrées, au mot près")
    func menuDeVues() {
        #expect(SavedViewMenu.prefixe == "Vue enregistrée :")
        #expect(SavedViewMenu.aucune == "Aucune")
        #expect(SavedViewMenu.enregistrerLibelle == "Enregistrer la vue actuelle…")
        #expect(SavedViewMenu.supprimerLibelle == "Supprimer cette vue")
        #expect(SavedViewNameSheet.titre == "Enregistrer la vue actuelle")
        #expect(SavedViewNameSheet.valider == "Enregistrer")
    }

    // MARK: - Les libellés du tableau

    @Test("Les huit en-têtes de colonnes, dans l'ordre de la capture")
    func enTetesDeColonnes() {
        #expect(PortfolioSort.Column.allCases.map(\.header)
                    == ["PROJET", "ENTITÉ", "PHASE", "RISQUE", "CHEF DE PROJET",
                        "JALON", "DERNIÈRE RÉU."])
    }

    @Test("Les mesures du tableau sont celles du handoff")
    func mesuresDuTableau() {
        #expect(PortfolioTable.hauteurEntete == 30)
        #expect(PortfolioTable.hauteurLigne == 44)
        // Les six premières largeurs du handoff (`22 | 1fr | 88 | 92 | 88 | 126`).
        #expect(PortfolioTable.largeurPastille == 22)
        #expect(PortfolioTable.largeurEntite == 88)
        #expect(PortfolioTable.largeurPhase == 92)
        #expect(PortfolioTable.largeurRisque == 88)
        #expect(PortfolioTable.largeurChef == 126)
        // Le nom est en 13 pt, le code en mono 10,5 pt.
        #expect(PortfolioTable.tailleNom == 13)
        #expect(PortfolioTable.tailleCode == 10.5)
        // `inkMuted` n'est jamais sous 11,5 pt (contrainte §1.2) — la cellule
        // et l'entité absente l'emploient.
        #expect(PortfolioTable.tailleCellule >= 11.5)
        #expect(PortfolioTable.tailleJalon >= 11)
    }

    @Test("L'état vide dit « Aucun projet ne correspond »")
    func etatVide() {
        #expect(PortfolioTable.aucunResultat == "Aucun projet ne correspond")
        #expect(PortfolioGroupedView.aucunResultat == PortfolioTable.aucunResultat)
    }

    @Test("Le pied dit les lignes affichées sur le total, et rappelle le ⇧-clic")
    func pied() throws {
        let (modele, _) = try modeleSurLeSemis()
        #expect(modele.footer == "62 lignes sur 62 · sélection multiple ⇧-clic pour changer phase, statut ou entité en lot")
        modele.filters = PortfolioFilters(entities: ["ASP"])
        #expect(modele.footer.hasPrefix("15 lignes sur 62"))
        #expect(modele.footer.contains("lignes sur"))
    }

    // MARK: - Les badges

    @Test("Les couples de phase du handoff, et le neutre hors table")
    func couplesDePhase() {
        #expect(PhaseBadge.fond(.cadrage) == One2OneToken.actionBg)
        #expect(PhaseBadge.encre(.cadrage) == One2OneToken.actionInk)
        #expect(PhaseBadge.fond(.design) == One2OneToken.oneOnOneBg)
        #expect(PhaseBadge.encre(.design) == One2OneToken.oneOnOneInk)
        #expect(PhaseBadge.fond(.build) == One2OneToken.workshopBg)
        #expect(PhaseBadge.encre(.build) == One2OneToken.workshop)
        #expect(PhaseBadge.fond(.run) == One2OneToken.okBg)
        #expect(PhaseBadge.encre(.run) == One2OneToken.okDeep)
        // « Réalisation » : neutre, jamais la teinte d'une phase (D14).
        #expect(PhaseBadge.fond(nil) == One2OneToken.surfaceAlt)
        #expect(PhaseBadge.encre(nil) == One2OneToken.ink4)
        #expect(PhaseBadge.taille == 11.5)
    }

    @Test("Les couples de risque : deux accents, « Faible » neutre (D2)")
    func couplesDeRisque() {
        #expect(RiskBadge.fond(.modere) == One2OneToken.warnBg)
        #expect(RiskBadge.encre(.modere) == One2OneToken.warnInk)
        #expect(RiskBadge.fond(.eleve) == One2OneToken.reportBg)
        #expect(RiskBadge.encre(.eleve) == One2OneToken.reportInk)
        #expect(RiskBadge.fond(.critique) == One2OneToken.reportBg)
        #expect(RiskBadge.encre(.critique) == One2OneToken.reportInk)
        // D2 : « Faible » reste `ink4`, pas de vert.
        #expect(RiskBadge.encre(.faible) == One2OneToken.ink4)
        #expect(RiskBadge.fond(.faible) != One2OneToken.okBg)
    }

    @Test("La teinte de la chip de risque vient de la table unique")
    func teinteDeRisqueUnique() {
        for niveau in RiskLevel.allCases {
            #expect(RiskBadge.teinte(niveau) == RiskBadge.niveau(niveau).teinte)
        }
        #expect(RiskBadge.teinte(.modere) == One2OneToken.warn)
        #expect(RiskBadge.teinte(.critique) == One2OneToken.report)
        #expect(RiskBadge.teinte(.faible) == One2OneToken.ink4)
    }

    // MARK: - La barre d'actions en lot

    @Test("Les libellés de la barre en lot sont accentués")
    func libellesDeLaBarreEnLot() {
        #expect(ProjectBatchBar.titre(3) == "3 projets sélectionnés")
        #expect(ProjectBatchBar.titre(1) == "1 projet sélectionné")
        #expect(ProjectBatchBar.toutDeselectionner == "Tout désélectionner")
        #expect(ProjectBatchBar.phaseLibelle == "Phase")
        #expect(ProjectBatchBar.statutLibelle == "Statut")
        #expect(ProjectBatchBar.entiteLibelle == "Entité")
        #expect(ProjectBatchBar.archiver == "Archiver")
        #expect(ProjectBatchBar.supprimer == "Supprimer")
        // Le lot 6 réutilisera le menu Entité sous ce nom.
        #expect(ProjectBatchBar.deplacerVersEntite == "Déplacer vers une entité")
        #expect(ProjectBatchBar.messageSuppression(3).contains("Supprimer 3 projets ?"))
    }

    @Test("La barre latérale monte la même barre et le même service (D15)")
    func barreLateralePartagee() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("OneToOne/Views/Sidebar.swift"),
            encoding: .utf8)
        #expect(source.contains("ProjectBatchBar("))
        #expect(source.contains("ProjectBatchActions."))
        // Les six méthodes privées ont disparu : deux implémentations qui
        // divergent est exactement ce que D15 supprime.
        for ancienne in ["batchUpdate", "batchSetPhase", "batchSetStatus",
                         "batchSetEntity", "batchArchive", "batchDelete"] {
            #expect(!source.contains("func \(ancienne)"),
                    "Sidebar.swift redéclare \(ancienne)")
        }
    }

    /// Le défaut n° 1 de la recette du 2026-09-09 (capture
    /// `recette/lot-2-p1a-v1.png`), et le garde-fou qui l'empêche de revenir.
    ///
    /// `.menuStyle(.borderlessButton)` passe par un bouton AppKit, qui
    /// **extrait** de l'étiquette d'un `Menu` un titre et une image et les
    /// redessine lui-même, image en tête : la pilule en tirets disparaissait et
    /// le chevron sortait **avant** le libellé (« ⌄ Risque » au lieu de
    /// « Risque ⌄ »). Un rendu ne se vérifie pas depuis un test ; le choix de
    /// style, si — même approche que `RefonteTypographieTests` et que
    /// `ProjectsSidebarSectionTests.ordreDeLaBarreLaterale`.
    @Test("Les menus du Portfolio dessinent leur propre étiquette, chevron après le libellé")
    func menusDessinesAlaMain() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OneToOne/Views/Portfolio")
        for fichier in ["PortfolioFilterBar.swift", "SavedViewMenu.swift", "ProjectBatchBar.swift"] {
            let source = try String(contentsOf: racine.appendingPathComponent(fichier),
                                    encoding: .utf8)
            // Le style fautif ne doit plus être **appliqué** (il reste cité en
            // commentaire, pour dire pourquoi).
            #expect(!source.contains(".menuStyle(.borderlessButton)"),
                    "\(fichier) applique encore .borderlessButton : le chevron repasserait devant le libellé")
            #expect(source.contains(".menuStyle(.button)"), "\(fichier)")
            #expect(source.contains(".menuIndicator(.hidden)"), "\(fichier)")
            #expect(source.contains(".buttonStyle(.plain)"), "\(fichier)")
        }

        // Dans une étiquette de chip, le libellé précède le chevron : c'est
        // l'ordre d'écriture qui fait l'ordre à l'écran, une fois le style
        // AppKit écarté.
        let barre = try String(
            contentsOf: racine.appendingPathComponent("PortfolioFilterBar.swift"),
            encoding: .utf8)
        let texte = try #require(barre.range(of: "Text(libelle)"))
        let chevron = try #require(barre.range(of: "Image(systemName: \"chevron.down\")"))
        #expect(texte.lowerBound < chevron.lowerBound,
                "le chevron est écrit avant le libellé de la chip")
        // La pilule est bien en tirets, au jeton du handoff.
        #expect(barre.contains("One2OneToken.dashedBorder"))
        #expect(barre.contains("dash: [3, 2]"))
        #expect(PortfolioFilterBar.tailleChevron == 9)
    }

    @Test("« Vue enregistrée : » est en inkMuted, le nom en action")
    func teintesDuMenuDeVues() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("OneToOne/Views/Portfolio/SavedViewMenu.swift"),
            encoding: .utf8)
        #expect(source.contains("One2OneToken.inkMuted"))
        #expect(source.contains("One2OneToken.action"))
        // Le préfixe est à 12 pt : `inkMuted` n'est jamais sous 11,5 pt (§1.2).
        #expect(SavedViewMenu.taille >= 11.5)
    }

    @Test("`ProjectListView` est supprimée (D16) et n'a plus d'appelant")
    func projetListViewSupprimee() {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(
            atPath: racine.appendingPathComponent("OneToOne/Views/ProjectListView.swift").path))
    }

    // MARK: - L'en-tête d'entité du mode groupé (lot 6)

    @Test("L'en-tête d'un groupe ouvre l'entité, sauf « Sans entité »")
    func enTeteDeGroupeCliquable() {
        // La fiche d'une entité était atteinte par l'arbre de la barre
        // latérale, retiré au lot 6 (variante 2a). Le seul chemin restant est
        // l'en-tête du mode « Groupé par entité » — c'est aussi le premier
        // appelant de `MainRoute.entity`, créée au lot 0 sans destination.
        #expect(PortfolioGroupedView.estCliquable("ASP"))
        #expect(!PortfolioGroupedView.estCliquable(PortfolioGroupedView.sansEntite))
        // Le libellé du groupe des orphelins vient de `PortfolioBuilder` : les
        // deux doivent rester le même mot.
        #expect(PortfolioGroupedView.sansEntite == "Sans entité")
    }

    @Test("Le nom d'un groupe se résout en entité du store")
    func resolutionDeLEntiteDuGroupe() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let entites = try contexte.fetch(FetchDescriptor<Entity>())
        let asp = try #require(PortfolioBuilder.entite(nommee: "ASP", parmi: entites))
        #expect(asp.name == "ASP")
        // Le groupe des orphelins n'est pas une entité, et un nom inconnu non
        // plus : la vue ne route pas plutôt que de router n'importe où.
        #expect(PortfolioBuilder.entite(nommee: PortfolioGroupedView.sansEntite,
                                        parmi: entites) == nil)
        #expect(PortfolioBuilder.entite(nommee: "Entité fantôme", parmi: entites) == nil)
    }

    @Test("Le Portfolio est le seul appelant de la route `entity`")
    func routeEntiteBranchee() {
        let vue = Self.source("OneToOne/Views/Portfolio/PortfolioView.swift")
        #expect(vue.contains("MainRoute.entity("),
                "l'en-tête d'entité doit ouvrir la fiche de l'entité")
        let groupee = Self.source("OneToOne/Views/Portfolio/PortfolioGroupedView.swift")
        #expect(groupee.contains("ouvrirEntite"))
    }

    // MARK: - Le modèle d'écran

    @Test("Le modèle recalcule les lignes, le groupement et le sous-titre")
    func rechargement() throws {
        let (modele, _) = try modeleSurLeSemis()
        #expect(modele.rows.count == 62)
        #expect(modele.filtered.count == 62)
        #expect(modele.groupes.count == 8)
        #expect(modele.mode == .tableau)
        #expect(modele.sort == .parDefaut)
        #expect(modele.selection.isEmpty)
    }

    @Test("Changer une facette refiltre sans relire le store")
    func facetteRefiltre() throws {
        let (modele, _) = try modeleSurLeSemis()
        modele.basculer("ASP", dans: .entity)
        #expect(modele.filters.entities == ["ASP"])
        #expect(modele.filtered.count == 15)
        #expect(modele.rows.count == 62)
        // Rebasculer la même valeur la retire.
        modele.basculer("ASP", dans: .entity)
        #expect(modele.filters.entities.isEmpty)
        #expect(modele.filtered.count == 62)
    }

    @Test("Le seuil de risque se pose et s'annule d'un même clic")
    func seuilDeRisque() throws {
        let (modele, _) = try modeleSurLeSemis()
        modele.basculer("Modéré", dans: .risk)
        #expect(modele.filters.riskAtLeast == "Modéré")
        #expect(modele.actives(.risk) == ["Modéré"])
        modele.basculer("Modéré", dans: .risk)
        #expect(modele.filters.riskAtLeast == nil)
    }

    @Test("La croix d'une chip vide sa facette et rien d'autre")
    func croixDeChip() throws {
        let (modele, _) = try modeleSurLeSemis()
        modele.filters = PortfolioFilters(entities: ["ASP"], phases: ["Build"])
        modele.effacer(.entity)
        #expect(modele.filters.entities.isEmpty)
        #expect(modele.filters.phases == ["Build"])
    }

    @Test("Le tri bascule de sens sur la même colonne, repart croissant sur une autre")
    func triAuClic() throws {
        let (modele, _) = try modeleSurLeSemis()
        modele.sort = PortfolioSort(column: .name, ascending: false)
        #expect(!modele.sort.ascending)
        #expect(modele.filtered.first?.name == modele.rows
                    .map(\.name).max { $0.localizedStandardCompare($1) == .orderedAscending })
        modele.sort = PortfolioSort(column: .entity, ascending: true)
        #expect(modele.filtered.first?.entity == "ASP")
    }

    @Test("Le champ de recherche est débouncé à 250 ms")
    func debounce() async throws {
        #expect(PortfolioModel.debounceRecherche == 250_000_000)
        let (modele, _) = try modeleSurLeSemis()
        modele.rechercher("netserver")
        // Immédiatement après la frappe, le filtre n'a pas encore bougé.
        #expect(modele.champDeRecherche == "netserver")
        #expect(modele.filters.text.isEmpty)
        // Puis il bouge. L'attente est **bornée mais patiente** : la suite
        // complète charge la machine, et un `sleep` de 450 ms y a déjà rendu ce
        // test intermittent. Ce qui se vérifie est l'ordre des deux états, pas
        // la milliseconde.
        var restant = 40
        while modele.filters.text.isEmpty && restant > 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            restant -= 1
        }
        #expect(modele.filters.text == "netserver")
        #expect(modele.filtered.map(\.code) == ["P25_121"])
        // Vider s'applique tout de suite : attendre pour revoir le tableau se
        // sent.
        modele.rechercher("")
        #expect(modele.filters.text.isEmpty)
        #expect(modele.filtered.count == 62)
    }

    @Test("Les menus de facettes proposent toutes les valeurs, même filtré")
    func valeursDesMenusHorsFiltre() throws {
        let (modele, _) = try modeleSurLeSemis()
        modele.basculer("ASP", dans: .entity)
        #expect(modele.valeurs(de: .entity).count == 8,
                "filtrer sur ASP interdirait de changer d'entité")
    }

    @Test("La sélection multiple retient des identités et se purge du disparu")
    func selectionMultiple() throws {
        let (modele, contexte) = try modeleSurLeSemis()
        let ligne = try #require(modele.filtered.first { $0.code == "P25_112" })
        modele.basculerSelection(ligne.id)
        #expect(modele.selection == [ligne.id])
        #expect(modele.projetsSelectionnes.map(\.code) == ["P25_112"])
        modele.basculerSelection(ligne.id)
        #expect(modele.selection.isEmpty)

        // Un projet supprimé quitte la sélection au rechargement suivant.
        modele.basculerSelection(ligne.id)
        let projet = try #require(modele.projet(ligne))
        ProjectBatchActions.delete([projet], in: contexte)
        modele.recharger(projects: try contexte.fetch(FetchDescriptor<Project>()),
                         meetings: try contexte.fetch(FetchDescriptor<Meeting>()))
        #expect(modele.selection.isEmpty)
    }

    @Test("Une ligne se résout en projet, pour router et pour agir en lot")
    func resolutionDeLigne() throws {
        let (modele, _) = try modeleSurLeSemis()
        let ligne = try #require(modele.filtered.first { $0.code == "P25_193" })
        #expect(modele.projet(ligne)?.code == "P25_193")
        #expect(ligne.stableID == RefonteDemoSeed.portfolioFocusProjectStableID)
    }

    // MARK: - Vues enregistrées

    @Test("Enregistrer, appliquer puis supprimer une vue")
    func vuesEnregistrees() throws {
        let (modele, contexte) = try modeleSurLeSemis()
        modele.basculer("ASP", dans: .entity)
        modele.sort = PortfolioSort(column: .risk, ascending: false)
        let vue = PortfolioSavedViewStore.enregistrer(modele.vueCourante(nommee: "Mes projets ASP"),
                                                      in: contexte)
        let reglages = try contexte.fetch(FetchDescriptor<AppSettings>())
        #expect(PortfolioSavedViewStore.vues(reglages.canonicalSettings).map(\.name)
                    == ["Mes projets ASP"])

        // La vue rejouée rend exactement les mêmes filtres et le même tri.
        modele.filters = .aucun
        modele.sort = .parDefaut
        modele.appliquer(vue)
        #expect(modele.filters.entities == ["ASP"])
        #expect(modele.sort == PortfolioSort(column: .risk, ascending: false))
        #expect(modele.vueActive == vue.id)
        #expect(modele.filtered.count == 15)

        PortfolioSavedViewStore.supprimer(vue.id, in: contexte)
        #expect(PortfolioSavedViewStore.vues(
            try contexte.fetch(FetchDescriptor<AppSettings>()).canonicalSettings).isEmpty)
    }

    @Test("Réenregistrer une vue de même identifiant la remplace")
    func vueIdempotente() throws {
        let contexte = try contexteEnMemoire()
        let id = UUID()
        PortfolioSavedViewStore.enregistrer(
            PortfolioSavedView(id: id, name: "Un", filters: PortfolioFilters(entities: ["ASP"])),
            in: contexte)
        PortfolioSavedViewStore.enregistrer(
            PortfolioSavedView(id: id, name: "Deux", filters: PortfolioFilters(entities: ["RH"])),
            in: contexte)
        let vues = PortfolioSavedViewStore.vues(
            try contexte.fetch(FetchDescriptor<AppSettings>()).canonicalSettings)
        #expect(vues.count == 1)
        #expect(vues.first?.name == "Deux")
        #expect(vues.first?.filters.entities == ["RH"])
    }

    @Test("Toucher une facette désactive la vue enregistrée affichée")
    func facetteDesactiveLaVue() throws {
        let (modele, _) = try modeleSurLeSemis()
        modele.appliquer(PortfolioSavedView(name: "Mes projets ASP",
                                            filters: PortfolioFilters(entities: ["ASP"])))
        #expect(modele.vueActive != nil)
        modele.basculer("Build", dans: .phase)
        #expect(modele.vueActive == nil)
    }

    // MARK: - Recette p1a

    @Test("Seul `p1a` porte une vue enregistrée, et c'est « Mes projets ASP »")
    func vueDeRecette() {
        for ecran in RecetteScreen.allCases where ecran != .portefeuille {
            #expect(ecran.vueEnregistreeDeRecette == nil, "\(ecran.rawValue) en porte une")
        }
        let vue = RecetteScreen.portefeuille.vueEnregistreeDeRecette
        #expect(vue?.name == "Mes projets ASP")
        #expect(vue?.filters.entities == ["ASP"])
        #expect(vue?.sort == .parDefaut)
        #expect(vue?.id == RecetteScreen.idVueEnregistree)
        // L'écran de recette du portefeuille ouvre bien la route du Portfolio.
        #expect(RecetteScreen.portefeuille.cible == .fenetrePrincipale(.portfolio))
    }

    @Test("La vue en attente du routeur ne s'applique qu'une fois")
    func vueEnAttente() {
        // `ReglagesEnMemoire` (cf. `MainRouterTests`) : une suite nommée écrirait
        // un fichier dans les préférences réelles de l'utilisateur.
        let routeur = MainRouter(defaults: ReglagesEnMemoire())
        #expect(routeur.consumePendingPortfolioSavedView() == nil)
        routeur.pendingPortfolioSavedView = RecetteScreen.idVueEnregistree
        #expect(routeur.consumePendingPortfolioSavedView() == RecetteScreen.idVueEnregistree)
        #expect(routeur.consumePendingPortfolioSavedView() == nil)
    }

    @Test("L'état de recette rend les huit projets que la capture nomme")
    func etatDeRecette() throws {
        let (modele, _) = try modeleSurLeSemis()
        let vue = try #require(RecetteScreen.portefeuille.vueEnregistreeDeRecette)
        modele.appliquer(vue)
        for code in ["P25_112", "P25_193", "P25_087", "P25_140",
                     "P25_155", "P25_061", "P25_099", "P25_121"] {
            #expect(modele.filtered.contains { $0.code == code }, "\(code) absent de l'écran p1a")
        }
        // Tri PROJET ↑, comme la capture l'indique.
        #expect(modele.sort == PortfolioSort(column: .name, ascending: true))
        #expect(modele.filtered.map(\.name)
                    == modele.filtered.map(\.name)
                        .sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    // MARK: - Le Portfolio vierge des écrans de recette

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    private static var racineDuDepot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racineDuDepot.appendingPathComponent(chemin),
                     encoding: .utf8)) ?? ""
    }

    @Test("seul p1a photographie une vue enregistrée ; les autres écrans de la fenêtre principale exigent un tableau vierge")
    func portfolioViergeParEcran() {
        for ecran in RecetteScreen.allCases {
            switch ecran.cible {
            case .fenetrePrincipale:
                #expect(ecran.portfolioVierge == (ecran != .portefeuille),
                        "\(ecran.rawValue) : vierge attendu sauf pour p1a")
            default:
                // Un écran de réunion n'affiche pas le Portfolio : il n'a rien
                // à en dire, et surtout rien à y remettre à zéro.
                #expect(!ecran.portfolioVierge, "\(ecran.rawValue) n'ouvre pas le Portfolio")
            }
        }
        #expect(RecetteScreen.palette.portfolioVierge)
        #expect(!RecetteScreen.portefeuille.portfolioVierge)
    }

    @Test("la consigne de remise à zéro se consomme une seule fois")
    func consigneDeRemiseAZero() {
        let routeur = MainRouter(defaults: ReglagesEnMemoire())
        #expect(!routeur.consumePendingPortfolioReset())
        routeur.pendingPortfolioReset = true
        #expect(routeur.consumePendingPortfolioReset())
        // Consommée : un second affichage du Portfolio garde les filtres que
        // l'utilisateur y aura posés entretemps.
        #expect(!routeur.consumePendingPortfolioReset())
    }

    @Test("réinitialiser efface le texte, les filtres et la vue active")
    func reinitialiser() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())

        let model = PortfolioModel()
        model.recharger(projects: projets, meetings: reunions)
        let toutes = model.filtered.count

        // L'état exact de la capture `p1c` fautive : « ASP » dans le champ,
        // quinze lignes, et une vue appliquée par-dessus.
        model.appliquer(PortfolioSavedView(name: "Mes projets ASP",
                                           filters: PortfolioFilters(entities: ["ASP"]),
                                           sort: PortfolioSort(column: .entity, ascending: false)))
        model.filters.text = "ASP"
        model.recharger(projects: projets, meetings: reunions)
        #expect(model.filtered.count < toutes)
        #expect(model.vueActive != nil)

        model.reinitialiser()
        model.recharger(projects: projets, meetings: reunions)
        #expect(model.champDeRecherche.isEmpty)
        #expect(model.filters == .aucun)
        #expect(model.vueActive == nil)
        #expect(model.sort == .parDefaut)
        #expect(model.filtered.count == toutes)
    }

    @Test("l'écran de recette pose la consigne, et le Portfolio l'applique")
    func consigneBranchee() {
        let app = Self.source("OneToOne/OneToOneApp.swift")
        #expect(app.contains("mainRouter.pendingPortfolioReset = ecran.portfolioVierge"))
        let vue = Self.source("OneToOne/Views/Portfolio/PortfolioView.swift")
        #expect(vue.contains("router.consumePendingPortfolioReset()"))
        #expect(vue.contains("model.reinitialiser()"))
    }
}
