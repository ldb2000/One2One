import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le routeur de navigation de la fenêtre principale (décision **D0**).
///
/// Avant ce lot, la barre latérale était une liste de `NavigationLink` à
/// destination inline (`Views/Sidebar.swift`) : rien ne savait sélectionner un
/// écran par programme, or la palette, les Récents, le fil d'Ariane et
/// `SearchPopover` en ont tous besoin. Le routeur est un état, pas une vue —
/// donc il se teste sans en monter aucune, et il se teste **avant** elles.
/// Un `UserDefaults` **en mémoire**, pour que la suite n'écrive rien dans les
/// préférences réelles de l'utilisateur.
///
/// `UserDefaults(suiteName:)` crée un fichier dans le vrai
/// `~/Library/Preferences/`. Un nom tiré au sort par test en a laissé
/// soixante-cinq derrière lui (constaté le 2026-09-09) ; un nom fixe effacé en
/// fin de test n'y suffit pas non plus, `cfprefsd` réécrivant le fichier après
/// coup. `MainRouter` ne lit et n'écrit qu'une chaîne : la surcharger est ce
/// qui garantit qu'aucun octet ne quitte le processus.
final class ReglagesEnMemoire: UserDefaults {

    private var valeurs: [String: Any] = [:]

    init() { super.init(suiteName: nil)! }

    required init?(coder: NSCoder) { fatalError("inutilisé") }

    override func set(_ value: Any?, forKey defaultName: String) {
        if let value { valeurs[defaultName] = value } else { valeurs.removeValue(forKey: defaultName) }
    }

    override func object(forKey defaultName: String) -> Any? {
        valeurs[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
        valeurs[defaultName] as? String
    }

    override func removeObject(forKey defaultName: String) {
        valeurs.removeValue(forKey: defaultName)
    }
}

@Suite("Routeur de navigation — D0")
@MainActor
struct MainRouterTests {

    /// Un `UserDefaults` jetable : les récents s'y écrivent, et rien n'atteint
    /// le disque.
    private func reglagesJetables() -> UserDefaults {
        ReglagesEnMemoire()
    }

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: - État initial

    @Test("Le routeur s'ouvre sur le tableau de bord, sans histoire")
    func etatInitial() {
        let routeur = MainRouter(defaults: reglagesJetables())
        #expect(routeur.route == .dashboard)
        #expect(routeur.history.isEmpty)
        #expect(routeur.pendingPaletteQuery == nil)
    }

    // MARK: - open / back

    @Test("Ouvrir un écran pousse le précédent dans l'histoire")
    func openPousseLePrecedent() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.open(.portfolio)
        #expect(routeur.route == .portfolio)
        #expect(routeur.history == [.dashboard])

        routeur.open(.atRisk)
        #expect(routeur.route == .atRisk)
        #expect(routeur.history == [.dashboard, .portfolio])
    }

    @Test("Revenir dépile l'histoire et n'y remet pas la route quittée")
    func backDepile() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.open(.portfolio)
        routeur.open(.atRisk)

        routeur.back()
        #expect(routeur.route == .portfolio)
        #expect(routeur.history == [.dashboard])

