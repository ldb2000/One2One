import SwiftUI
import SwiftData
import AppKit
import Combine
import CoreSpotlight

/// Point d'entrée de l'app. Construit le `ModelContainer` SwiftData (avec
/// récupération destructive si la migration échoue) et déclare les scènes :
/// fenêtre principale, fenêtre 1to1-meeting et fenêtre de préparation.
@main
struct OneToOneApp: App {
    /// Container partagé pour les déclencheurs hors hiérarchie SwiftUI
    /// (AppIntent perform, Carbon hotkey callback). Initialisé dans `init()`.
    static var sharedContainer: ModelContainer!

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer

    init() {
        // Fontes IBM Plex embarquées enregistrées avant la première image
        // dessinée. `PlexFont.isInstalled` le referait au premier usage, mais un
        // enregistrement tardif ferait clignoter la typographie.
        PlexFont.ensureRegistered()

        // Store dédié sous `Application Support/OneToOne/OneToOne.store` :
        // évite la collision avec `default.store` (utilisé par d'autres libs
        // CoreData qui partagent ce nom par défaut) et garantit la persistance
        // continue des données métier (Project, Meeting, Collaborator…).
        let storeDir = URL.applicationSupportDirectory.appending(path: "OneToOne", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appending(path: "OneToOne.store")

        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: OneToOneMigrationPlan.self,
                configurations: configuration
            )
            Self.sharedContainer = container
        } catch {
            // Migration impossible — sauvegarde le store cassé puis recrée
            // un store vide. ⚠️ destructif, n'arrive que si la migration
            // SwiftData échoue (schéma fondamentalement incompatible).
            print("SwiftData schema migration failed, backing up store: \(error)")
            let backupURL = storeDir.appending(path: "OneToOne.store.broken-\(Int(Date().timeIntervalSince1970))")
            for suffix in ["", "-wal", "-shm"] {
                let fileURL = suffix.isEmpty
                    ? storeURL
                    : storeURL.deletingLastPathComponent().appending(path: "OneToOne.store\(suffix)")
                let dst = suffix.isEmpty
                    ? backupURL
                    : backupURL.deletingLastPathComponent().appending(path: "\(backupURL.lastPathComponent)\(suffix)")
                try? FileManager.default.moveItem(at: fileURL, to: dst)
            }
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: OneToOneMigrationPlan.self,
                    configurations: configuration
                )
                Self.sharedContainer = container
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    @StateObject private var router = QuickLaunchRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(router)
                // Spec §2.6 : le mode séance remplace **tout** le contenu de
                // la fenêtre, barre du haut comprise. La racine est donc le
                // seul endroit qui puisse le monter (cf. `sessionFullscreenHost`).
                .sessionFullscreenHost()
                // ⚠️ La fenêtre principale **ne reçoit pas** l'enveloppe de
                // taille de la fenêtre de réunion : son contenu est un
                // `NavigationSplitView`, qui borne lui-même ses colonnes, et un
                // plancher constant l'empêcherait de rouvrir plus petite que ce
                // plancher. Sa taille est celle que l'utilisateur lui a laissée
                // (cf. `MainWindowSizing`).
                .background(MainWindowFrameRestorer())
        }
        .modelContainer(container)
        .defaultSize(width: MainWindowSizing.defaultWidth,
                     height: MainWindowSizing.defaultHeight)
        .commands { MeetingCommands() }

        WindowGroup(id: "1to1-meeting", for: OneToOneLaunchToken.self) { $token in
            OneToOneMeetingWindowContent(token: token)
                .preferredColorScheme(.light)
                .environmentObject(router)
                .sessionFullscreenHost()
        }
        .modelContainer(container)

        WindowGroup(id: "prep-standalone", for: PrepWindowToken.self) { $token in
            if let t = token {
                PrepWindowView(token: t)
                    .preferredColorScheme(.light)
            }
        }
        .modelContainer(container)
    }
}

/// Vue racine : `NavigationSplitView` (sidebar + dashboard) qui orchestre
/// au lancement la réparation du store, l'indexation Spotlight, les hotkeys
/// globaux et le nettoyage audio automatique.
struct ContentView: View {
    /// Le routeur de la fenêtre principale (décision **D0**). Il remplace
    /// `selectedTab`, qui était mort : rien ne l'écrivait ni ne le lisait, et
    /// aucune destination n'était atteignable par programme.
    ///
    /// `MainRouter.shared` et non une instance locale : `MenuBarController` est
    /// un `NSObject` hors hiérarchie SwiftUI, il ne peut pas lire
    /// l'environnement, et c'est lui qui ouvre un projet depuis la recherche
    /// du menu système.
    private let mainRouter = MainRouter.shared
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var router: QuickLaunchRouter
    @State private var didRunDataRepair = false
    @State private var showMeetingPicker: Bool = false
    /// `.onAppear` peut se déclencher plusieurs fois : le semis de recette ne
    /// doit pas rouvrir la réunion à chaque fois.
    @State private var didSeedRefonteDemo = false

