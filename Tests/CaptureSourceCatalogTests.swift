import Testing
import CoreGraphics
@testable import OneToOne

/// Le catalogue des sources du sélecteur (spec §5.1, capture 4a). Fonctions
/// pures : aucun appel à ScreenCaptureKit, aucune autorisation.
@Suite("CaptureSourceCatalog")
struct CaptureSourceCatalogTests {

    private func window(_ bundle: String?,
                        _ title: String,
                        id: CGWindowID = 1,
                        width: CGFloat = 1440,
                        height: CGFloat = 900) -> ShareableWindow {
        ShareableWindow(id: id,
                        title: title,
                        appName: bundle == CaptureSourceCatalog.zoomBundleIdentifier ? "zoom.us" : "Microsoft Teams",
                        bundleIdentifier: bundle,
                        frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    @Test("trois lignes, dans l'ordre de la capture : Teams, Zoom, Écran")
    func threeRowsInOrder() {
        let options = CaptureSourceCatalog.options(teams: .init(), zoom: .init())
        #expect(options.map(\.source) == [.teams, .zoom, .screen])
        #expect(options.map(\.badge) == ["TEAMS", "ZOOM", "ÉCRAN"])
        #expect(options.map(\.title) == ["Microsoft Teams", "Zoom", "Écran entier"])
    }

    @Test("Teams en réunion avec un partage : la ligne nomme le partageur et s'allume")
    func teamsSharing() {
        let etat = CaptureSourceCatalog.teamsState(
            windows: [window("com.microsoft.teams2", "Réunion | Microsoft Teams")],
            sharerName: "Sylvain",
            isSharing: true)
        let ligne = CaptureSourceCatalog.options(teams: etat, zoom: .init())[0]
        #expect(ligne.subtitle == "Réunion · partage de Sylvain en cours")
        #expect(ligne.isActive)
        #expect(ligne.supportsAutomaticDetection)
        #expect(ligne.windowID == 1)
    }

    @Test("Teams lancé sans réunion : « Aucune réunion active » et bascule indisponible")
    func teamsWithoutMeeting() {
        // Le titre ne ressemble pas à un appel : c'est la fenêtre de
        // conversations. C'est le cas exigé par la recette du lot 7.
        let etat = CaptureSourceCatalog.teamsState(
            windows: [window("com.microsoft.teams2", "Général — Architecture")])
        let ligne = CaptureSourceCatalog.options(teams: etat, zoom: .init())[0]
        #expect(ligne.subtitle == "Fenêtre ouverte · aucune réunion active")
        // La fenêtre existe : elle est capturable, même sans réunion.
        #expect(ligne.isActive)
    }

    @Test("Teams absent : « Aucune réunion active », ligne éteinte, bascule indisponible")
    func teamsAbsent() {
        let ligne = CaptureSourceCatalog.options(teams: .init(), zoom: .init())[0]
        #expect(ligne.subtitle == "Aucune réunion active")
        #expect(!ligne.isActive)
        #expect(!ligne.supportsAutomaticDetection)
        #expect(ligne.windowID == 0)
    }

    @Test("Teams en réunion sans partage détecté : la ligne ne prétend pas qu'il y en a un")
    func teamsInCallWithoutSharing() {
        let etat = CaptureSourceCatalog.teamsState(
            windows: [window("com.microsoft.teams2", "Appel | Microsoft Teams")])
        let ligne = CaptureSourceCatalog.options(teams: etat, zoom: .init())[0]
        #expect(ligne.subtitle == "Réunion en cours · aucun partage détecté")
    }

    @Test("Teams en réunion, partage sans partageur connu")
    func teamsSharingWithoutName() {
        let etat = CaptureSourceCatalog.teamsState(
            windows: [window("com.microsoft.teams2", "Meeting | Microsoft Teams")],
            isSharing: true)
        #expect(CaptureSourceCatalog.subtitle(for: etat) == "Réunion · partage en cours")
    }

    @Test("Zoom est reconnu par son bundle, jamais par son titre")
    func zoomByBundle() {
        let etat = CaptureSourceCatalog.zoomState(
            windows: [window(CaptureSourceCatalog.zoomBundleIdentifier, "Zoom Meeting", id: 7)])
        let ligne = CaptureSourceCatalog.options(teams: .init(), zoom: etat)[1]
        #expect(ligne.isActive)
        #expect(ligne.windowID == 7)
        // Zoom ne publie pas de titre exploitable : toute fenêtre Zoom compte
        // comme une réunion (programme §9 : la détection fine est hors périmètre).
        #expect(ligne.subtitle == "Réunion en cours · aucun partage détecté")
    }

    @Test("Zoom absent : « Aucune réunion active »")
    func zoomAbsent() {
        let ligne = CaptureSourceCatalog.options(teams: .init(), zoom: .init())[1]
        #expect(ligne.subtitle == "Aucune réunion active")
        #expect(!ligne.isActive)
    }

    @Test("l'écran entier est toujours proposé et toujours actif")
    func screenIsAlwaysAvailable() {
        let ligne = CaptureSourceCatalog.options(teams: .init(), zoom: .init())[2]
        #expect(ligne.isActive)
        #expect(ligne.windowID == 0)
        #expect(ligne.subtitle == "Ou une zone à la souris")
    }

    @Test("la fenêtre de réunion retenue est la plus grande de l'application")
    func largestWindowWins() {
        let petite = window("com.microsoft.teams2", "Réunion | Microsoft Teams", id: 1, width: 400, height: 300)
        let grande = window("com.microsoft.teams2", "Réunion | Microsoft Teams", id: 2, width: 1600, height: 1000)
        let etat = CaptureSourceCatalog.teamsState(windows: [petite, grande])
        #expect(etat.window?.id == 2)
    }

    @Test("le partageur n'est nommé que s'il est déjà un participant de la réunion")
    func sharerNameFromTitle() {
        let participants = ["Sylvain", "Marine", "Olivier"]
        #expect(CaptureSourceCatalog.sharerName(fromTitle: "Partage de Sylvain | Microsoft Teams",
                                                among: participants) == "Sylvain")
        // Aucun participant dans le titre : on ne devine pas un nom depuis un
        // mot quelconque, sinon le sous-titre annoncerait « partage de Réunion ».
        #expect(CaptureSourceCatalog.sharerName(fromTitle: "Réunion | Microsoft Teams",
                                                among: participants) == nil)
        #expect(CaptureSourceCatalog.sharerName(fromTitle: "", among: participants) == nil)
    }

    @Test("une fenêtre sans bundle ou d'une autre application est ignorée")
    func foreignWindowsIgnored() {
        let autres = [window(nil, "Réunion | Microsoft Teams", id: 3),
                      window("com.apple.Safari", "Réunion", id: 4)]
        #expect(CaptureSourceCatalog.teamsState(windows: autres).window == nil)
        #expect(CaptureSourceCatalog.zoomState(windows: autres).window == nil)
    }
}
