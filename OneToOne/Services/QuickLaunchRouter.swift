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

    /// Sauvegarde le contexte en loggant (sans propager) toute erreur :
    /// un échec de save ne doit pas bloquer l'ouverture de la fenêtre.
    private func saveContext(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }
    }

    /// Active l'app au premier plan et publie le token de lancement
    /// (mutualise le pattern commun aux trois `start*()`).
    private func launchWith(meetingID: UUID, autoStartRecording: Bool) {
        NSApp?.activate(ignoringOtherApps: true)
        pendingToken = OneToOneLaunchToken(
            meetingID: meetingID,
            autoStartRecording: autoStartRecording
        )
    }

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

        saveContext(context)
        launchWith(meetingID: meeting.ensuredStableID,
                   autoStartRecording: autoStartRecording)
        return meeting
    }

    /// Crée un `Meeting` `kind=.global` (réunion ad-hoc sans participant) et
    /// publie un token qui ouvre la fenêtre avec enregistrement auto activé.
    /// Diffère de `startOneToOne` par le `kind` et l'absence de collaborateur.
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
        saveContext(context)
        launchWith(meetingID: meeting.ensuredStableID, autoStartRecording: true)
        return meeting
    }

    /// Comme `startOneToOne` mais marque `kind=.manager`. Au caller de fournir
    /// le collaborateur manager (résolu depuis `AppSettings.managerEmail`).
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
        saveContext(context)
        launchWith(meetingID: meeting.ensuredStableID, autoStartRecording: true)
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