    var body: some View {
        NavigationSplitView {
            MainSidebarView()
                .focusSection()
                // Sans largeur déclarée, SwiftUI ramène la colonne à ~147 px et
                // les entrées s'y coupent (« Tableau d… », « Suivi man… ») : sa
                // position de séparateur est enregistrée sous la même clé
                // instable que le cadre de la fenêtre, elle ne peut donc pas
                // être restaurée, et c'est cette largeur idéale qui sert de
                // repli. **250 px** depuis la refonte de la gestion des projets
                // (décision **D13**) : c'est la largeur des captures 2a et 2b,
                // et la section « Projets » du lot 1 ne tient pas dans 190.
                .navigationSplitViewColumnWidth(min: 170, ideal: 250, max: 320)
        } detail: {
            MainDetailView()
                .focusSection()
        }
        // La palette `⌘K` (décision **D1**) : une couche par-dessus les deux
        // colonnes, posée **avant** `.environment(_:)` pour que le routeur
        // qu'elle lit soit celui de la fenêtre — l'ordre des modificateurs
        // décide de ce qu'une superposition voit.
        .overlay {
            if mainRouter.paletteOuverte {
                CommandPalette(router: mainRouter)
            }
        }
        .environment(mainRouter)
        .onAppear {
            // Indispensable quand l'app est lancée via swift run :
            // sans ça, l'app reste un processus "accessory" qui ne reçoit
            // pas les événements clavier.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // Forcer la fenêtre principale comme key window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            repairStoreIfNeeded()
            reindexSpotlight()

            // Re-index Spotlight when app is about to terminate
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                reindexSpotlight()
            }

            registerHotkeys()
            maybeRunAutoCleanup()
            runRAGIndexingSweep()
            maybeSeedRefonteDemo()
            mainRouter.ouvrirLaPaletteEnAttente()

            NotificationCenter.default.addObserver(
                forName: .collaboratorHotkeysChanged,
                object: nil,
                queue: .main
            ) { _ in
                registerHotkeys()
            }

            NotificationCenter.default.addObserver(
                forName: .openPrepWindow,
                object: nil,
                queue: .main
            ) { note in
                if let token = note.userInfo?["token"] as? PrepWindowToken {
                    Task { @MainActor in
                        openWindow(id: "prep-standalone", value: token)
                    }
                }
            }
        }
        // Filet de la recette `p1c` : si le terme est posé **après** le premier
        // `onAppear` — ordre que rien ne garantit, `maybeSeedRefonteDemo` étant
        // gardé par un `@State` —, la palette s'ouvre quand même. L'opération
        // consomme le terme, donc elle ne peut pas boucler.
        .onChange(of: mainRouter.pendingPaletteQuery) { _, _ in
            mainRouter.ouvrirLaPaletteEnAttente()
        }
        .onReceive(router.$pendingToken.compactMap { $0 }) { token in
            openWindow(id: "1to1-meeting", value: token)
            // Drain so the same token doesn't fire twice on view remount.
            _ = router.consumePendingToken()
        }
        .sheet(isPresented: $showMeetingPicker) {
            CalendarMeetingPicker { meeting in
                router.pendingToken = OneToOneLaunchToken(
                    meetingID: meeting.ensuredStableID,
                    autoStartRecording: false
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCalendarMeetingPicker)) { _ in
            showMeetingPicker = true
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            QuickLaunchURLHandler.handle(activity: activity,
                                         router: router,
                                         context: context)
        }
    }

    /// Nom de la variable d'environnement qui déclenche le semis du jeu de
    /// démonstration de la refonte au démarrage. Posée par
    /// `Scripts/recette-run.sh --seed`.
    static let seedDemoEnvironmentKey = "ONETOONE_SEED_DEMO"

    /// Nom de la variable d'environnement qui choisit **quel écran** de la
    /// refonte s'ouvre : un code de capture (`1a`, `1c`, `2a`, `2b`, `6a`…),
    /// interprété par `RecetteScreen`. Sans elle, c'est le cockpit de
    /// `1a-cockpit.png`, comme avant les lots 11 et 12.
    ///
    /// Une variable et non un item de menu par écran : la recette visuelle
    /// doit être reproductible sans clic, et ni l'entretien de démonstration
    /// ni la planche d'atelier ne sont atteignables autrement qu'à la souris
    /// depuis la liste des réunions.
    ///
    /// **Un seul crochet.** Les lots 11 et 12 avaient posé deux variables pour
    /// le même besoin (`ONETOONE_SEED_DEMO_SCREEN=2a` et
    /// `ONETOONE_SEED_OPEN=1to1`) ; `ONETOONE_SEED_OPEN` a disparu à
    /// l'intégration de la vague 5.
    static let seedDemoScreenEnvironmentKey = "ONETOONE_SEED_DEMO_SCREEN"

    /// Sème et ouvre la réunion de démonstration quand la variable
    /// `ONETOONE_SEED_DEMO` vaut `1`.
    ///
    /// Pourquoi une variable d'environnement et non un réglage : la recette
    /// visuelle doit être reproductible sans clic. Le semis est déjà
    /// disponible dans le menu **Réunion** ; ici il est simplement automatique
    /// pour un lancement de recette, dans un `HOME` jetable
    /// (cf. `Scripts/recette-run.sh`).
    ///
    /// Aucune garde `#if DEBUG` : le bundle de recette est un **build
    /// release** — c'est justement celui qu'on veut regarder. La garde utile
    /// est ailleurs : sans la variable, rien ne se passe, et
    /// `RefonteDemoSeed.seed` est idempotent.
    @MainActor
    private func maybeSeedRefonteDemo() {
        guard ProcessInfo.processInfo.environment[Self.seedDemoEnvironmentKey] == "1",
              !didSeedRefonteDemo else { return }
        didSeedRefonteDemo = true

        guard let ecran = RecetteScreen.from(
            environment: ProcessInfo.processInfo.environment[Self.seedDemoScreenEnvironmentKey])
        else {
            // Sans code d'écran, rien ne change : la réunion de
            // `1a-cockpit.png`, au mode qu'elle a mémorisé.
            let reunion = RefonteDemoSeed.seed(in: context)
            router.pendingToken = OneToOneLaunchToken(meetingID: reunion.ensuredStableID,
                                                      autoStartRecording: false)
            return
        }
        ouvrirEcranDeRecette(ecran)
    }

