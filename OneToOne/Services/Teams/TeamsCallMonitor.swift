import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

private let teamsLog = Logger(subsystem: "com.onetoone.app", category: "teams")

/// Surveille localement Microsoft Teams et publie `callStarted` / `callEnded`.
/// C'est le **déclencheur 1** de la spec §3 : le moins fiable des trois, et le
/// seul qui puisse produire un faux positif — d'où les seuils de
/// `TeamsCallObservation`.
///
/// Aucune API Microsoft n'est utilisée (décision T-A) : on n'observe que ce que
/// macOS expose, c'est-à-dire l'app au premier plan et les titres de fenêtres.
@MainActor
final class TeamsCallMonitor: NSObject {

    static let shared = TeamsCallMonitor()

    /// Publiée quand un appel est considéré comme démarré. Sans `userInfo` :
    /// l'appariement avec l'agenda est le travail du coordinateur.
    static let callStartedNotification = Notification.Name("OneToOne.TeamsCallMonitor.callStarted")
    static let callEndedNotification = Notification.Name("OneToOne.TeamsCallMonitor.callEnded")

    nonisolated static let teamsBundleIdentifiers: Set<String> = ["com.microsoft.teams", "com.microsoft.teams2"]

    /// Cadence d'échantillonnage. Les seuils de `TeamsCallObservation` sont de
    /// 5 s et 30 s : une seconde suffit largement et reste négligeable.
    private static let tickInterval: TimeInterval = 1.0

    private var state = TeamsCallState()
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private override init() { super.init() }

    // MARK: - Cycle de vie

    /// Arme l'observation. Idempotent.
    func start() {
        guard timer == nil else { return }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(
                nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in await self?.tick() }
                })
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    /// Désarme l'observation et libère timer et observateurs.
    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
        workspaceObservers.removeAll()
        timer?.invalidate()
        timer = nil
        state = TeamsCallState()
    }

    // MARK: - Sélection de fenêtre (pure)

    /// Retourne le titre de la première fenêtre appartenant à Teams et dont le
    /// titre évoque un appel. Fonction pure, testée sans système.
    nonisolated static func teamsWindowTitle(in windows: [(bundleID: String, title: String)]) -> String? {
        windows.first { window in
            teamsBundleIdentifiers.contains(window.bundleID)
                && TeamsCallObservation.titleLooksLikeCall(window.title)
        }?.title
    }

    // MARK: - Observation

    /// Un tick : construit l'entrée, avance la machine, publie la décision.
    private func tick() async {
        let observed = await observeWindows()
        let input = TeamsObservationInput(isTeamsWindowPresent: observed != nil,
                                          windowTitle: observed ?? "",
                                          now: Date())

        switch TeamsCallObservation.step(state: &state, input: input) {
        case .none:
            break
        case .callStarted:
            teamsLog.info("teams call started (source 1)")
            NotificationCenter.default.post(name: Self.callStartedNotification, object: nil)
        case .callEnded:
            teamsLog.info("teams call ended (source 1)")
            NotificationCenter.default.post(name: Self.callEndedNotification, object: nil)
        }
    }

    /// Titre de la fenêtre Teams pertinente, ou `nil`.
    ///
    /// Deux niveaux, par ordre de qualité décroissante :
    /// 1. si la permission d'enregistrement d'écran est **déjà** accordée,
    ///    `SCShareableContent` énumère toutes les fenêtres, arrière-plan
    ///    compris — Teams n'a alors pas besoin d'être au premier plan ;
    /// 2. sinon, on se rabat sur l'app au premier plan.
    ///
    /// `CGPreflightScreenCaptureAccess()` ne déclenche **aucune** demande de
    /// permission : tant que l'utilisateur n'a pas enregistré une réunion à
    /// deux pistes, on reste silencieusement au niveau 2 (spec D-11).
    private func observeWindows() async -> String? {
        if CGPreflightScreenCaptureAccess() {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: false)
                let windows = content.windows.compactMap { window -> (bundleID: String, title: String)? in
                    guard let bundleID = window.owningApplication?.bundleIdentifier,
                          let title = window.title, !title.isEmpty else { return nil }
                    return (bundleID: bundleID, title: title)
                }
                return Self.teamsWindowTitle(in: windows)
            } catch {
                teamsLog.warning("SCShareableContent indisponible: \(error.localizedDescription)")
                // On retombe sur le premier plan plutôt que de conclure « absent ».
            }
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              Self.teamsBundleIdentifiers.contains(bundleID) else { return nil }
        return Self.teamsWindowTitle(in: [(bundleID: bundleID, title: frontmostWindowTitle(of: front) ?? "")])
    }

    /// Titre de la fenêtre principale de l'app donnée, via l'API d'accessibilité
    /// publique `NSRunningApplication` + `CGWindowListCopyWindowInfo`.
    private func frontmostWindowTitle(of app: NSRunningApplication) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == app.processIdentifier,
                  let name = info[kCGWindowName as String] as? String, !name.isEmpty else { continue }
            return name
        }
        return nil
    }
}
