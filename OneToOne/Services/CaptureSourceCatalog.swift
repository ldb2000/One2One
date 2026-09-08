import CoreGraphics
import Foundation

/// Une ligne du sélecteur de source (spec §5.1, capture `4a-capture-selecteur.png`) :
/// `TEAMS · Microsoft Teams · Réunion · partage de Sylvain en cours`.
struct CaptureSourceOption: Identifiable, Equatable, Sendable {

    var id: CaptureSource { source }

    let source: CaptureSource
    /// Le mot de la vignette 44 × 30 (`TEAMS`, `ZOOM`, `ÉCRAN`). Le **texte**
    /// porte l'information, la couleur la confirme : une palette seule serait
    /// illisible pour un daltonien (même règle que `ResourceTypeIcon`).
    let badge: String
    /// Nom du produit, en gras sur la ligne.
    let title: String
    /// Sous-titre d'état : `Réunion · partage de Sylvain en cours`,
    /// `Aucune réunion active`, `Ou une zone à la souris`.
    let subtitle: String
    /// Fenêtre à capturer. `0` (`kCGNullWindowID`) = écran entier.
    let windowID: CGWindowID
    /// Point `accent/ok` : la source est prête à être capturée.
    let isActive: Bool

    /// Une source inactive rend la bascule « à chaque changement de partage »
    /// indisponible : sans fenêtre à lire, il n'y a pas de partage à détecter.
    var supportsAutomaticDetection: Bool { isActive }
}

/// Construit la liste des sources proposées par le sélecteur.
///
/// **Fonctions pures** : les entrées (fenêtres partageables, titre de la
/// fenêtre Teams, nom du partageur, « le détecteur bouge ») sont fournies par
/// l'appelant, qui seul touche à ScreenCaptureKit et à `TeamsCallMonitor`. Le
/// critère d'acceptation n° 1 du chantier 4 — savoir sans ouvrir de menu si la
/// capture est armée, sur quelle source et combien de captures existent — se
/// teste donc sans écran ni autorisation.
enum CaptureSourceCatalog {

    /// Bundles de Microsoft Teams (v1 et v2) — même liste que `TeamsCallMonitor`,
    /// dont ce catalogue est le pendant côté capture.
    static let teamsBundleIdentifiers = TeamsCallMonitor.teamsBundleIdentifiers
    /// Bundle de Zoom. La détection de Zoom ne va pas au-delà de la présence de
    /// sa fenêtre (programme §9 : hors périmètre).
    static let zoomBundleIdentifier = "us.zoom.xos"

    /// L'état d'une application de réunion, tel que le sous-titre l'annonce.
    struct MeetingAppState: Equatable, Sendable {
        /// La fenêtre de réunion trouvée, `nil` si l'application n'est pas
        /// lancée ou n'a aucune fenêtre exploitable.
        var window: ShareableWindow?
        /// Le titre de la fenêtre ressemble à un appel en cours
        /// (`TeamsCallObservation.titleLooksLikeCall`).
        var isInCall: Bool = false
        /// Prénom du partageur, quand on le connaît. Affiché tel quel :
        /// `Réunion · partage de Sylvain en cours`.
        var sharerName: String?
        /// Le détecteur voit l'image bouger : quelque chose est bien partagé.
        var isSharing: Bool = false
    }

    /// Les trois lignes de la capture 4a, dans cet ordre : Teams, Zoom, Écran.
    ///
    /// L'écran entier est **toujours** proposé et toujours actif : c'est la
    /// source de repli quand ni Teams ni Zoom ne tournent, et un sélecteur qui
    /// n'aurait aucune ligne active serait un cul-de-sac.
    static func options(teams: MeetingAppState, zoom: MeetingAppState) -> [CaptureSourceOption] {
        [
            option(source: .teams, badge: "TEAMS", title: "Microsoft Teams", state: teams),
            option(source: .zoom, badge: "ZOOM", title: "Zoom", state: zoom),
            CaptureSourceOption(source: .screen,
                                badge: "ÉCRAN",
                                title: "Écran entier",
                                subtitle: "Ou une zone à la souris",
                                windowID: 0,
                                isActive: true)
        ]
    }