    /// Sème ce dont l'écran de recette a besoin, puis l'ouvre au bon mode.
    ///
    /// Tous les semis sont appelés, et **une seule fois chacun** : ils sont
    /// idempotents et se complètent (le lot 5 les décisions horodatées, le
    /// lot 6 les ressources, le lot 7 les captures, le lot 11 les engagements
    /// de la séance 2a, le lot 12 les dates et les résumés de 2b, le lot 13 les
    /// quatre livrables de 5a). Les
    /// distribuer écran par écran demanderait de savoir, pour chaque capture,
    /// de quel lot vient chaque pixel — et se tromperait.
    @MainActor
    private func ouvrirEcranDeRecette(_ ecran: RecetteScreen) {
        // Fenêtre principale (décision **D6**) : le portefeuille de
        // démonstration, puis une route — **aucune** fenêtre de réunion. Les
        // semis de réunion ne sont pas appelés : ils n'ont rien à voir avec le
        // Portfolio, et ouvriraient une seconde fenêtre par-dessus la capture.
        if case .fenetrePrincipale(let route) = ecran.cible {
            let focus = RefonteDemoSeed.seedPortfolio(in: context)
            mainRouter.pendingPaletteQuery = ecran.termeDePalette
            prereplirLesRecents(ecran.codesDeProjetsRecents)
            // Une capture ne doit pas dépendre de celle qui l'a précédée : les
            // écrans qui ne photographient pas de vue enregistrée exigent un
            // Portfolio vierge, quoi qu'une instance laissée ouverte ou un
            // home réutilisé lui ait laissé.
            mainRouter.pendingPortfolioReset = ecran.portfolioVierge
            poserLaVueEnregistree(ecran.vueEnregistreeDeRecette)
            mainRouter.open(routeDeRecette(route, focus: focus))
            return
        }

        let demonstration = RefonteDemoSeed.seedLot5(in: context)
        _ = RefonteDemoSeed.seedLot6(in: context)
        _ = RefonteDemoSeed.seedLot7(in: context)
        let seance = RefonteDemoSeed.seedLot11(in: context)
        let fils = RefonteDemoSeed.seedLot12(in: context)
        let seanceSubie = RefonteDemoSeed.seedLot13(in: context)

        let cible: Meeting?
        switch ecran.cible {
        case .demonstration:
            cible = demonstration
        case .entretienMene:
            // `seedLot11` rend la séance de la capture ; le repli passe par le
            // fil, parce qu'un fil sans participant ne rend rien.
            cible = seance?.meeting ?? OneOnOneThreadStore.allMeetings(of: fils.manager).last
        case .entretienSubi:
            // `seedLot13` rend la séance de la capture 5a ; même repli par le
            // fil que pour l'entretien mené.
            cible = seanceSubie?.meeting
                ?? OneOnOneThreadStore.allMeetings(of: fils.collaborator).last
        case .atelier:
            // `seedWorkshopSession` et non `seedWorkshop` : chaque lot
            // enveloppe le semis du précédent, et les **deux** points d'entrée
            // (ici et `MeetingCommands`) doivent semer la même chose — sinon
            // la capture `6a` de recette montrerait l'atelier du lot 16, sans
            // les objets annotés du lot 17 ni les légendes du lot 18. Le plus
            // complet enveloppe les autres, et reste idempotent.
            cible = RefonteDemoSeed.seedWorkshopSession(in: context)
        case .fenetrePrincipale:
            // Traité plus haut, avant les semis de réunion. Le cas est ici pour
            // que le `switch` reste total : c'est lui, et non un `default`, qui
            // fera parler le compilateur au prochain écran ajouté.
            return
        }
        guard let cible else { return }

        // Le mode vit dans `UserDefaults`, par réunion : l'y écrire **avant**
        // l'ouverture est le seul moyen de l'imposer sans clic, et il survit à
        // la relecture que fait `MeetingScreenModel.attach`.
        UserDefaults.standard.set(ecran.mode.rawValue,
                                  forKey: MeetingScreenModel.modeKey(for: cible.ensuredStableID))
        router.pendingToken = OneToOneLaunchToken(meetingID: cible.ensuredStableID,
                                                  autoStartRecording: false)
    }

    /// Inscrit dans les récents les projets que l'écran de recette demande.
    ///
    /// La sous-section « RÉCENTS » de la capture `2b` est un **état de
    /// session** : elle vit dans `@AppStorage`, pas dans le store, et le semis
    /// ne la pose donc pas. Sans ce préremplissage, l'écran `p2b` se
    /// photographierait avec une sous-section vide.
    ///
    /// La liste est un ordre d'usage — le plus récemment ouvert en tête. Les
    /// codes sont inscrits du **dernier au premier** pour que l'ordre affiché
    /// soit celui de la capture.
    @MainActor
    private func prereplirLesRecents(_ codes: [String]) {
        guard !codes.isEmpty else { return }
        let projets = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        for code in codes.reversed() {
            guard let projet = projets.first(where: { $0.code == code }) else { continue }
            mainRouter.rememberRecentProject(projet.ensuredStableID)
        }
    }

    /// Enregistre et arme la vue enregistrée que l'écran de recette demande.
    ///
    /// La vue est **persistée** (`AppSettings.portfolioSavedViews`) pour que le
    /// menu « Vue enregistrée : … » la montre, puis son identifiant est posé
    /// dans le routeur pour que `PortfolioView` l'active à son apparition.
    /// Idempotent par identifiant : relancer la recette ne crée pas de doublon.
    @MainActor
    private func poserLaVueEnregistree(_ vue: PortfolioSavedView?) {
        guard let vue else { return }
        PortfolioSavedViewStore.enregistrer(vue, in: context)
        mainRouter.pendingPortfolioSavedView = vue.id
    }

