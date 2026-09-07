import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La barre du haut de l'écran de séance 1:1 (capture 2a) :
/// `One2One › Mon équipe › [1:1] Laurent NOMINÉ — entretien du 4 septembre`,
/// la pilule `● Privé — vous deux` et le bouton `Rapport 1:1 ✓`.
///
/// Le lot 10 avait posé la teinte et le badge de type ; ce lot ajoute les trois
/// éléments propres à la séance, tous dérivés de fonctions pures pour être
/// vérifiables sans monter la barre.
@Suite("Barre du haut — écran de séance 1:1")
@MainActor
struct OneOnOneTopChromeSessionTests {

    private static var seance: Date { RefonteDemoSeed.oneOnOneSeedDate }

    @Test("Le segment d'équipe n'apparaît que pour un 1:1 mené")
    func segmentDEquipe() {
        #expect(MeetingTopChromeBar.teamSegmentLabel(for: .oneToOne) == "Mon équipe")
        // Un 1:1 subi ne se range pas dans « mon équipe » : c'est l'écran 5a,
        // et son fil d'Ariane est celui du lot 13.
        #expect(MeetingTopChromeBar.teamSegmentLabel(for: .manager) == nil)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.teamSegmentLabel(for: kind) == nil)
        }
    }

    @Test("La pilule de confidentialité est celle de la capture")
    func piluleDeConfidentialite() {
        #expect(MeetingTopChromeBar.privacyPillLabel(for: .oneToOne) == "● Privé — vous deux")
        // Côté collaborateur, c'est la pilule de rôle qui est obligatoire
        // (lot 10, D4) : deux pilules violettes côte à côte diraient deux fois
        // la même chose.
        #expect(MeetingTopChromeBar.privacyPillLabel(for: .manager) == nil)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.privacyPillLabel(for: kind) == nil)
        }
    }

    @Test("Le bouton de rapport dit « Rapport 1:1 » en entretien")
    func libelleDeRapport() {
        #expect(MeetingTopChromeBar.reportBaseLabel(for: .oneToOne) == "Rapport 1:1")
        #expect(MeetingTopChromeBar.reportBaseLabel(for: .manager) == "Rapport 1:1")
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.reportBaseLabel(for: kind) == "Rapport")
        }
    }

    @Test("L'en-tête d'entretien nomme la personne et le jour")
    func enteteDEntretien() {
        #expect(MeetingTopChromeBar.oneOnOneSessionHeading(person: "Laurent NOMINÉ",
                                                           date: Self.seance)
                == "Laurent NOMINÉ — entretien du 4 septembre")
        // Sans participant connu, on ne fabrique pas un nom : le jour suffit.
        #expect(MeetingTopChromeBar.oneOnOneSessionHeading(person: "", date: Self.seance)
                == "Entretien du 4 septembre")
    }

    @Test("L'en-tête dérivé sert de placeholder du titre, il ne l'écrase pas")
    func placeholderDuTitre() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let laurent = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        context.insert(laurent)
        let seance = Meeting(title: "", date: Self.seance, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(laurent)
        try context.save()

        // Un entretien sans titre s'annonce comme la capture…
        #expect(MeetingTopChromeBar.titlePlaceholder(for: seance)
                == "Laurent NOMINÉ — entretien du 4 septembre")
        // …et le titre reste **éditable** : le renommer est un geste que la
        // barre ne doit pas retirer, c'est son seul point d'entrée dans
        // l'application.
        seance.title = "1:1 de crise"
        #expect(seance.title == "1:1 de crise")
        #expect(MeetingTopChromeBar.titlePlaceholder(for: seance)
                == "Laurent NOMINÉ — entretien du 4 septembre")

        // Les autres types gardent le placeholder générique.
        let comite = Meeting(title: "", date: Self.seance, notes: "")
        comite.kind = .global
        context.insert(comite)
        #expect(MeetingTopChromeBar.titlePlaceholder(for: comite) == "Titre de la réunion…")
    }
}
