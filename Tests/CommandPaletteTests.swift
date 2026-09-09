import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import OneToOne

/// La palette `⌘K` et l'écran de recherche dans les CR : les libellés au mot
/// près, les mesures du handoff §1c, et les branchements qu'aucun test de
/// modèle ne couvre.
///
/// Une vue SwiftUI ne s'inspecte pas ; ce qui se vérifie, ce sont ses
/// constantes et ses sources — même approche que `AppShortcutsTests`,
/// `ProjectsSidebarSectionTests` et `PortfolioViewTests`.
@Suite("Palette ⌘K et recherche dans les CR")
@MainActor
struct CommandPaletteTests {

    // MARK: - Lecture des sources

    private static var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8)) ?? ""
    }

    // MARK: - Les libellés de la capture 1c

    @Test("les libellés de la palette sont ceux de la capture, au mot près")
    func libellesDeLaPalette() {
        #expect(PaletteModel.pastilleEsc == "esc")
        // Les deux groupes sont rendus par `.sectionLabel()`, qui met en
        // majuscules : la constante est en casse normale, la capture montre
        // « PROJETS » et « ACTIONS ».
        #expect(PaletteModel.titreProjets == "Projets")
        #expect(PaletteModel.titreActions == "Actions")
        #expect(PaletteModel.titreProjets.uppercased() == "PROJETS")
        #expect(PaletteModel.titreActions.uppercased() == "ACTIONS")
        #expect(PaletteModel.libelleAucunProjet == "Aucun projet")
    }

    @Test("le pied est celui du handoff, et se rend en trois segments")
    func pied() {
        #expect(PaletteModel.pied == "↑↓ naviguer · ↩ ouvrir · ⌘↩ épingler")
        #expect(PaletteModel.piedSegments
                == ["↑↓ naviguer", "↩ ouvrir", "⌘↩ épingler"])
    }

    @Test("les mesures de la carte sont celles du handoff §1c")
    func mesures() {
        #expect(CommandPalette.largeur == 560)
        #expect(CommandPalette.hauteurChamp == 44)
        #expect(CommandPalette.tailleChamp == 15)
        // `0 18px 40px rgba(0,0,0,.16)` : la teinte et le rayon sont les
        // jetons D12, seul le décalage vertical est ici.
        #expect(CommandPalette.ombreY == 18)
        #expect(One2OneToken.paletteShadowRadius == 40)
        // Ligne : `8px 10px`, rayon 7, pastille 9 px, sous-ligne 10,5 pt.
        #expect(PaletteRowMetrics.paddingV == 8)
        #expect(PaletteRowMetrics.paddingH == 10)
        #expect(PaletteRowMetrics.gap == 10)
        #expect(PaletteRowMetrics.tailleLibelle == 13.5)
        #expect(PaletteRowMetrics.tailleSousLigne == 10.5)
        #expect(PaletteRowMetrics.taillePastille == 9)
        #expect(One2OneToken.radiusCard == 7)
        #expect(One2OneToken.radiusPanel == 10)
        // Pied et pastille `esc` : mono 10,5 et 10 pt.
        #expect(CommandPalette.taillePied == 10.5)
        #expect(CommandPalette.taillePastille == 10)
        #expect(CommandPalette.gapPied == 14)
    }

    @Test("la carte emploie les trois jetons de la palette et aucune couleur nue")
    func jetons() {
        let source = Self.source("OneToOne/Views/Palette/CommandPalette.swift")
        #expect(!source.isEmpty, "CommandPalette.swift introuvable")
        #expect(source.contains("One2OneToken.surface"))
        #expect(source.contains("One2OneToken.strongBorder"))
        #expect(source.contains("One2OneToken.paletteShadow"))
        #expect(source.contains("One2OneToken.bgCanvas"))
        // Le surlignage `highlight` est posé par `HighlightedText`, une fois.
        let surlignage = Self.source("OneToOne/Views/Palette/HighlightedText.swift")
        #expect(surlignage.contains("One2OneToken.highlight"))
        #expect(surlignage.contains("ProjectSearch.highlightRanges"))
        // La ligne sélectionnée : `actionBg`, rayon 7.
        let ligne = Self.source("OneToOne/Views/Palette/PaletteRow.swift")
        #expect(ligne.contains("One2OneToken.actionBg"))
        #expect(ligne.contains("One2OneToken.radiusCard"))
        // Aucun littéral de couleur dans les trois fichiers : `One2OneToken`
        // est le seul fichier autorisé à en nommer une (D12).
        for fichier in ["CommandPalette.swift", "PaletteRow.swift", "HighlightedText.swift"] {
            let texte = Self.source("OneToOne/Views/Palette/\(fichier)")
            #expect(!texte.contains("Color(hex:"), "\(fichier) nomme une couleur")
            #expect(!texte.contains("Color.red"), "\(fichier) nomme une couleur")
            #expect(!texte.contains(".opacity(0."), "\(fichier) fabrique une teinte")
        }
    }

    // MARK: - Le surlignage

    @Test("le surlignage porte le fond `highlight` sur chaque occurrence")
    func surlignage() {
        let attribue = HighlightedText.attribue("ASP – Installation nouvelle GED",
                                                terme: "ged")
        let surlignees = attribue.runs.filter { $0.backgroundColor == One2OneToken.highlight }
        #expect(surlignees.count == 1)
        #expect(String(attribue[surlignees[0].range].characters) == "GED")
    }

    @Test("le surlignage plie les accents, comme la correspondance")
    func surlignageAccents() {
        let attribue = HighlightedText.attribue("Refonte des états réglementaires",
                                                terme: "etats")
        let surlignees = attribue.runs.filter { $0.backgroundColor == One2OneToken.highlight }
        #expect(surlignees.count == 1)
        #expect(String(attribue[surlignees[0].range].characters) == "états")
    }

    @Test("deux occurrences sont surlignées deux fois")
    func surlignageMultiple() {
        let attribue = HighlightedText.attribue("GED, encore la ged", terme: "ged")
        let surlignees = attribue.runs.filter { $0.backgroundColor == One2OneToken.highlight }
        #expect(surlignees.count == 2)
    }

    @Test("un terme absent ou vide ne surligne rien, et rend le texte entier")
    func surlignageVide() {
        for terme in ["", "   ", "zzz"] {
            let attribue = HighlightedText.attribue("ASP – Obsolescence VM", terme: terme)
            #expect(attribue.runs.allSatisfy { $0.backgroundColor == nil })
            #expect(String(attribue.characters) == "ASP – Obsolescence VM")
        }
    }

    // MARK: - Les branchements

    @Test("le routeur porte l'ouverture de la palette, et la referme")
    func ouvertureEtFermeture() {
        let routeur = MainRouter(defaults: ReglagesEnMemoire())
        #expect(!routeur.paletteOuverte)
        #expect(routeur.paletteTerme == nil)
        routeur.ouvrirPalette()
        #expect(routeur.paletteOuverte)
        #expect(routeur.paletteTerme == "")
        routeur.fermerPalette()
        #expect(!routeur.paletteOuverte)
        routeur.ouvrirPalette(terme: "ged")
        #expect(routeur.paletteTerme == "ged")
    }

    @Test("le terme en attente de la recette ouvre la palette une seule fois")
    func termeDeRecette() {
        let routeur = MainRouter(defaults: ReglagesEnMemoire())
        routeur.pendingPaletteQuery = RecetteScreen.palette.termeDePalette
        let terme = routeur.consumePendingPaletteQuery()
        #expect(terme == "ged")
        routeur.ouvrirPalette(terme: terme ?? "")
        #expect(routeur.paletteTerme == "ged")
        // Consommé : une seconde ouverture repart vide.
        #expect(routeur.consumePendingPaletteQuery() == nil)
    }

    @Test("le point d'entrée de l'application ouvre la palette au lancement")
    func brancheeAuLancement() {
        let source = Self.source("OneToOne/OneToOneApp.swift")
        #expect(source.contains("CommandPalette(router: mainRouter)"))
        #expect(source.contains("mainRouter.paletteOuverte"))
        #expect(source.contains("consumePendingPaletteQuery()"))
        #expect(source.contains("mainRouter.ouvrirPalette(terme: terme)"))
        // La superposition est posée **avant** `.environment(_:)`, sinon la
        // palette ne verrait pas le routeur de la fenêtre.
        guard let overlay = source.range(of: ".overlay {"),
              let environnement = source.range(of: ".environment(mainRouter)")
        else {
            Issue.record("superposition ou environnement introuvables dans ContentView")
            return
        }
        #expect(overlay.lowerBound < environnement.lowerBound)
    }

    @Test("la palette ouvre le projet par le routeur et crée par le service du lot 2")
    func activation() {
        let source = Self.source("OneToOne/Views/Palette/CommandPalette.swift")
        #expect(source.contains("router.openProject(projet)"))
        #expect(source.contains("ProjectCreation.creer(among: projets,"))
        #expect(source.contains("router.open(.searchReports(model.terme))"))
        #expect(source.contains("router.fermerPalette()"))
        // `⌘↩` n'appelle pas `fermer()`.
        #expect(source.contains("func epingler()"))
        #expect(source.contains("model.basculerEpinglage()"))
    }

    @Test("« Créer » nomme le projet du terme frappé")
    func creationNommee() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let contexte = ModelContext(container)
        let cree = ProjectCreation.creer(among: [], nom: "ged", in: contexte)
        #expect(cree.name == "ged")
        #expect(cree.code == "PXX_001")
        // Un nom blanc retombe sur le défaut : c'est le bouton du Portfolio.
        let sansNom = ProjectCreation.creer(among: [cree], nom: "   ", in: contexte)
        #expect(sansNom.name == ProjectCreation.nomParDefaut)
        let boutonPortfolio = ProjectCreation.creer(among: [cree, sansNom], in: contexte)
        #expect(boutonPortfolio.name == ProjectCreation.nomParDefaut)
    }

    // MARK: - L'écran de recherche dans les CR

    @Test("la route `.searchReports` monte l'écran, plus l'invite du lot 0")
    func routeBranchee() {
        let source = Self.source("OneToOne/Views/Navigation/MainDetailView.swift")
        #expect(source.contains("ReportSearchView(terme: terme)"))
        #expect(!source.contains("les comptes rendus contenant"),
                "l'invite `.searchReports` du lot 0 doit avoir disparu")
    }

    @Test("l'écran de recherche affiche l'en-tête et le sous-titre de la spec")
    func enteteDeLaRecherche() {
        #expect(ReportSearch.titre == "Recherche dans les CR")
        #expect(ReportSearchView.tailleTitre == 17)
        let source = Self.source("OneToOne/Views/Search/ReportSearchView.swift")
        #expect(source.contains("ReportSearch.titre"))
        #expect(source.contains("ReportSearch.sousTitre(reunions:"))
        #expect(source.contains(".plexSans(Self.tailleTitre, .semibold)"))
    }

    @Test("un clic ouvre la réunion par le jeton de lancement existant")
    func ouvertureDeLaReunion() {
        let source = Self.source("OneToOne/Views/Search/ReportSearchView.swift")
        #expect(source.contains("QuickLaunchRouter.shared.pendingToken"))
        #expect(source.contains("OneToOneLaunchToken(meetingID: reunion.ensuredStableID"))
    }

    @Test("l'écran de recherche ne calcule pas dans body (D11)")
    func pasDeCalculDansBody() {
        let source = Self.source("OneToOne/Views/Search/ReportSearchView.swift")
        // Les groupes sont un `@State` rechargé par `onAppear`/`onChange`, pas
        // une propriété calculée relue à chaque image : la recherche traverse
        // `textualContent` de toutes les réunions du store.
        #expect(source.contains("@State private var groupes: [ReportSearchGroup] = []"))
        #expect(source.contains("private func recharger()"))
        #expect(source.contains(".onChange(of: reunions) { recharger() }"))
    }

    // MARK: - Unification de la recherche (D7)

    @Test("les deux filtres historiques passent par ProjectSearch")
    func unificationD7() {
        let popover = Self.source("OneToOne/Views/Menubar/SearchPopover.swift")
        #expect(popover.contains("ProjectSearch."))
        // Le prédicat maison a disparu : c'était le troisième du dépôt.
        #expect(!popover.contains("$0.name.localizedStandardContains(q) || $0.code.localizedStandardContains(q)"))

        let liste = Self.source("OneToOne/Views/MeetingsListView.swift")
        #expect(liste.contains("ProjectSearch."))
        #expect(!liste.contains("p.chefDeProjet.localizedCaseInsensitiveContains(q)"),
                "le prédicat de MeetingsProjectFilterPicker doit avoir migré")
    }
}