    /// La route à ouvrir, recalée sur le projet **réellement** semé.
    ///
    /// `RecetteScreen.ecranProjet` désigne le projet par un identifiant
    /// constant. Si le store portait déjà un projet du même code, le semis le
    /// rend tel quel — avec son propre identifiant — et la route constante ne
    /// désignerait plus rien. Le home de recette est jetable, donc le cas ne
    /// s'y produit pas ; le recalage est là pour le semis lancé depuis le menu,
    /// sur une base réelle.
    @MainActor
    private func routeDeRecette(_ route: MainRoute, focus: Project?) -> MainRoute {
        guard case .project(let id, let onglet) = route,
              id == RefonteDemoSeed.portfolioFocusProjectStableID,
              let focus else { return route }
        return .project(focus.ensuredStableID, onglet)
    }

    /// Lance, si activé dans les réglages et au plus une fois par 24 h, un job
    /// en arrière-plan qui compresse/supprime les WAV selon la politique de
    /// rétention.
    @MainActor
    private func maybeRunAutoCleanup() {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = (try? context.fetch(descriptor))?.first,
              settings.autoCleanupOnLaunch else { return }
        if let last = settings.lastCleanupAt,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        let plan = WavRetentionService.plan(in: context, settings: settings)
        guard !plan.toCompress.isEmpty || !plan.toDelete.isEmpty else { return }
        let queue = JobQueue.shared
        _ = queue.start(
            kind: .maintenance,
            meetingTitle: "Cleanup audio (auto)"
        ) { _ in
            for m in plan.toCompress {
                try Task.checkCancellation()
                do {
                    try await WavRetentionService.compress(m, in: context)
                } catch {
                    print("[AutoCleanup] compress échec: \(error)")
                }
            }
            for m in plan.toDelete {
                try Task.checkCancellation()
                await MainActor.run {
                    WavRetentionService.delete(m, in: context)
                }
            }
            await MainActor.run {
                settings.lastCleanupAt = Date()
                try? context.save()
                StorageStatsService.shared.invalidate()
            }
        }
    }

    /// Lance en arrière-plan le batch de rattrapage RAG (ADR
    /// `docs/adr/2026-09-05-rag-pipeline-inventaire.md`, section D) : ne
    /// bloque pas l'affichage de l'UI — `Task` planifie le travail et rend la
    /// main immédiatement, `RAGIndexingSweep` cède la main entre chaque
    /// parent traité via les `await` de ses handlers.
    private func runRAGIndexingSweep() {
        Task {
            await RAGIndexingSweep.shared.runIfNeeded(context: context)
        }
    }

    /// (Ré)enregistre les raccourcis globaux : l'overlay quick-picker et un
    /// raccourci par collaborateur (démarrage direct d'un 1:1). Désenregistre
    /// tout au préalable pour rester idempotent.
    private func registerHotkeys() {
        GlobalHotkeyService.shared.unregisterAll()

        let settings: AppSettings? = (try? context.fetch(FetchDescriptor<AppSettings>()))?.canonicalSettings
        let map = settings?.collaboratorHotkeys ?? [:]

        // Overlay (default ⌃⌥⌘1 if absent)
        let overlaySpec = HotkeySpec(serialized: map["__overlay__"] ?? "⌃⌥⌘1")
            ?? HotkeySpec(modifiers: [.control, .option, .command], keyChar: "1")
        _ = GlobalHotkeyService.shared.register(spec: overlaySpec) {
            OneToOneQuickPickerWindow.shared.present()
        }

        // Pastille flottante (lot 8, spec §1.4 et §5.4) : `⌘⇧S` capture la source
        // configurée, `⌘⇧N` ouvre un champ de note au timecode courant. Carbon et non
        // `.keyboardShortcut` : ils doivent fonctionner alors que Teams est au premier
        // plan. L'échec d'enregistrement est **publié** — un raccourci silencieusement
        // mort est indétectable (cf. `SettingsHotkeysSection`).
        registerSessionPillHotkeys(settings: settings)

        // Per-collab
        for (key, serialized) in map where key != "__overlay__" {
            guard let spec = HotkeySpec(serialized: serialized),
                  let uuid = UUID(uuidString: key) else { continue }
            _ = GlobalHotkeyService.shared.register(spec: spec) {
                Task { @MainActor in
                    let descriptor = FetchDescriptor<Collaborator>(
                        predicate: #Predicate { $0.stableID == uuid }
                    )
                    guard let collab = try? context.fetch(descriptor).first else { return }
                    QuickLaunchRouter.shared.startOneToOne(
                        collaborator: collab,
                        autoStartRecording: true,
                        in: context
                    )
                }
            }
        }
    }

    /// Les deux raccourcis globaux de la pastille flottante (lot 8).
    ///
    /// Bloc à part de `registerHotkeys()` pour rester lisible, mais appelé par lui :
    /// `unregisterAll()` a déjà tout rendu au système, et ces deux-là doivent revenir
    /// dans la même passe — sinon décocher un raccourci de collaborateur désarmerait
    /// silencieusement `⌘⇧S`.
    private func registerSessionPillHotkeys(settings: AppSettings?) {
        let controleur = SessionPillPanelController.shared
        // Les réglages sont relus à chaque évaluation de la règle d'affichage : le mode
        // peut changer alors qu'aucune réunion n'est ouverte, et une valeur figée ici
        // ne serait plus vraie une minute plus tard.
        controleur.mode = {
            let liste: [AppSettings] = (try? OneToOneApp.sharedContainer.mainContext
                .fetch(FetchDescriptor<AppSettings>())) ?? []
            return liste.canonicalSettings?.sessionPillMode ?? .sessionOnly
        }
        controleur.storedCorner = { settings?.sessionPillCorner ?? .bottomTrailing }
        controleur.persistCorner = { coin in
            guard let settings, settings.sessionPillCorner != coin else { return }
            settings.sessionPillCorner = coin
            try? OneToOneApp.sharedContainer.mainContext.save()
        }

        let capture = CaptureHotkey.capture
        if settings?.captureHotkeyEnabled ?? true {
            let ok = GlobalHotkeyService.shared.register(spec: capture.spec) {
                SessionPillPanelController.shared.captureShortcut()
            }
            CaptureHotkeyFailures.shared.record(capture, succeeded: ok)
        } else {
            CaptureHotkeyFailures.shared.forget(capture)
        }

        let note = CaptureHotkey.note
        if settings?.noteHotkeyEnabled ?? true {
            let ok = GlobalHotkeyService.shared.register(spec: note.spec) {
                SessionPillPanelController.shared.noteShortcut()
            }
            CaptureHotkeyFailures.shared.record(note, succeeded: ok)
        } else {
            CaptureHotkeyFailures.shared.forget(note)
        }
    }

