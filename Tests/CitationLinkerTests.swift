import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La chaîne de citation (spec §8 : « le rapport rend ces références
/// cliquables »). Le motif porte sur le **balisage de l'app**
/// (`<code>mm:ss</code>`) et non sur le texte nu : c'est ce qui le rend sûr
/// dans un document où le modèle écrit aussi des horaires.
@Suite("Chaîne de citation — timecodes cliquables")
struct CitationLinkerTests {

    private let reunion = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000001")!

    @Test("L'URL porte la réunion, les secondes et la note quand il y en a une")
    func urlComplete() {
        #expect(CitationLinker.url(meetingStableID: reunion, t: 252)
                == "onetoone://meeting/\(reunion.uuidString)?t=252")
        let note = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000002")!
        #expect(CitationLinker.url(meetingStableID: reunion, t: 252, noteStableID: note)
                == "onetoone://meeting/\(reunion.uuidString)?t=252&note=\(note.uuidString)")
    }

    @Test("Un timecode se relit en secondes, mm:ss comme h:mm:ss")
    func lectureDesTimecodes() {
        #expect(CitationLinker.seconds(fromTimecode: "04:12") == 252)
        #expect(CitationLinker.seconds(fromTimecode: "1:02:33") == 3753)
        #expect(CitationLinker.seconds(fromTimecode: "pas un timecode") == nil)
        // Minutes et secondes s'écrivent sur deux chiffres et restent sous 60.
        #expect(CitationLinker.seconds(fromTimecode: "12:345") == nil)
        #expect(CitationLinker.seconds(fromTimecode: "04:75") == nil)
    }

    @Test("En interne, chaque <code>mm:ss</code> devient un lien avec sa flèche")
    func lienInterne() {
        let html = "<li><code>04:12</code> Chiffrage_Marine_v3.xlsx</li>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie.contains(
            "<a class=\"tc\" href=\"onetoone://meeting/\(reunion.uuidString)?t=252\">"))
        #expect(sortie.contains("04:12 ↗"))
        #expect(!sortie.contains("<code>04:12</code>"))
    }

    @Test("Une note nommée par data-note voyage dans l'URL")
    func lienVersUneNote() {
        let note = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000003")!
        let html = "<li><code data-note=\"\(note.uuidString)\">02:00</code> Point</li>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie.contains("?t=120&note=\(note.uuidString)"))
    }

    /// « Les schémas privés n'ont pas de sens hors machine » : à l'export, le
    /// timecode reste du texte, sans lien mort ni balise inutile.
    @Test("À l'export externe, le timecode reste du texte")
    func exportSansLien() {
        let html = "<li><code>04:12</code> Chiffrage_Marine_v3.xlsx</li>"
        let sortie = CitationLinker.link(html, mode: .plainText)
        #expect(!sortie.contains("onetoone://"))
        #expect(!sortie.contains("<a "))
        #expect(sortie.contains("04:12"))
    }

    @Test("Un horaire dans une phrase libre n'est pas transformé en lien")
    func aucunFauxPositif() {
        let html = "<p>Le point est reporté à 14:30, après la démo de 9:05.</p>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie == html)
    }

    @Test("Un code qui n'est pas un timecode reste un code")
    func codeNonTimecode() {
        let html = "<p><code>P25_110</code> et <code>12:345</code></p>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie == html)
    }

    @Test("Plusieurs citations sur la même ligne sont toutes liées")
    func plusieursCitations() {
        let html = "<li><code>04:12</code> et <code>1:02:33</code></li>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie.contains("?t=252"))
        #expect(sortie.contains("?t=3753"))
    }
}

/// Ouvrir une citation : décodage pur, puis déplacement de la tête de lecture.
@Suite("Ouverture d'une citation")
struct CitationURLHandlingTests {

    private let reunion = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000001")!

    @Test("L'URL produite par le linker se relit sans perte")
    func allerRetour() {
        let note = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000002")!
        let brute = CitationLinker.url(meetingStableID: reunion, t: 252, noteStableID: note)
        let citation = QuickLaunchURLHandler.parseCitation(URL(string: brute)!)
        #expect(citation?.meetingStableID == reunion)
        #expect(citation?.t == 252)
        #expect(citation?.noteStableID == note)
    }

    @Test("Sans t, la citation ouvre la réunion sans déplacer la tête de lecture")
    func sansTimecode() {
        let citation = QuickLaunchURLHandler.parseCitation(
            URL(string: "onetoone://meeting/\(reunion.uuidString)")!)
        #expect(citation?.meetingStableID == reunion)
        #expect(citation?.t == nil)
    }

    @Test("Un schéma étranger ou un UUID cassé ne mène nulle part")
    func urlRefusees() {
        #expect(QuickLaunchURLHandler.parseCitation(URL(string: "https://exemple.fr/x")!) == nil)
        #expect(QuickLaunchURLHandler.parseCitation(
            URL(string: "onetoone://meeting/pas-un-uuid")!) == nil)
        #expect(QuickLaunchURLHandler.parseCitation(
            URL(string: "onetoone://collaborator/\(UUID().uuidString)")!) == nil)
    }

    @Test("La tête de lecture se déplace au timecode de la citation")
    @MainActor
    func seekAuTimecode() {
        let playhead = MeetingPlayhead(meetingStableID: reunion)
        playhead.duration = 600
        playhead.seek(to: 252)
        #expect(playhead.t == 252)
    }
}
