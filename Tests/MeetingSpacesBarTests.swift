import Testing
import Foundation
@testable import OneToOne

/// La barre d'espaces, spec §2.2 : 34 px, les trois espaces à gauche (onglet
/// actif souligné 2 px `accent/report`), le sélecteur de mode et la date à
/// droite.
///
/// Le principe §1.1 « aucun onglet vide » est vérifiable ici : **toute** entrée
/// de navigation porte un compteur ou un état. C'est le libellé qui le
/// garantit, pas la vue.
@Suite("Barre d'espaces")
struct MeetingSpacesBarTests {

    @Test("Hauteur de 34 px et soulignement de 2 px, comme la spec §2.2")
    func geometry() {
        #expect(MeetingSpacesBar.height == 34)
        #expect(MeetingSpacesBar.underlineHeight == 2)
    }

    @Test("Chaque espace porte un compteur ou un état, jamais rien (spec §1.1)")
    func everySpaceCarriesACounter() {
        #expect(MeetingSpacesBar.label(for: .meeting, kind: .project,
                                        hasReport: false, documentsCount: 0).titre == "Réunion")
        #expect(MeetingSpacesBar.label(for: .report, kind: .project,
                                        hasReport: false, documentsCount: 0).complement == "à générer")
        #expect(MeetingSpacesBar.label(for: .report, kind: .project,
                                        hasReport: true, documentsCount: 0).complement == "✓")
        #expect(MeetingSpacesBar.label(for: .resources, kind: .project,
                                        hasReport: true, documentsCount: 0).complement == "0 doc")
        #expect(MeetingSpacesBar.label(for: .resources, kind: .project,
                                        hasReport: true, documentsCount: 1).complement == "1 doc")
        #expect(MeetingSpacesBar.label(for: .resources, kind: .project,
                                        hasReport: true, documentsCount: 7).complement == "7 docs")
    }

    @Test("Le libellé de l'espace Réunion suit le type : « Note » pour une note")
    func meetingLabelFollowsKind() {
        #expect(MeetingSpacesBar.label(for: .meeting, kind: .note,
                                        hasReport: false, documentsCount: 0).titre == "Note")
    }

    @Test("Les libellés des modes sont ceux de la capture")
    func modeLabels() {
        #expect(MeetingScreenModel.Mode.prepare.label == "Préparer")
        #expect(MeetingScreenModel.Mode.live.label == "En séance")
        #expect(MeetingScreenModel.Mode.review.label == "Relire")
    }

    @Test("La date s'écrit comme sur la capture : « 4 sept. 2026 · 9:15 »")
    func dateFormat() {
        // Composants explicites : la locale du poste ne doit pas décider du
        // séparateur — la capture fait foi.
        var composants = DateComponents()
        composants.year = 2026
        composants.month = 9
        composants.day = 4
        composants.hour = 9
        composants.minute = 15
        let calendrier = Calendar(identifier: .gregorian)
        let date = calendrier.date(from: composants)!
        let rendu = MeetingSpacesBar.formatDate(date, locale: Locale(identifier: "fr_FR"))
        #expect(rendu.contains("·"))
        #expect(rendu.contains("2026"))
        #expect(rendu.contains("9:15"))
    }
}