    /// Réindexe tous les projets, collaborateurs et réunions (notes comprises)
    /// dans Spotlight.
    private func reindexSpotlight() {
        // Une reunion marquee « drainee » avec une preparation vide n'a rien
        // recu : le drapeau enregistrait « on a essaye ». Rien ne justifie de
        // lui fermer la porte.
        let drainsRouverts = PrepCarryoverService.reopenBurnedDrains(in: context)
        if drainsRouverts > 0 {
            print("[Repair] \(drainsRouverts) reunion(s) peuvent de nouveau recevoir une preparation")
        }

        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let allCollabs = try context.fetch(FetchDescriptor<Collaborator>())
            let allMeetings = try context.fetch(FetchDescriptor<Meeting>())
            SpotlightIndexService.shared.indexAll(projects: allProjects,
                                                  collaborators: allCollabs,
                                                  meetings: allMeetings)
        } catch {
            print("[Spotlight] Failed to fetch for indexing: \(error)")
        }
    }

    /// Réparation one-shot du store au lancement : déduplique les codes
    /// projet et backfill les `stableID` nil/dupliqués (Project, Collaborator,
    /// Meeting, et 4 autres types via les helpers), puis seed les templates.
    private func repairStoreIfNeeded() {
        guard !didRunDataRepair else { return }
        didRunDataRepair = true

        // Un rôle qui porte une adresse n'est pas un rôle. Une ancienne
        // version de l'import calendrier écrivait l'email de l'invité dans
        // `role` (commit 2cb5bf4) ; 38 fiches en portent la trace, dont 16 où
        // l'adresse n'existe **que** là. La règle déplace, elle n'efface pas.
        let rolesRepares = CollaboratorIdentity.repairRoles(in: context)
        if rolesRepares > 0 {
            print("[Repair] \(rolesRepares) rôle(s) qui portaient une adresse déplacés vers le champ email")
        }

        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let sortedProjects = allProjects.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }

            var seenCodes = Set<String>()
            var changed = false
            var generatedIndex = 1

            for project in sortedProjects {
                let trimmed = project.code.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseCode = trimmed.isEmpty ? "PXX_AUTO" : trimmed
                var candidate = baseCode
                var duplicateSuffix = 1

                while seenCodes.contains(candidate) {
                    if trimmed.isEmpty {
                        candidate = "PXX_AUTO_\(generatedIndex)"
                        generatedIndex += 1
                    } else {
                        candidate = "\(baseCode)_\(duplicateSuffix)"
                        duplicateSuffix += 1
                    }
                }

                if candidate != project.code {
                    project.code = candidate
                    changed = true
                }
                seenCodes.insert(candidate)
            }

            if changed {
                try context.save()
                print("Reparation SwiftData: codes projet dupliques corriges.")
            }

            // Backfill Project.stableID — new Optional field, nil on existing rows.
            let allProjectsForBackfill = try context.fetch(FetchDescriptor<Project>())
            var seenProjectIDs = Set<UUID>()
            var projectBackfilled = 0
            for proj in allProjectsForBackfill {
                if let id = proj.stableID, seenProjectIDs.insert(id).inserted { continue }
                proj.stableID = UUID()
                projectBackfilled += 1
            }
            if projectBackfilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(projectBackfilled) Project.stableID backfilles.")
            }

            // Backfill Collaborator.stableID — handles both nil rows and
            // duplicates from the legacy non-Optional `UUID()` default that
            // SwiftData applied identically to existing rows.
            let allCollabs = try context.fetch(FetchDescriptor<Collaborator>())
            var seenCollabIDs = Set<UUID>()
            var backfilled = 0
            for collab in allCollabs {
                if let id = collab.stableID, seenCollabIDs.insert(id).inserted { continue }
                collab.stableID = UUID()
                backfilled += 1
            }
            if backfilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(backfilled) Collaborator.stableID backfilles.")
            }

            // Backfill Meeting.stableID — pre-Optional rows may have nil or
            // share duplicates from the legacy non-Optional default. Detect
            // both and assign unique UUIDs.
            let allMeetings = try context.fetch(FetchDescriptor<Meeting>())
            var seenIDs = Set<UUID>()
            var meetingFilled = 0
            for meeting in allMeetings {
                if let id = meeting.stableID, seenIDs.insert(id).inserted { continue }
                meeting.stableID = UUID()
                meetingFilled += 1
            }
            if meetingFilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(meetingFilled) Meeting.stableID backfilles.")
            }

            // Defensive dedup for the 3 stableID Optionals + SlideCapture.id.
            // Same pattern as Meeting/Collaborator: nil rows OR duplicates
            // get a fresh UUID.
            deduplicateOptional(context: context, label: "ManagerReportItem",
                                fetch: FetchDescriptor<ManagerReportItem>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicateOptional(context: context, label: "ManagerMeetingReport",
                                fetch: FetchDescriptor<ManagerMeetingReport>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicateOptional(context: context, label: "TranscriptSegment",
                                fetch: FetchDescriptor<TranscriptSegment>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicate(context: context, label: "SlideCapture",
                        fetch: FetchDescriptor<SlideCapture>(),
                        get: { $0.id }, set: { $0.id = $1 })
            deduplicate(context: context, label: "TranscriptChunk",
                        fetch: FetchDescriptor<TranscriptChunk>(),
                        get: { $0.chunkId }, set: { $0.chunkId = $1 })

            // TranscriptChunk.chunkId : UUID non optionnel sans défaut — les lignes
            // migrées depuis un store antérieur à ce champ partagent toutes le même
            // identifiant. `IdentifierRepair` isole la règle de dédoublonnage (testée
            // sans SwiftData) ; `deduplicate` ci-dessous ne fait que la brancher sur
            // le store, comme pour SlideCapture.
            deduplicate(context: context, label: "TranscriptChunk",
                        fetch: FetchDescriptor<TranscriptChunk>(),
                        get: { $0.chunkId }, set: { $0.chunkId = $1 })

            BuiltInTemplates.seedIfNeeded(in: context)
            try context.save()
        } catch {
            print("Echec reparation SwiftData: \(error)")
        }
    }

    /// Same as `deduplicate` but for Optional UUID fields — nil rows are
    /// also backfilled.
    ///
    /// Reste volontairement distinct de `IdentifierRepair.duplicates` : cette
    /// dernière ne connaît que des `UUID` non optionnels, alors qu'ici un champ
    /// `nil` (jamais encore backfillé) doit lui aussi être réattribué. C'est un
    /// backfill (nil OU doublon), pas un simple dédoublonnage — deux règles
    /// différentes, qui ne doivent pas être forcées à converger.
    private func deduplicateOptional<T: PersistentModel>(
        context: ModelContext,
        label: String,
        fetch: FetchDescriptor<T>,
        get: (T) -> UUID?,
        set: (T, UUID) -> Void
    ) {
        guard let all = try? context.fetch(fetch) else { return }
        var seen = Set<UUID>()
        var fixed = 0
        for row in all {
            if let id = get(row), seen.insert(id).inserted { continue }
            set(row, UUID())
            fixed += 1
        }
        if fixed > 0 {
            try? context.save()
            print("Reparation SwiftData: \(fixed) \(label).stableID backfilles.")
        }
    }

    /// Scans a SwiftData entity for rows whose UUID identifier collides
    /// with another, and reassigns each duplicate a fresh UUID. Saves
    /// once when any change is made. Quiet on no-op.
    ///
    /// Délègue la règle de dédoublonnage à `IdentifierRepair.duplicates`, seule
    /// version testée (sans dépendance à SwiftData) ; cette fonction ne fait que
    /// la brancher sur le store : fetch, mutation, sauvegarde unique, log.
    private func deduplicate<T: PersistentModel>(
        context: ModelContext,
        label: String,
        fetch: FetchDescriptor<T>,
        get: (T) -> UUID,
        set: (T, UUID) -> Void
    ) {
        guard let all = try? context.fetch(fetch) else { return }
        let toFix = IdentifierRepair.duplicates(in: all, identifier: get)
        for row in toFix {
            set(row, UUID())
        }
        if !toFix.isEmpty {
            try? context.save()
            print("Reparation SwiftData: \(toFix.count) \(label) UUID dedoublonnes.")
        }
    }
}

