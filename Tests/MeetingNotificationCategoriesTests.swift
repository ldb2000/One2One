import Testing
import Foundation
import UserNotifications
@testable import OneToOne

/// `setNotificationCategories` remplace l'ensemble enregistré. Ces tests
/// garantissent que les catégories Teams s'**ajoutent** aux catégories réunion
/// au lieu de les écraser — une régression qui, sans test, ne se verrait qu'à
/// l'usage, sous la forme de notifications sans boutons.
@Suite("MeetingNotificationService — catalogue de catégories")
struct MeetingNotificationCategoriesTests {

    @Test("Les neuf catégories sont enregistrées ensemble")
    func allCategoriesPresent() {
        let ids = Set(MeetingNotificationService.makeCategories().map(\.identifier))
        #expect(ids == [
            "MEETING_PRE_START", "MEETING_START", "MEETING_END", "RECORDING_STARTED",
            "TEAMS_CALL_DETECTED", "TEAMS_CALL_LINK", "TEAMS_CALL_ENDED",
            "TEAMS_TRANSCRIPT_READY", "TEAMS_RECORDING_ERROR"
        ])
    }

    @Test("Aucun identifiant de catégorie en double")
    func noDuplicateIdentifiers() {
        let all = MeetingNotificationService.makeCategories().map(\.identifier)
        #expect(all.count == Set(all).count)
    }

    @Test("Le popup de détection propose démarrer, snooze et ignorer")
    func detectedCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_CALL_DETECTED" }
        #expect(category?.actions.map(\.identifier) == ["START_RECORD", "SNOOZE_TEAMS_5", "DISMISS_TEAMS"])
    }

    @Test("Le popup de liaison propose de lier ou d'ignorer")
    func linkCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_CALL_LINK" }
        #expect(category?.actions.map(\.identifier) == ["LINK_TO_CURRENT", "DISMISS_TEAMS"])
    }

    @Test("Le popup de fin propose arrêter et continuer")
    func endedCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_CALL_ENDED" }
        #expect(category?.actions.map(\.identifier) == ["STOP_AND_FINALIZE", "CONTINUE_RECORDING"])
    }

    @Test("Le popup de transcription prête propose générer et plus tard")
    func transcriptCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_TRANSCRIPT_READY" }
        #expect(category?.actions.map(\.identifier) == ["GENERATE_REPORT", "SKIP_REPORT"])
    }
}
