import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le bloc `CAPTURÉ CETTE SÉANCE` (capture `1b-mode-seance.png` :
/// `4 ACTIONS · 1 DÉCISION · 2 RISQUES`).
///
/// L'enjeu est « cette séance » : la réunion porte tout son historique, y
/// compris ce qui a été saisi la veille en préparation. Un compteur qui compte
/// autre chose que ce qu'il annonce est pire qu'absent.
@Suite("Capturé cette séance")
struct SessionCapturedSummaryTests {

    private let ouverture = Date(timeIntervalSince1970: 1_788_506_100)

    @Test("L'enregistrement fixe l'origine, même s'il précède l'ouverture du mode")
    func sessionStart() {
        let debutEnreg = ouverture.addingTimeInterval(-300)
        #expect(SessionCapturedSummary.debutDeSeance(recordingStartedAt: debutEnreg,
                                                     ouvertureDuMode: ouverture) == debutEnreg)
        // Sans enregistrement, c'est l'ouverture du mode.
        #expect(SessionCapturedSummary.debutDeSeance(recordingStartedAt: nil,
                                                     ouvertureDuMode: ouverture) == ouverture)
        // Un enregistrement démarré *après* l'ouverture ne rétrécit pas la
        // séance : on garde la plus ancienne des deux origines.
        let apres = ouverture.addingTimeInterval(120)
        #expect(SessionCapturedSummary.debutDeSeance(recordingStartedAt: apres,
                                                     ouvertureDuMode: ouverture) == ouverture)
    }

    @Test("Ce qui précède le début de séance n'est pas compté")
    func onlyCountsSinceStart() {
        let avant = ouverture.addingTimeInterval(-60)
        let apres = ouverture.addingTimeInterval(60)
        #expect(SessionCapturedSummary.compte([avant, apres, apres], depuis: ouverture) == 2)
        // L'instant exact du début compte : la première note d'une séance est
        // souvent posée dans la seconde du démarrage.
        #expect(SessionCapturedSummary.compte([ouverture], depuis: ouverture) == 1)
    }

    @Test("Un horodatage absent ne compte pas")
    func nilDatesDoNotCount() {
        #expect(SessionCapturedSummary.compte([nil, nil], depuis: ouverture) == 0)
        #expect(SessionCapturedSummary.compte([nil, ouverture], depuis: ouverture) == 1)
    }

    @Test("Les trois compteurs de la capture")
    func counters() {
        let apres = ouverture.addingTimeInterval(60)
        let avant = ouverture.addingTimeInterval(-60)
        let compteurs = SessionCapturedSummary.compteurs(
            actions: [apres, apres, apres, apres, avant, nil],
            decisions: [apres, avant],
            risques: [apres, apres],
            depuis: ouverture
        )
        #expect(compteurs == SessionCapturedSummary.Compteurs(actions: 4, decisions: 1, risques: 2))
        #expect(!compteurs.estVide)
        #expect(SessionCapturedSummary.Compteurs().estVide)
    }

    @Test("Les libellés s'accordent en nombre")
    func labels() {
        #expect(SessionCapturedSummary.libelle(1, singulier: "DÉCISION", pluriel: "DÉCISIONS") == "DÉCISION")
        #expect(SessionCapturedSummary.libelle(2, singulier: "RISQUE", pluriel: "RISQUES") == "RISQUES")
        #expect(SessionCapturedSummary.libelle(0, singulier: "ACTION", pluriel: "ACTIONS") == "ACTIONS")
    }

    @MainActor
    @Test("Sur une réunion, seules les lignes de la séance sont comptées")
    func countersFromMeeting() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let reunion = Meeting(title: "[P25_110] Partage statut final", date: ouverture)
        context.insert(reunion)

        let ancienne = ActionTask(title: "Reprise de la veille")
        ancienne.createdAt = ouverture.addingTimeInterval(-3_600)
        let neuve = ActionTask(title: "Chiffrer la fin de migration")
        neuve.createdAt = ouverture.addingTimeInterval(30)
        for tache in [ancienne, neuve] {
            context.insert(tache)
            tache.meeting = reunion
        }

        let decision = MeetingNote(t: 663, text: "Le partenaire finalise", kind: .decision,
                                   createdAt: ouverture.addingTimeInterval(40))
        let note = MeetingNote(t: 252, text: "Gros morceau = AP", kind: .note,
                               createdAt: ouverture.addingTimeInterval(50))
        for ligne in [decision, note] {
            context.insert(ligne)
            ligne.meeting = reunion
        }

        let risque = ProjectAlert(title: "Comptes GitLab désactivés", severity: "Critique",
                                  date: ouverture.addingTimeInterval(60))
        let resolu = ProjectAlert(title: "Déjà traité", severity: "Faible",
                                  date: ouverture.addingTimeInterval(70))
        resolu.isResolved = true
        for alerte in [risque, resolu] {
            context.insert(alerte)
            alerte.meeting = reunion
        }

        let compteurs = SessionCapturedSummary.compteurs(meeting: reunion, depuis: ouverture)
        #expect(compteurs.actions == 1)
        #expect(compteurs.decisions == 1)
        #expect(compteurs.risques == 1)
    }
}