/// Enveloppe de taille du contenu de la fenêtre `1to1-meeting`.
///
/// **Pourquoi elle existe.** Le contenu racine d'une fenêtre SwiftUI qui ne
/// borne pas sa taille oblige le `NSHostingView` racine à *mesurer toute la
/// hiérarchie* pour en déduire `contentMinSize`/`contentMaxSize`
/// (`updateWindowContentSizeExtremaIfNecessary`) — et cela **pendant** la passe
/// Auto Layout de la fenêtre, depuis `NSHostingView.updateConstraints()`. Cette
/// mesure réinvalide le graphe de vues, qui remarque aussitôt la fenêtre
/// « needs update constraints » : la passe se relance sans fin et AppKit lève
/// `NSGenericException` — « The window has been marked as needing another
/// Update Constraints in Window pass, but it has already had more […] passes
/// than there are views in the window ». L'écran de réunion est devenu
/// sensible à cette boucle quand la barre du haut est passée sur une ligne
/// (spec §2.1 : titre `flex:1; min-width:0`, donc `maxWidth: .infinity` +
/// `layoutPriority`) ; la fenêtre principale y échappe parce que son contenu
/// est un `NavigationSplitView`, qui borne lui-même ses colonnes.
///
/// Déclarer l'enveloppe rend les extrema **constants** : la fenêtre n'a plus
/// besoin de mesurer l'écran de réunion pour connaître ses limites, et la passe
/// de contraintes converge. C'est déjà ce que fait la fenêtre de préparation
/// (`PrepWindowView`, `600 × 480`) ; la fenêtre de réunion était la seule des
/// trois scènes à ne rien déclarer.
enum MeetingWindowSizing {
    /// Plancher de largeur. Il ne peut pas descendre sous
    /// `MeetingSpaceLayout.fluidMinimum + One2OneToken.actionsRailWidth` :
    /// en dessous, `MeetingSpaceLayout.columns` sacrifie le rail d'actions,
    /// que la spec §1.1 veut permanent. Vérifié par
    /// `MeetingWindowSizingTests`.
    static let minWidth: CGFloat = 960
    /// Plancher de hauteur : barre du haut (38) + barre d'espaces (34) + les
    /// deux colonnes de l'espace Réunion sans qu'elles soient réduites à rien.
    static let minHeight: CGFloat = 640
    /// Taille d'ouverture par défaut, celle des captures de la spec.
    static let idealWidth: CGFloat = 1_280
    static let idealHeight: CGFloat = 800
}

