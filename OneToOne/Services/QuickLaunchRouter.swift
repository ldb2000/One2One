import Foundation
import SwiftData
import AppKit

/// Routeur central pour les lancements rapides de 1:1.
/// Tous les déclencheurs (Spotlight handler, AppIntent, hotkey, menu
/// contextuel) appellent `startOneToOne(...)`. SwiftUI observe
/// `pendingToken` pour ouvrir la fenêtre dédiée; `listFilterCollaborator`
/// pour appliquer le filtre dans `MeetingsListView`.
@MainActor
final class QuickLaunchRouter: ObservableObject {

    static let shared = QuickLaunchRouter()

    /// Token consommé par `OneToOneApp` pour ouvrir un `WindowGroup`. Reset
    /// à `nil` après ouverture par `consumePendingToken()`.
    @Published var pendingToken: OneToOneLaunchToken?

    /// Collaborateur cible du filtre "Voir derniers 1:1" dans la liste
    /// des réunions. Reset à `nil` quand l'utilisateur ferme le filtre.
    @Published var listFilterCollaborator: Collaborator?

    /// Init privé pour le singleton; `testInstance()` ouvre une porte pour
    /// les tests qui ne doivent pas piétiner l'état partagé.
    private init() {}

    /// Crée un `Meeting` `kind=.oneToOne`, l'insère dans le contexte,
    /// active l'app, publie le token. Retourne le meeting créé.
    @discardableResult
    func startOneToOne(collaborator: Collaborator,
                       autoStartRecording: Bool,
                       in context: ModelContext) -> Meeting {
        let meeting = Meeting(
            title: "1:1 — \(collaborator.name)",
            date: Date(),
            notes: ""
        )
        meeting.kind = .oneToOne
        context.insert(meeting)
        meeting.participants = [collaborator]

        do {
            try context.save()
        } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }

        NSApp?.activate(ignoringOtherApps: true)

        pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: autoStartRecording
        )
        return meeting
    }

    /// Creates a `kind=.global` meeting with no participants and publishes
    /// a launch token that opens the 1to1-meeting window with recording on.
    @discardableResult
    func startAdHocMeeting(in context: ModelContext) -> Meeting {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let meeting = Meeting(
            title: "Réunion ad-hoc \(formatter.string(from: Date()))",
            date: Date()
        )
        meeting.kind = .global
        context.insert(meeting)
        do { try context.save() } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }

        NSApp?.activate(ignoringOtherApps: true)
        pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: true
        )
        return meeting
    }

    /// Same as `startOneToOne` but stamps `kind=.manager`. Caller provides
    /// the manager collaborator (resolved from `AppSettings.managerEmail`).
    @discardableResult
    func startManagerMeeting(collaborator: Collaborator,
                              in context: ModelContext) -> Meeting {
        let meeting = Meeting(
            title: "1:1 Manager — \(collaborator.name)",
            date: Date()
        )
        meeting.kind = .manager
        context.insert(meeting)
        meeting.participants = [collaborator]
        do { try context.save() } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }

        NSApp?.activate(ignoringOtherApps: true)
        pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: true
        )
        return meeting
    }

    /// Consommé par la vue qui ouvre la fenêtre — reset le token pour ne
    /// pas re-tirer.
    func consumePendingToken() -> OneToOneLaunchToken? {
        let t = pendingToken
        pendingToken = nil
        return t
    }

    /// Active le filtre "1:1 avec X" dans `MeetingsListView`. Ne touche pas
    /// au token de lancement (les deux flux peuvent coexister).
    func showRecentOneToOnes(for collaborator: Collaborator) {
        listFilterCollaborator = collaborator
        NSApp?.activate(ignoringOtherApps: true)
    }
}

// MARK: - Test helpers

#if DEBUG
extension QuickLaunchRouter {
    /// Crée une instance dédiée aux tests, isolée du singleton partagé.
    static func testInstance() -> QuickLaunchRouter {
        QuickLaunchRouter()
    }
}
#endif