        routeur.back()
        #expect(routeur.route == .dashboard)
        #expect(routeur.history.isEmpty)
    }

    @Test("Revenir sans histoire ne change rien")
    func backSansHistoire() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.back()
        #expect(routeur.route == .dashboard)
        #expect(routeur.history.isEmpty)
    }

    /// Cliquer deux fois la même entrée de la barre latérale ne doit pas
    /// empiler deux fois le même écran : sinon « revenir » ne bougerait pas.
    @Test("Réouvrir l'écran courant n'empile rien")
    func memeRouteNEmpilePas() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.open(.portfolio)
        routeur.open(.portfolio)
        #expect(routeur.history == [.dashboard])
    }

    @Test("L'histoire est bornée à vingt écrans : le plus ancien tombe")
    func histoireBornee() {
        let routeur = MainRouter(defaults: reglagesJetables())
        #expect(MainRouter.historyLimit == 20)
        // 25 ouvertures distinctes : `searchReports` en donne autant qu'on veut.
        for index in 0..<25 { routeur.open(.searchReports("t\(index)")) }
        #expect(routeur.history.count == MainRouter.historyLimit)
        // Les vingt derniers écrans quittés, le plus ancien en tête.
        #expect(routeur.history.first == .searchReports("t4"))
        #expect(routeur.history.last == .searchReports("t23"))
        #expect(routeur.route == .searchReports("t24"))
    }

    // MARK: - Ouvrir un projet

    @Test("Ouvrir un projet route sur l'onglet Pilotage et l'inscrit aux récents")
    func openProject() throws {
        let contexte = try contexteEnMemoire()
        let reglages = reglagesJetables()
        let routeur = MainRouter(defaults: reglages)

        let projet = Project(code: "P25_193", name: "AE — Services IO / ALP",
                             domain: "ASP", phase: "Design")
        contexte.insert(projet)
        try contexte.save()

        routeur.openProject(projet)
        let id = try #require(projet.stableID)
        #expect(routeur.route == .project(id, .pilotage))
        #expect(routeur.recentProjectIDs == [id])
    }

    @Test("Ouvrir un projet sur un onglet donné respecte l'onglet")
    func openProjectOnglet() throws {
        let contexte = try contexteEnMemoire()
        let routeur = MainRouter(defaults: reglagesJetables())
        let projet = Project(code: "P25_112", name: "ASP — BLOOM", domain: "ASP", phase: "Build")
        contexte.insert(projet)
        try contexte.save()

        routeur.openProject(projet, tab: .actions)
        #expect(routeur.route == .project(try #require(projet.stableID), .actions))
    }

    /// Les projets créés avant l'ajout de `stableID` en portent `nil` :
    /// `ensuredStableID` doit le combler, sinon le routeur ne saurait pas
    /// désigner le projet et l'écran resterait vide.
    @Test("Un projet sans identifiant stable en reçoit un à l'ouverture")
    func openProjectBackfill() throws {
        let contexte = try contexteEnMemoire()
        let routeur = MainRouter(defaults: reglagesJetables())
        let projet = Project(code: "P24_211", name: "RH — Migration GED documentaire",
                             domain: "RH", phase: "Run")
        projet.stableID = nil
        contexte.insert(projet)
        try contexte.save()

        routeur.openProject(projet)
        let id = try #require(projet.stableID)
        #expect(routeur.route == .project(id, .pilotage))
    }

    @Test("Les récents gardent cinq projets, le dernier ouvert en tête")
    func recentsBornes() throws {
        let contexte = try contexteEnMemoire()
        let routeur = MainRouter(defaults: reglagesJetables())
        var projets: [Project] = []
        for index in 0..<7 {
            let projet = Project(code: "P25_0\(index)", name: "Projet \(index)",
                                 domain: "ASP", phase: "Build")
            contexte.insert(projet)
            projets.append(projet)
        }
        try contexte.save()

        for projet in projets { routeur.openProject(projet) }
        let attendus = try projets.suffix(5).reversed().map { try #require($0.stableID) }
        #expect(routeur.recentProjectIDs == attendus)
    }

    // MARK: - Terme en attente pour la palette (lot 3)

    /// `p1c` doit pouvoir ouvrir la palette sur le terme « ged » sans clic. Le
    /// routeur ne connaît pas la palette : il porte le terme, et le lot 3 le
    /// consommera.
    @Test("Le terme en attente de la palette se pose et se consomme une fois")
    func termeEnAttente() {
        let routeur = MainRouter(defaults: reglagesJetables())
        routeur.pendingPaletteQuery = "ged"
        #expect(routeur.consumePendingPaletteQuery() == "ged")
        #expect(routeur.pendingPaletteQuery == nil)
        #expect(routeur.consumePendingPaletteQuery() == nil)
    }

    // MARK: - Aucune suite n'écrit dans les préférences réelles

    /// Les suites qui ouvrent encore une suite `UserDefaults` **nommée**, avec
    /// ce qu'elle sert.
    ///
    /// Une liste d'exceptions nommées, comme celle des raccourcis dupliqués de
    /// `AppShortcutsTests` : les douze fichiers ci-dessous précèdent cette
    /// garde, ils passent tous leur `UserDefaults` à `MeetingScreenModel`, et
    /// les corriger demande un double en mémoire pour **ce** modèle-là — un
    /// chantier à part. Ce qui compte, c'est qu'aucun **nouveau** fichier ne
    /// s'y ajoute.
    ///
    /// Mesuré le 2026-09-09 : `~/Library/Preferences` portait 2 025 plists
    /// `MeetingScreenModelTests.<uuid>.plist`, un par exécution de test depuis
    /// des mois.
    private static let suitesNommeesTolerees: Set<String> = [
        "ActionComposerServiceTests.swift",
        "ActionFromTranscriptCriterionTests.swift",
        "ActionSeamIntegrationTests.swift",
        "ActiveMeetingRegistryTests.swift",
        "CaptureSessionCoordinatorTests.swift",
        "MeetingPlayheadTests.swift",
        "MeetingScreenModelTests.swift",
        "RAGIndexingSweepTests.swift",
        "ReviewStateTests.swift",
        "SessionFullscreenTests.swift",
        "SessionPillTargetTests.swift",
        "WorkshopDockTests.swift",
    ]

    /// Aucun **nouveau** fichier de `Tests/` n'ouvre une suite `UserDefaults`
    /// nommée.
    ///
    /// `UserDefaults(suiteName:)` crée un `.plist` dans le vrai
    /// `~/Library/Preferences/`, que le processus de test **n'efface pas** :
    /// `removePersistentDomain` est réécrit après coup par `cfprefsd`. Deux
    /// suites en ont laissé derrière elles avant d'être corrigées — celle-ci,
    /// soixante-cinq, et `AtRiskViewTests`, quatorze (2026-09-09). La parade
    /// est `ReglagesEnMemoire`, déclarée juste au-dessus.
    ///
    /// Un test de lecture des sources : un `.plist` de trop ne fait échouer
    /// aucune assertion, il encombre le poste de quelqu'un.
    @Test("Aucune nouvelle suite de tests n'ouvre une suite UserDefaults nommée")
    func aucuneSuiteDePreferencesNommee() throws {
        let dossier = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fichiers = try FileManager.default
            .contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(fichiers.count > 100, "chemin du dossier de tests faux : \(fichiers.count) fichiers")
        var coupables: [String] = []
        for fichier in fichiers {
            let nom = fichier.lastPathComponent
            guard !Self.suitesNommeesTolerees.contains(nom) else { continue }
            // Hors commentaires : une garde qui compte ses propres explications
            // se déclenche sur le texte qui la décrit.
            let texte = try String(contentsOf: fichier, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            // `ReglagesEnMemoire` appelle `super.init(suiteName: nil)`, le
            // domaine standard : il n'écrit aucun fichier nouveau.
            let interdits = texte.components(separatedBy: "UserDefaults(suiteName:").count - 1
            let permis = texte.components(separatedBy: "super.init(suiteName: nil)").count - 1
            if interdits > permis { coupables.append(nom) }
        }
        #expect(coupables.isEmpty,
                "ces suites écriraient dans ~/Library/Preferences : \(coupables) — employer ReglagesEnMemoire")
    }

    /// La liste d'exceptions ne survit pas à la correction de ses membres : un
    /// fichier qui n'emploie plus de suite nommée doit en sortir, sinon elle
    /// devient un cimetière que personne ne relit.
    @Test("La liste d'exceptions ne cite que des fichiers encore concernés")
    func exceptionsToujoursJustifiees() throws {
        let dossier = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for nom in Self.suitesNommeesTolerees {
            let fichier = dossier.appendingPathComponent(nom)
            let texte = try String(contentsOf: fichier, encoding: .utf8)
            #expect(texte.contains("UserDefaults(suiteName:"),
                    "\(nom) n'ouvre plus de suite nommée : le retirer de suitesNommeesTolerees")
        }
    }

    // MARK: - Les routes elles-mêmes

    @Test("Deux routes de projet ne se confondent pas par leur seul onglet")
    func routesDistinctes() {
        let id = UUID()
        #expect(MainRoute.project(id, .pilotage) != MainRoute.project(id, .actions))
        #expect(MainRoute.project(id, .pilotage) == MainRoute.project(id, .pilotage))
        #expect(MainRoute.searchReports("ged") != MainRoute.searchReports("GED"))
    }

    @Test("Les six onglets de l'écran projet sont ceux de la capture 1d")
    func ongletsDeLaCapture() {
        #expect(ProjectTab.allCases.map(\.rawValue)
            == ["pilotage", "meetings", "actions", "mails", "documents", "fiche"])
        #expect(ProjectTab.allCases.map(\.label)
            == ["Pilotage", "Réunions & CR", "Actions", "Mails", "Documents", "Fiche complète"])
    }
}
