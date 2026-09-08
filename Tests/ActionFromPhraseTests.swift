import Testing
import Foundation
@testable import OneToOne

/// « Créer une action depuis une phrase de transcription prend un clic »
/// (spec §2.4, critère d'acceptation n° 2 du chantier 1).
///
/// Le nettoyage est pur : c'est le seul moyen de vérifier qu'une phrase
/// hésitante devient un titre d'action lisible sans lancer d'interface ni de
/// modèle de langue. Le lexique reste **court et français** : une liste longue
/// finirait par réécrire des phrases qu'elle n'a pas comprises.
@Suite("Une action depuis une phrase de transcription")
struct ActionFromPhraseTests {

    @Test("« il faut » devient un infinitif en tête")
    func ilFaut() {
        #expect(ActionFromPhrase.title(from: "il faut remettre ça en route et vérifier les droits.")
                == "Remettre ça en route et vérifier les droits")
    }

    @Test("« on doit » aussi")
    func onDoit() {
        #expect(ActionFromPhrase.title(from: "on doit chiffrer la fin de migration.")
                == "Chiffrer la fin de migration")
    }

    @Test("Les hésitations de tête tombent")
    func hesitations() {
        #expect(ActionFromPhrase.title(from: "euh, donc il faut vérifier l'état des comptes GitLab.")
                == "Vérifier l'état des comptes GitLab")
        #expect(ActionFromPhrase.title(from: "bah euh donc on doit valider") == "Valider")
    }

    @Test("Les guillemets encadrants tombent")
    func guillemets() {
        #expect(ActionFromPhrase.title(from: "« Synchroniser les pipelines »")
                == "Synchroniser les pipelines")
        #expect(ActionFromPhrase.title(from: "\"Relancer Alexis\"") == "Relancer Alexis")
    }

    @Test("Sans amorce d'obligation, la phrase est seulement nettoyée et capitalisée")
    func sansAmorce() {
        #expect(ActionFromPhrase.title(from: "tous les comptes ont été désactivés")
                == "Tous les comptes ont été désactivés")
    }

    @Test("« il faudrait » et « faut » sont reconnus")
    func variantes() {
        #expect(ActionFromPhrase.title(from: "il faudrait relancer Alexis") == "Relancer Alexis")
        #expect(ActionFromPhrase.title(from: "faut planifier la formation")
                == "Planifier la formation")
    }

    @Test("Une amorce suivie de « que » n'est pas retirée : ce n'est pas un infinitif")
    func amorceAvecQue() {
        // « Le partenaire finalise » n'est pas une action confiée à quelqu'un :
        // amputer l'amorce produirait un titre faux.
        #expect(ActionFromPhrase.title(from: "il faut que le partenaire finalise")
                == "Il faut que le partenaire finalise")
    }

    @Test("Une amorce suivie d'un mot qui n'est pas un infinitif reste entière")
    func amorceSansInfinitif() {
        #expect(ActionFromPhrase.title(from: "il faut deux semaines de plus")
                == "Il faut deux semaines de plus")
    }

    @Test("Une phrase vide ne produit pas de titre")
    func vide() {
        #expect(ActionFromPhrase.title(from: "   ").isEmpty)
        #expect(ActionFromPhrase.title(from: "euh, donc").isEmpty)
    }

    @Test("Un titre trop long est coupé au mot")
    func tropLong() {
        let phrase = String(repeating: "reprendre l'état des lieux ", count: 20)
        let titre = ActionFromPhrase.title(from: phrase)
        #expect(titre.count <= ActionFromPhrase.maxTitleLength + 1)
        #expect(titre.hasSuffix("…"))
        #expect(!titre.contains("  "))
    }

    @Test("Le brouillon conserve la source et le locuteur")
    @MainActor
    func brouillon() {
        let id = UUID()
        let locuteur = Collaborator(name: "Laurent Deberti", role: "Manager")
        let d = ActionFromPhrase.draft(phrase: "il faut vérifier les droits.",
                                       stableID: id, t: 252, speaker: locuteur)
        #expect(d.title == "Vérifier les droits")
        #expect(d.sourceRef?.kind == .transcript)
        #expect(d.sourceRef?.stableID == id)
        #expect(d.sourceRef?.t == 252)
        #expect(d.suggestedOwner === locuteur)
    }

    @Test("Sans locuteur résolu, le responsable reste vide plutôt que devinné")
    @MainActor
    func sansLocuteur() {
        let d = ActionFromPhrase.draft(phrase: "chiffrer la fin", stableID: UUID(), t: 0)
        #expect(d.suggestedOwner == nil)
        #expect(d.title == "Chiffrer la fin")
    }

    @Test("La citation reprend le texte, le locuteur et le timecode")
    func citation() {
        #expect(ActionFromPhrase.quotation(phrase: "il faut vérifier les droits.",
                                           speakerName: "Laurent", t: 252)
                == "« il faut vérifier les droits. » — Laurent, 04:12")
        #expect(ActionFromPhrase.quotation(phrase: "texte", speakerName: nil, t: 0)
                == "« texte » — 00:00")
    }

    @Test("Le texte d'une décision garde la phrase, sans mise à l'infinitif")
    func texteDeDecision() {
        // Une décision se lit au passé (« le partenaire finalise ») : la
        // transformer en infinitif en ferait une action, pas une décision.
        #expect(ActionFromPhrase.decisionText(from: "il faut que le partenaire finalise la migration.")
                == "Il faut que le partenaire finalise la migration")
        #expect(ActionFromPhrase.decisionText(from: "on doit chiffrer avant le 11")
                == "On doit chiffrer avant le 11")
    }
}
