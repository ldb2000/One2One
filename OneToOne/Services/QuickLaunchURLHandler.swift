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
    /// modèle introuvable provoque un retour sans effet ; seul le modèle
    /// introuvable est journalisé — un UUID mal formé sort en silence.
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

// MARK: - Citations `onetoone://` (lot 15)

extension QuickLaunchURLHandler {

    /// Une citation décodée depuis `onetoone://meeting/<uuid>?t=252&note=<uuid>`
    /// — ce que `CitationLinker` écrit dans le HTML du rapport.
    ///
    /// Le schéma est **privé et non enregistré auprès de macOS** : rien ne peut
    /// ouvrir l'app par cette URL depuis l'extérieur, et c'est voulu. Ces liens
    /// ne vivent que dans l'aperçu du rapport, où le délégué de navigation de
    /// `MeetingReportPreview` les intercepte ; l'export externe garde le
    /// timecode en texte (spec §8).
    struct MeetingCitation: Equatable {
        var meetingStableID: UUID
        var t: Double?
        var noteStableID: UUID?
    }

    /// Décode l'URL. Fonction pure. `nil` pour tout ce qui n'est pas une
    /// citation de réunion : un autre schéma, un autre hôte, un UUID mal formé.
    static func parseCitation(_ url: URL) -> MeetingCitation? {
        guard url.scheme == "onetoone", url.host == "meeting" else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)
        guard let premier = segments.first, let id = UUID(uuidString: premier) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let t = items.first { $0.name == "t" }?.value.flatMap(Double.init)
        let note = items.first { $0.name == "note" }?.value.flatMap(UUID.init(uuidString:))
        return MeetingCitation(meetingStableID: id, t: t, noteStableID: note)
    }

    /// Ouvre la réunion citée et, si un `t` est donné, déplace la tête de
    /// lecture.
    ///
    /// `playhead` est **injectée** et non retrouvée : une `MeetingPlayhead`
    /// appartient à l'état d'un écran monté (`MeetingScreenModel`), et aucun
    /// registre ne l'expose — le registre statique du lot 0B a justement été
    /// retiré. Une citation vers une **autre** réunion ouvre donc sa fenêtre
    /// sans se placer au timecode : mieux vaut cela qu'un faux registre qui
    /// donnerait la tête de lecture d'un écran fermé.
    ///
    /// Rend `false` quand l'URL n'est pas une citation ou que la réunion n'est
    /// pas en base — l'appelant peut alors laisser le lien suivre son cours.
    @MainActor
    @discardableResult
    static func handle(url: URL,
                       router: QuickLaunchRouter,
                       context: ModelContext,
                       playhead: MeetingPlayhead? = nil) -> Bool {
        guard let citation = parseCitation(url) else { return false }
        let cible = citation.meetingStableID

        // Même réunion que l'écran courant : on se contente de déplacer la tête
        // de lecture, sans rouvrir une fenêtre déjà ouverte.
        if let playhead, playhead.meetingStableID == cible {
            if let t = citation.t { playhead.seek(to: t) }
            return true
        }

        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.stableID == cible })
        guard let meeting = try? context.fetch(descriptor).first else {
            print("[QuickLaunchURLHandler] no Meeting for citation \(cible)")
            return false
        }
        router.openMeeting(meeting)
        return true
    }
}