    private static func option(source: CaptureSource,
                               badge: String,
                               title: String,
                               state: MeetingAppState) -> CaptureSourceOption {
        CaptureSourceOption(source: source,
                            badge: badge,
                            title: title,
                            subtitle: subtitle(for: state),
                            windowID: state.window?.id ?? 0,
                            isActive: state.window != nil)
    }

    /// Le sous-titre d'état de la spec §5.1.
    ///
    /// Trois cas, et pas un de plus : pas de fenêtre → `Aucune réunion active` ;
    /// une réunion en cours → on nomme le partageur si on le connaît ; une
    /// fenêtre sans réunion → on ne prétend pas qu'il y en a une. La recette
    /// exige explicitement le deuxième message quand Teams tourne sans réunion.
    static func subtitle(for state: MeetingAppState) -> String {
        guard state.window != nil else { return "Aucune réunion active" }
        guard state.isInCall else { return "Fenêtre ouverte · aucune réunion active" }
        if state.isSharing, let nom = state.sharerName, !nom.isEmpty {
            return "Réunion · partage de \(nom) en cours"
        }
        if state.isSharing { return "Réunion · partage en cours" }
        return "Réunion en cours · aucun partage détecté"
    }

    /// L'état de Teams déduit des fenêtres partageables et de l'observation
    /// d'appel. Le titre de fenêtre sert **uniquement** à détecter la réunion
    /// active (décision D7) : c'est le détecteur d'image qui dit si ça bouge.
    static func teamsState(windows: [ShareableWindow],
                           sharerName: String? = nil,
                           isSharing: Bool = false) -> MeetingAppState {
        let fenetre = meetingWindow(in: windows, bundleIdentifiers: teamsBundleIdentifiers)
        return MeetingAppState(
            window: fenetre,
            isInCall: fenetre.map { TeamsCallObservation.titleLooksLikeCall($0.title) } ?? false,
            sharerName: sharerName,
            isSharing: isSharing)
    }

    /// L'état de Zoom : détecté par son seul bundle. Zoom ne publie pas de
    /// titre exploitable pour distinguer une réunion d'une fenêtre d'accueil,
    /// donc toute fenêtre Zoom assez grande est considérée comme une réunion.
    static func zoomState(windows: [ShareableWindow], isSharing: Bool = false) -> MeetingAppState {
        let fenetre = meetingWindow(in: windows, bundleIdentifiers: [zoomBundleIdentifier])
        return MeetingAppState(window: fenetre,
                               isInCall: fenetre != nil,
                               sharerName: nil,
                               isSharing: isSharing)
    }

    /// Le prénom du partageur, deviné depuis le **titre de la fenêtre** Teams.
    ///
    /// Teams n'expose aucune API : quand il nomme le partage dans son titre
    /// (« Partage de Sylvain »), le prénom y est, et il n'y est pas sinon.
    /// On ne retient donc qu'un prénom **déjà connu de la réunion** : inventer
    /// un nom à partir d'un mot du titre produirait « partage de Réunion en
    /// cours ». `nil` quand rien ne correspond, et le sous-titre se rabat sur
    /// « partage en cours ».
    static func sharerName(fromTitle title: String, among participants: [String]) -> String? {
        guard !title.isEmpty else { return nil }
        let normalise = AgendaProjectResolver.normalizedKey(title)
        let mots = Set(normalise.split(separator: " ").map(String.init))
        return participants.first { prenom in
            let cle = AgendaProjectResolver.normalizedKey(prenom)
            return !cle.isEmpty && mots.contains(cle)
        }
    }

    /// La plus grande fenêtre de l'application visée : sur Teams, la fenêtre de
    /// réunion est toujours plus grande que la liste des conversations.
    static func meetingWindow(in windows: [ShareableWindow],
                              bundleIdentifiers: Set<String>) -> ShareableWindow? {
        windows
            .filter { fenetre in
                guard let bundle = fenetre.bundleIdentifier else { return false }
                return bundleIdentifiers.contains(bundle)
            }
            .max { gauche, droite in
                gauche.frame.width * gauche.frame.height < droite.frame.width * droite.frame.height
            }
    }
}
