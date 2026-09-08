import Testing
@testable import OneToOne

/// `ActionsViewMode` a quitté `ActionsPanel.swift` pour `Models/` (programme
/// §2.1). Le rail de réunion n'en garde que trois cas (spec §2.5), mais l'écran
/// `ActionsListView` garde les cinq : ce sont deux listes distinctes, et rien ne
/// le dit à part ces tests.
@Suite("Modes d'affichage des actions")
struct ActionsViewModeTests {

    @Test("Le rail n'expose que Liste, Calendrier et Eisenhower")
    func railCases() {
        #expect(ActionsViewMode.railCases == [.liste, .calendar, .eisenhower])
        #expect(!ActionsViewMode.railCases.contains(.kanban))
        #expect(!ActionsViewMode.railCases.contains(.sticky))
    }

    @Test("Les cinq cas restent : ActionsListView propose encore Kanban et Post-it")
    func allCasesUnchanged() {
        #expect(ActionsViewMode.allCases.count == 5)
        #expect(ActionsViewMode.allCases.contains(.kanban))
        #expect(ActionsViewMode.allCases.contains(.sticky))
    }

    @Test("Les valeurs brutes sont inchangées : elles sont mémorisées")
    func rawValues() {
        #expect(ActionsViewMode.liste.rawValue == "liste")
        #expect(ActionsViewMode.calendar.rawValue == "calendar")
        #expect(ActionsViewMode.eisenhower.rawValue == "eisenhower")
        #expect(ActionsViewMode(rawValue: "kanban") == .kanban)
        #expect(ActionsViewMode(rawValue: "inconnu") == nil)
    }

    @Test("Les libellés sont ceux de la capture 1a")
    func labels() {
        #expect(ActionsViewMode.liste.label == "Liste")
        #expect(ActionsViewMode.calendar.label == "Calendrier")
        #expect(ActionsViewMode.eisenhower.label == "Eisenhower")
    }
}