/// Le « `CP parle` » de la barre d'état (spec §2.6 : « locuteur courant …
/// sinon masqué »).
@Suite("Locuteur courant en séance")
struct SessionCurrentSpeakerTests {

    @Test("Deux initiales, majuscules, sur les deux premiers mots")
    func initials() {
        #expect(SessionCurrentSpeaker.initiales("Cédric Payet") == "CP")
        #expect(SessionCurrentSpeaker.initiales("Pierre-Yves Nallet") == "PY")
        #expect(SessionCurrentSpeaker.initiales("laurent deberti") == "LD")
        #expect(SessionCurrentSpeaker.initiales("Yann") == "Y")
        #expect(SessionCurrentSpeaker.initiales("") == "")
    }

    @Test("Le locuteur du tour qui couvre l'instant, et son libellé")
    func speakerAtT() {
        let tours: [(debut: Double, fin: Double, nom: String?)] = [
            (0, 100, "Pierre-Yves Nallet"),
            (100, 200, "Cédric Payet")
        ]
        #expect(SessionCurrentSpeaker.locuteur(tours: tours, t: 150)?.libelle == "CP parle")
        #expect(SessionCurrentSpeaker.locuteur(tours: tours, t: 50)?.nom == "Pierre-Yves Nallet")
    }

    @Test("La borne de fin est exclue : le silence n'a pas de locuteur")
    func exclusiveEnd() {
        let tours: [(debut: Double, fin: Double, nom: String?)] = [(0, 100, "Yann Meyer")]
        #expect(SessionCurrentSpeaker.locuteur(tours: tours, t: 99.9) != nil)
        #expect(SessionCurrentSpeaker.locuteur(tours: tours, t: 100) == nil)
        #expect(SessionCurrentSpeaker.locuteur(tours: tours, t: 120) == nil)
    }

    @Test("Un tour sans locuteur résolu est masqué, pas rendu en `?? parle`")
    func unresolvedIsHidden() {
        #expect(SessionCurrentSpeaker.locuteur(tours: [(0, 100, nil)], t: 50) == nil)
        #expect(SessionCurrentSpeaker.locuteur(tours: [(0, 100, "   ")], t: 50) == nil)
    }

    @Test("En cas de recouvrement, c'est le tour le plus récent qui parle")
    func overlap() {
        let tours: [(debut: Double, fin: Double, nom: String?)] = [
            (0, 200, "Pierre-Yves Nallet"),
            (100, 200, "Cédric Payet")
        ]
        #expect(SessionCurrentSpeaker.locuteur(tours: tours, t: 150)?.initiales == "CP")
    }

    @Test("Aucun tour, aucun locuteur")
    func noTurns() {
        #expect(SessionCurrentSpeaker.locuteur(tours: [], t: 10) == nil)
    }
}

/// La règle de sortie (spec §2.6 : « `Esc` demande confirmation si
/// l'enregistrement tourne »).
@Suite("Sortie du mode séance")
struct SessionExitPolicyTests {

    @Test("Sans enregistrement, `Esc` sort tout de suite")
    func exitsDirectly() {
        #expect(SessionExitPolicy.escape(isRecording: false, isConfirming: false) == .sortir)
    }

    @Test("Avec enregistrement, `Esc` demande confirmation")
    func asksConfirmation() {
        #expect(SessionExitPolicy.escape(isRecording: true, isConfirming: false)
                == .demanderConfirmation)
    }

    @Test("Le second `Esc` referme la confirmation, il ne la valide pas")
    func secondEscapeCancels() {
        #expect(SessionExitPolicy.escape(isRecording: true, isConfirming: true)
                == .fermerLaConfirmation)
        #expect(SessionExitPolicy.escape(isRecording: false, isConfirming: true)
                == .fermerLaConfirmation)
    }
}

/// L'état du mode : entrée, sortie, origine du temps de séance.
@Suite("État du mode séance")
@MainActor
struct SessionFullscreenStateTests {

