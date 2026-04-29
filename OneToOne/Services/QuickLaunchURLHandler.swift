import Foundation
import CoreSpotlight
import SwiftData

/// Décode un `NSUserActivity` Spotlight (clic sur résultat collaborateur)
/// vers un appel `QuickLaunchRouter.startOneToOne`.
enum QuickLaunchURLHandler {

    @MainActor
    static func handle(activity: NSUserActivity,
                       router: QuickLaunchRouter,
                       context: ModelContext) {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return }

        guard identifier.hasPrefix("collaborator-") else { return }
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
}
