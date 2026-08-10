import Foundation
import CoreSpotlight
import SwiftData

/// Décode un `NSUserActivity` Spotlight (clic sur résultat collaborateur ou
/// résultat réunion/note) vers un appel `QuickLaunchRouter`.
enum QuickLaunchURLHandler {

    /// Décode l'`NSUserActivity` issu d'un clic sur un résultat Spotlight.
    /// N'agit que sur les activités `CSSearchableItemActionType` dont
    /// l'identifiant a le format `"collaborator-<UUID>"` (lance un 1:1 avec
    /// enregistrement) ou `"meeting-<UUID>"` (ouvre la réunion — ou la note,
    /// une note étant une réunion de kind `.note` — existante, sans
    /// enregistrer). Tout autre type, préfixe inconnu, UUID mal formé ou
    /// modèle introuvable provoque un retour silencieux (loggé pour les deux
    /// derniers cas).
    @MainActor
    static func handle(activity: NSUserActivity,
                       router: QuickLaunchRouter,
                       context: ModelContext) {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return }

        if identifier.hasPrefix("collaborator-") {
            handleCollaborator(identifier: identifier, router: router, context: context)
        } else if identifier.hasPrefix("meeting-") {
            handleMeeting(identifier: identifier, router: router, context: context)
        }
    }

    @MainActor
    private static func handleCollaborator(identifier: String,
                                            router: QuickLaunchRouter,
                                            context: ModelContext) {
        let uuidString = String(identifier.dropFirst("collaborator-".count))
        guard let uuid = UUID(uuidString: uuidString) else { return }

        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        guard let collab = try? context.fetch(descriptor).first else {
            print("[QuickLaunchURLHandler] no Collaborator for stableID \(uuid)")
            return
        }

        router.startOneToOne(collaborator: collab,
                             autoStartRecording: true,
                             in: context)
    }

    @MainActor
    private static func handleMeeting(identifier: String,
                                       router: QuickLaunchRouter,
                                       context: ModelContext) {
        let uuidString = String(identifier.dropFirst("meeting-".count))
        guard let uuid = UUID(uuidString: uuidString) else { return }

        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        guard let meeting = try? context.fetch(descriptor).first else {
            print("[QuickLaunchURLHandler] no Meeting for stableID \(uuid)")
            return
        }

        router.openMeeting(meeting)
    }
}