    @Test("L'entrée fixe l'origine du temps, la sortie la conserve")
    func enterAndLeave() {
        let etat = SessionFullscreenState()
        #expect(!etat.isPresented)
        #expect(etat.enteredAt == nil)

        let instant = Date(timeIntervalSince1970: 1_788_506_100)
        etat.enter(now: instant)
        #expect(etat.isPresented)
        #expect(etat.enteredAt == instant)

        etat.leave()
        #expect(!etat.isPresented)
        // Une sortie suivie d'une rentrée dans la même séance ne remet pas les
        // compteurs à zéro.
        #expect(etat.enteredAt == instant)
    }

    @Test("Une seconde entrée ne redate pas la séance")
    func reentryKeepsOrigin() {
        let etat = SessionFullscreenState()
        let instant = Date(timeIntervalSince1970: 1_788_506_100)
        etat.enter(now: instant)
        etat.enter(now: instant.addingTimeInterval(600))
        #expect(etat.enteredAt == instant)
    }

    @Test("La sortie referme la confirmation et la feuille d'assignation")
    func leaveClosesEverything() {
        let etat = SessionFullscreenState()
        etat.enter()
        etat.isConfirmingExit = true
        etat.isAssigning = true
        etat.leave()
        #expect(!etat.isConfirmingExit)
        #expect(!etat.isAssigning)
    }

    @Test("Le modèle d'écran porte l'état du mode séance")
    func screenModelCarriesState() {
        let screen = MeetingScreenModel(defaults: UserDefaults(suiteName: "lot4.tests")!)
        #expect(!screen.session.isPresented)
        screen.session.enter()
        #expect(screen.session.isPresented)
    }
}

/// Les mentions `@Prénom` rendues en pilule dans la colonne de notes.
@Suite("Mentions en pilule")
struct SessionMentionRunsTests {

    /// Catalogue de test : trois prénoms reconnus, rien d'autre.
    private let connus = ["yann", "cedric", "pierre-yves"]

    private func estUneMention(_ nom: String) -> Bool {
        connus.contains(nom.slashSearchNormalized)
    }

    @Test("La ligne de la capture : un texte puis une mention")
    func capturedLine() {
        let runs = SessionMentionRuns.runs(
            in: "Timing de reprise à définir. Qui donne le feu vert ? @Yann",
            estUneMention: estUneMention)
        #expect(runs == [.texte("Timing de reprise à définir. Qui donne le feu vert ? "),
                         .mention("Yann")])
    }

    @Test("Un nom inconnu reste du texte : pas de pilule mensongère")
    func unknownStaysText() {
        let runs = SessionMentionRuns.runs(in: "Vu avec @Inconnu hier", estUneMention: estUneMention)
        #expect(runs == [.texte("Vu avec @Inconnu hier")])
    }

    @Test("Un `@` au milieu d'un mot n'ouvre pas de mention")
    func emailIsNotAMention() {
        let runs = SessionMentionRuns.runs(in: "yann@april.com", estUneMention: estUneMention)
        #expect(runs == [.texte("yann@april.com")])
    }

    @Test("La ponctuation collée reste dans la phrase")
    func trailingPunctuation() {
        let runs = SessionMentionRuns.runs(in: "À voir avec @Yann.", estUneMention: estUneMention)
        #expect(runs == [.texte("À voir avec "), .mention("Yann"), .texte(".")])
    }

    @Test("Un prénom composé est une seule mention")
    func compoundFirstName() {
        let runs = SessionMentionRuns.runs(in: "@Pierre-Yves confirme", estUneMention: estUneMention)
        #expect(runs == [.mention("Pierre-Yves"), .texte(" confirme")])
    }

    @Test("Deux mentions dans la même ligne")
    func twoMentions() {
        let runs = SessionMentionRuns.runs(in: "@Yann et @Cedric", estUneMention: estUneMention)
        #expect(runs == [.mention("Yann"), .texte(" et "), .mention("Cedric")])
    }

    @Test("Rien n'est perdu : les fragments recomposent la ligne")
    func lossless() {
        let lignes = [
            "Timing de reprise à définir. Qui donne le feu vert ? @Yann",
            "yann@april.com",
            "@Yann et @Cedric, cc @Inconnu.",
            "",
            "@",
            "Rien à signaler"
        ]
        for ligne in lignes {
            let recompose = SessionMentionRuns.runs(in: ligne, estUneMention: estUneMention)
                .map(\.brut)
                .joined()
            #expect(recompose == ligne, "la ligne « \(ligne) » a été altérée")
        }
    }

    @Test("Un `@` seul n'est pas une mention")
    func lonelyAt() {
        #expect(SessionMentionRuns.runs(in: "@", estUneMention: estUneMention) == [.texte("@")])
        #expect(SessionMentionRuns.runs(in: "@ Yann", estUneMention: estUneMention)
                == [.texte("@ Yann")])
    }
}
