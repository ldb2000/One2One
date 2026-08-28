import Testing
import Foundation
@testable import OneToOne

/// Le moniteur choisit une fenêtre parmi celles que le système lui présente.
/// C'est la seule décision de la classe qui puisse se tromper silencieusement,
/// donc la seule qu'on isole en fonction pure.
@Suite("TeamsCallMonitor — sélection de la fenêtre Teams")
struct TeamsCallMonitorTests {

    @Test("Une fenêtre Teams dont le titre évoque un appel est retenue")
    func picksCallWindow() {
        let windows = [
            (bundleID: "com.apple.Safari", title: "Réunion budget"),
            (bundleID: "com.microsoft.teams2", title: "Réunion hebdo | Microsoft Teams")
        ]
        #expect(TeamsCallMonitor.teamsWindowTitle(in: windows) == "Réunion hebdo | Microsoft Teams")
    }

    @Test("Les deux identifiants de bundle Teams sont acceptés")
    func acceptsBothBundleIdentifiers() {
        #expect(TeamsCallMonitor.teamsWindowTitle(
            in: [(bundleID: "com.microsoft.teams", title: "Weekly call")]) == "Weekly call")
    }

    @Test("Une fenêtre Teams de discussion n'est pas retenue")
    func ignoresChatWindow() {
        #expect(TeamsCallMonitor.teamsWindowTitle(
            in: [(bundleID: "com.microsoft.teams2", title: "Discussion | Microsoft Teams")]) == nil)
    }

    @Test("Une fenêtre non-Teams au titre évocateur n'est pas retenue")
    func ignoresNonTeamsApp() {
        #expect(TeamsCallMonitor.teamsWindowTitle(
            in: [(bundleID: "com.apple.Safari", title: "Réunion hebdo")]) == nil)
    }

    @Test("Aucune fenêtre → rien")
    func emptyList() {
        #expect(TeamsCallMonitor.teamsWindowTitle(in: []) == nil)
    }
}
