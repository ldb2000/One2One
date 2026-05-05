import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("AppSettings — manager categories & defaults")
struct AppSettingsManagerCategoriesTests {

    @Test("Default categories returns the 8 expected entries when JSON is empty defaults")
    func defaultCategories() {
        let s = AppSettings()
        let cats = s.managerCategories
        #expect(cats == [
            "Risque", "Décision", "RH", "Projet",
            "Reconnaissance", "Blocage", "Information", "Demande"
        ])
    }

    @Test("Setting categories round-trips via JSON")
    func roundTrip() {
        let s = AppSettings()
        s.managerCategories = ["A", "B", "C"]
        #expect(s.managerCategories == ["A", "B", "C"])
        #expect(s.managerCategoriesJSON.contains("\"A\""))
    }

    @Test("Corrupted JSON falls back to default categories")
    func fallbackOnCorruption() {
        let s = AppSettings()
        s.managerCategoriesJSON = "{not-valid-json"
        #expect(s.managerCategories.count == 8)
        #expect(s.managerCategories.first == "Risque")
    }

    @Test("Empty array is preserved (user explicitly removed all)")
    func emptyArrayPreserved() {
        let s = AppSettings()
        s.managerCategories = []
        #expect(s.managerCategories == [])
    }

    @Test("managerName / managerEmail default empty")
    func defaultNameEmail() {
        let s = AppSettings()
        #expect(s.managerName == "")
        #expect(s.managerEmail == "")
    }

    @Test("managerReportPrompt defaults to non-empty template")
    func defaultPromptNonEmpty() {
        let s = AppSettings()
        #expect(!s.managerReportPrompt.isEmpty)
        #expect(s.managerReportPrompt == AppSettings.defaultManagerReportPrompt)
    }
}