/// La taille de la **fenêtre principale** : pourquoi elle avait cessé d'être
/// restaurée, et pourquoi ce n'est pas celle de la fenêtre de réunion (retour
/// d'usage du 2026-09-08).
///
/// La fenêtre s'ouvrait à ~1 660 × 540, barre latérale écrasée. Deux causes,
/// enchaînées, et il fallait corriger les deux.
///
/// **1. Le cadre enregistré était devenu introuvable.** SwiftUI enregistre le
/// cadre d'une fenêtre de `WindowGroup` sous un nom qu'il **dérive du type de la
/// vue racine**. Le nom réellement écrit dans les préférences est :
///
/// ```
/// NSWindow Frame SwiftUI.ModifiedContent<…OneToOne.ContentView…,
///   OneToOne.(unknown context at $1030392a8).SessionFullscreenHostModifier>-1-AppWindow-1
/// ```
///
/// `$1030392a8` est une **adresse**. Le modificateur de l'hôte du mode séance
/// est un type `private`, dont le nom manglé n'est pas symbolique : il porte
/// l'adresse de son contexte, que l'ASLR change à chaque lancement. Deux clés
/// pour la même chaîne de vues ont été relevées dans le même fichier de
/// préférences, différant par cette seule adresse. Autrement dit : depuis que le
/// correctif #42 a inséré un type privé dans la chaîne, **chaque lancement
/// cherche son cadre sous une clé que le lancement précédent n'a pas écrite**.
/// Avant #42 la chaîne ne portait que des types publics (`ContentView`,
/// `_PreferenceWritingModifier`, `_EnvironmentKeyWritingModifier`), le nom était
/// stable, et la restauration marchait — c'est exactement ce que l'utilisateur
/// décrit : « avant la refonte elle rouvrait à sa taille sauvegardée ».
///
/// **2. Le repli était pathologique.** Sans cadre à restaurer, la fenêtre se
/// dimensionne sur son contenu — et l'hôte enveloppait ce contenu dans un
/// `ZStack`, qui mesure ses enfants et porte la taille du résultat. Le
/// `NavigationSplitView` cessait d'être la racine de la fenêtre, laquelle
/// prenait la taille *idéale mesurée* du tableau de bord et de sa carte de
/// 52 semaines : large et courte, 1 660 × 540. L'hôte pose désormais une
/// **surimpression** (cf. `SessionFullscreenHost`), qui laisse le contenu porter
/// sa taille.
///
/// D'où les deux constantes ci-dessous : une clé de préférence **écrite à la
/// main**, donc stable quoi qu'on ajoute plus tard à la scène, et une taille de
/// premier lancement — 1 280 × 800, celle des captures de la spec ; sous cela la
/// barre latérale de 190 px et le tableau de bord ne tiennent pas ensemble.
enum MainWindowSizing {
    static let defaultWidth: CGFloat = 1_280
    static let defaultHeight: CGFloat = 800
    /// Clé du cadre enregistré. **Ne pas la changer** : c'est sous elle que la
    /// taille des utilisateurs actuels est écrite.
    static let frameKey = "OneToOne.mainWindowFrame"
}

/// Où poser la fenêtre principale quand le cadre enregistré ne correspond plus
/// aux écrans branchés (retour de recette du 2026-09-09).
///
/// **Pourquoi une fonction pure.** La règle « le cadre doit toucher un écran
/// visible » vivait dans `MainWindowFrameRestorer.restaurer`, donc dans une
/// `NSView` privée : intestable, et appliquée à **une seule** des deux sources
/// de cadre. Car il y en a deux — la nôtre (`MainWindowSizing.frameKey`) et
/// celle de SwiftUI, dont le nom manglé porte une adresse. Le commentaire de
/// `MainWindowSizing` affirmait que cette seconde clé était « sans lecteur » :
/// c'est faux, **SwiftUI la relit**. Le 9 septembre 2026, elle portait un cadre
/// à `x = 2048`, sur un second écran 1920 × 1050 débranché depuis : la fenêtre
/// principale a été restaurée entièrement hors de tout écran — aucune surface,
/// aucun rendu, `onAppear` jamais parti, aucun semis, et trois heures de
/// diagnostic sur une recette qui photographiait la fenêtre d'un autre
/// processus.
///
/// La règle est donc sortie ici, testée avant sa vue
/// (`MainWindowPlacementTests`) comme `MeetingSpaceRouting` ou `ReminderRules`,
/// et appliquée **inconditionnellement** après la restauration — quelle que
/// soit la clé d'où vient le cadre.
enum MainWindowPlacement {

    /// Rend `cadre` inchangé s'il touche un écran visible ; sinon un cadre de
    /// `tailleParDefaut` centré sur le premier écran.
    ///
    /// - Parameter ecrans: les `visibleFrame` des écrans branchés. **Vide rend
    ///   `cadre`** : pendant la veille, `NSScreen.screens` peut l'être, et
    ///   recentrer sur un écran qu'on ne connaît pas serait pire que de ne rien
    ///   faire.
    ///
    /// On corrige l'invisible, pas le gênant : un cadre qui ne chevauche
    /// l'écran que d'un coin est laissé tel quel — l'utilisateur peut l'attraper.
    static func corrige(cadre: CGRect,
                        ecrans: [CGRect],
                        tailleParDefaut: CGSize) -> CGRect {
        guard !ecrans.isEmpty else { return cadre }
        // `isEmpty` avant `intersects` : un cadre dégénéré (largeur ou hauteur
        // nulle) n'a pas de surface, donc pas d'écran — et `CGRect.intersects`
        // n'est pas la bonne question à lui poser.
        if !cadre.isEmpty, ecrans.contains(where: { $0.intersects(cadre) }) { return cadre }
        let ecran = ecrans[0]
        return CGRect(x: ecran.midX - tailleParDefaut.width / 2,
                      y: ecran.midY - tailleParDefaut.height / 2,
                      width: tailleParDefaut.width,
                      height: tailleParDefaut.height)
    }
}

