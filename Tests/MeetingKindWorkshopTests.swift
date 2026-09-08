import Testing
@testable import OneToOne

@Suite("Type de réunion — l'Atelier s'ajoute sans toucher aux valeurs existantes")
struct MeetingKindWorkshopTests {

    @Test("Le type Atelier existe, se décode depuis sa valeur brute et porte son libellé")
    func atelierPresent() {
        #expect(MeetingKind(rawValue: "workshop") == .workshop)
        #expect(MeetingKind.workshop.label == "Atelier")
        #expect(!MeetingKind.workshop.sfSymbol.isEmpty)
    }

    /// Les valeurs brutes sont persistées dans `Meeting.kindRaw` : les renommer
    /// transformerait silencieusement toutes les réunions en `.global` (le
    /// repli du wrapper calculé).
    @Test("Les six valeurs brutes historiques sont inchangées")
    func valeursBrutesHistoriquesIntactes() {
        #expect(MeetingKind.global.rawValue == "global")
        #expect(MeetingKind.project.rawValue == "project")
        #expect(MeetingKind.oneToOne.rawValue == "oneToOne")
        #expect(MeetingKind.work.rawValue == "work")
        #expect(MeetingKind.manager.rawValue == "manager")
        #expect(MeetingKind.note.rawValue == "note")
        #expect(MeetingKind.allCases.count == 7)
    }
}
