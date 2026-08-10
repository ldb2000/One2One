import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Verrouille `Meeting.noteDisplayTitle` / `Meeting.notePreview`
/// (`NoteDisplay.swift`) : logique partagée par `AllNotesRow`
/// (`AllNotesView.swift`) et `NoteRow` (`NotesSection.swift`).
@Suite("Meeting.noteDisplayTitle / notePreview — dérivation d'affichage d'une note")
struct NoteDisplayTests {

    @Test("Une note titrée rend son titre")
    func titledNoteRendersItsTitle() {
        let note = NoteFactory.make(body: "Contenu du corps.", title: "Décisions du comité")
        #expect(note.noteDisplayTitle == "Décisions du comité")
    }

    @Test("Une note sans titre rend la première ligne du corps")
    func untitledNoteRendersFirstBodyLine() {
        let note = NoteFactory.make(body: "Première ligne\nDeuxième ligne")
        #expect(note.noteDisplayTitle == "Première ligne")
    }

    @Test("Une note vide rend « Sans titre »")
    func emptyNoteRendersFallback() {
        let note = NoteFactory.make(body: "")
        #expect(note.noteDisplayTitle == "Sans titre")
    }

    @Test("L'aperçu saute la première ligne quand elle sert de titre")
    func previewSkipsFirstLineWhenUsedAsTitle() {
        let note = NoteFactory.make(body: "Première ligne\nDeuxième ligne\nTroisième ligne")
        #expect(note.notePreview == "Deuxième ligne Troisième ligne")
    }

    @Test("L'aperçu ne saute pas la première ligne quand un vrai titre existe")
    func previewKeepsFirstLineWhenTitleExists() {
        let note = NoteFactory.make(body: "Première ligne\nDeuxième ligne",
                                     title: "Décisions du comité")
        #expect(note.notePreview == "Première ligne Deuxième ligne")
    }
}