/// Enregistre et restaure le cadre de la fenêtre principale, sous une clé de
/// notre choix.
///
/// **Pourquoi pas le nom d'enregistrement de cadre d'AppKit.** C'était le
/// premier essai, et la
/// recette l'a démenti : SwiftUI **repose** son propre nom d'enregistrement
/// après le passage de `viewDidMoveToWindow`. Le nom écrit à la main était
/// remplacé, la clé instable revenait, et rien n'était restauré — le défaut
/// intact. Se disputer la propriété du nom avec SwiftUI, à chaque mise à jour de
/// vue, n'a pas de vainqueur prévisible.
///
/// On fait donc le travail nous-mêmes : lecture au moment où la vue rejoint sa
/// fenêtre, écriture à chaque déplacement et à chaque redimensionnement.
/// Vingt lignes, une clé constante, aucune dépendance à ce que SwiftUI décide de
/// nommer. Sa clé instable continue d'être écrite à côté — et, contrairement à
/// ce que ce commentaire affirmait, **SwiftUI la relit** : elle a donc un
/// lecteur, et un cadre toxique enregistré sous elle a laissé la fenêtre
/// principale hors écran le 2026-09-09. C'est `MainWindowPlacement.corrige`,
/// appliqué à toutes les sources, qui l'empêche désormais.
///
/// L'ordre tient : SwiftUI donne sa taille à la fenêtre à la création — donc la
/// taille de `defaultSize`, faute de cadre trouvé sous **sa** clé — et
/// `viewDidMoveToWindow` passe après. La restauration est bien le dernier mot.
private struct MainWindowFrameRestorer: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView { Restorer() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Restorer: NSView {

        private var observations: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.forEach(NotificationCenter.default.removeObserver)
            observations = []
            guard let window else { return }
            // Le seul endroit du code qui tient la fenêtre principale : les
            // raccourcis posés depuis un menu natif ou la barre de menus en ont
            // besoin pour la remonter (cf. `MainWindowRegistry`).
            MainWindowRegistry.enregistrer(window)
            restaurer(window)
            // Inconditionnel, et **après** `restaurer` : le cadre à corriger
            // peut venir de notre clé comme de celle que SwiftUI a restaurée de
            // son côté — c'est cette seconde source qui a laissé la fenêtre
            // hors écran le 2026-09-09.
            ramenerSurUnEcran(window)
            for nom in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                observations.append(NotificationCenter.default.addObserver(
                    forName: nom, object: window, queue: .main
                ) { notification in
                    guard let fenetre = notification.object as? NSWindow else { return }
                    // Jamais en plein écran : le cadre y est celui de l'écran,
                    // et le restaurer rouvrirait l'application à la taille de
                    // l'écran sans en avoir la barre de titre.
                    guard !fenetre.styleMask.contains(.fullScreen) else { return }
                    UserDefaults.standard.set(NSStringFromRect(fenetre.frame),
                                              forKey: MainWindowSizing.frameKey)
                })
            }
        }

        /// Applique le cadre enregistré. Le bornage à un écran visible n'est
        /// plus fait ici : `ramenerSurUnEcran`, appelé juste après, s'en charge
        /// pour **toutes** les sources de cadre — la nôtre et celle de SwiftUI.
        private func restaurer(_ window: NSWindow) {
            guard let chaine = UserDefaults.standard.string(forKey: MainWindowSizing.frameKey)
            else { return }
            let cadre = NSRectFromString(chaine)
            guard cadre.width >= 1, cadre.height >= 1 else { return }
            window.setFrame(cadre, display: false)
        }

        /// Ramène la fenêtre sur un écran visible si son cadre n'en touche
        /// aucun. La règle est dans `MainWindowPlacement.corrige`, fonction
        /// pure testée.
        private func ramenerSurUnEcran(_ window: NSWindow) {
            let corrige = MainWindowPlacement.corrige(
                cadre: window.frame,
                ecrans: NSScreen.screens.map(\.visibleFrame),
                tailleParDefaut: CGSize(width: MainWindowSizing.defaultWidth,
                                        height: MainWindowSizing.defaultHeight))
            guard corrige != window.frame else { return }
            window.setFrame(corrige, display: false)
        }
    }
}

/// Contenu de la fenêtre `1to1-meeting`. Résout le token vers un `Meeting`
/// via `stableID`, présente `MeetingView` avec `autoStartRecording`.
struct OneToOneMeetingWindowContent: View {
    let token: OneToOneLaunchToken?
    @Environment(\.modelContext) private var context
    @State private var resolved: Meeting?

    var body: some View {
        Group {
            if let resolved {
                MeetingView(meeting: resolved, autoStartRecording: token?.autoStartRecording ?? false)
            } else {
                ProgressView()
            }
        }
        // ⚠️ Ne pas retirer : sans enveloppe déclarée, l'ouverture de cette
        // fenêtre boucle sur la passe Auto Layout et l'application meurt
        // (cf. `MeetingWindowSizing`). Le plancher doit rester une constante :
        // le déduire du contenu ramènerait la boucle.
        .frame(minWidth: MeetingWindowSizing.minWidth,
               idealWidth: MeetingWindowSizing.idealWidth,
               maxWidth: .infinity,
               minHeight: MeetingWindowSizing.minHeight,
               idealHeight: MeetingWindowSizing.idealHeight,
               maxHeight: .infinity)
        .onAppear { resolveIfNeeded() }
        .onChange(of: token) { _, _ in resolveIfNeeded() }
    }

    /// Résout le token courant vers un `Meeting` via `stableID` (no-op si déjà
    /// résolu vers le même meeting).
    private func resolveIfNeeded() {
        guard let token else { return }
        if let resolved, resolved.stableID == token.meetingID { return }
        let target = token.meetingID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.stableID == target }
        )
        resolved = try? context.fetch(descriptor).first
    }
}
