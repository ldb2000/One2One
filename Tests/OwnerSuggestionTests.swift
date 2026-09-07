import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La suggestion de responsable de la spec §2.5 : « locuteur de la phrase
/// source, puis dernier porteur d'une action de même préfixe de titre, puis
/// participant unique restant ».
///
/// Trois règles ordonnées : chacune a son test, et l'ordre entre elles aussi —
/// c'est l'ordre qui fait la qualité de la suggestion, et un service qui
/// renverrait le bon nom par la mauvaise règle finirait par se tromper sur une
/// autre réunion.
@Suite("Suggestion de responsable")
@MainActor
struct OwnerSuggestionTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Le préfixe garde trois mots normalisés")
    func prefixe() {
        #expect(OwnerSuggestion.prefixe("Vérifier l'état des comptes GitLab") == "verifier l etat")
        // Même préfixe malgré la ponctuation, la casse et les accents.
        #expect(OwnerSuggestion.prefixe("VÉRIFIER L'ÉTAT, des droits")
                == OwnerSuggestion.prefixe("vérifier l'état des comptes"))
        #expect(OwnerSuggestion.prefixe("Chiffrer") == "chiffrer")
        #expect(OwnerSuggestion.prefixe("   ") == "")
    }

    @Test("Règle 1 : le locuteur de la phrase source")
    func speakerOfSourcePhrase() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let yann = Collaborator(name: "Yann Ferré", role: "")
        let autre = Collaborator(name: "Nathalie Lefèvre", role: "")
        context.insert(yann); context.insert(autre)
        reunion.participants = [yann, autre]

        let segment = TranscriptSegment(orderIndex: 0, startSeconds: 231, endSeconds: 252,
                                        text: "Il faut vérifier l'état des comptes GitLab.",
                                        speakerID: 1)
        segment.speaker = yann
        context.insert(segment)
        segment.meeting = reunion

        let action = ActionTask(title: "Vérifier l'état des comptes GitLab")
        context.insert(action)
        action.meeting = reunion
        action.sourceRef = SourceRef(kind: .transcript,
                                     stableID: segment.stableID ?? UUID(),
                                     t: 231)

        #expect(OwnerSuggestion.suggestion(for: action, in: reunion, projectTasks: []) === yann)
    }

    @Test("Règle 1 : un segment sans locuteur résolu ne suggère rien par lui-même")
    func unresolvedSpeakerFallsThrough() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        // Trois participants : la règle 3 ne peut pas conclure non plus.
        for nom in ["Yann Ferré", "Nathalie Lefèvre", "Cédric Payet"] {
            let c = Collaborator(name: nom, role: "")
            context.insert(c)
            reunion.participants.append(c)
        }
        let segment = TranscriptSegment(orderIndex: 0, startSeconds: 10, endSeconds: 20,
                                        text: "Phrase sans locuteur nommé.", speakerID: 2)
        context.insert(segment)
        segment.meeting = reunion

        let action = ActionTask(title: "Action née d'un cluster anonyme")
        context.insert(action)
        action.meeting = reunion
        action.sourceRef = SourceRef(kind: .transcript, stableID: segment.stableID ?? UUID(), t: 10)

        #expect(OwnerSuggestion.suggestion(for: action, in: reunion, projectTasks: []) == nil)
    }

    @Test("Règle 2 : le dernier porteur d'une action de même préfixe")
    func lastCarrierOfSamePrefix() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        // Trois participants pour que la règle 3 ne puisse pas conclure.
        for nom in ["Alice Berger", "Bruno Colin", "Chloé Dumas"] {
            let c = Collaborator(name: nom, role: "")
            context.insert(c)
            reunion.participants.append(c)
        }
        let ancien = Collaborator(name: "Ancien porteur", role: "")
        let recent = Collaborator(name: "Porteur récent", role: "")
        context.insert(ancien); context.insert(recent)

        let vieille = ActionTask(title: "Vérifier l'état des flux")
        vieille.collaborator = ancien
        vieille.createdAt = Date(timeIntervalSince1970: 1_000)
        let recente = ActionTask(title: "Vérifier l'état des droits GitLab")
        recente.collaborator = recent
        recente.createdAt = Date(timeIntervalSince1970: 2_000)
        // Un préfixe différent ne doit pas peser.
        let ailleurs = ActionTask(title: "Chiffrer la fin de migration")
        ailleurs.collaborator = ancien
        ailleurs.createdAt = Date(timeIntervalSince1970: 3_000)
        for t in [vieille, recente, ailleurs] { context.insert(t) }

        let action = ActionTask(title: "Vérifier l'état des comptes GitLab")
        context.insert(action)
        action.meeting = reunion

        let suggestion = OwnerSuggestion.suggestion(for: action, in: reunion,
                                                    projectTasks: [vieille, recente, ailleurs])
        #expect(suggestion === recent)
    }

    @Test("La règle 1 l'emporte sur la règle 2")
    func speakerBeatsPrefix() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let locuteur = Collaborator(name: "Locuteur", role: "")
        let porteurHistorique = Collaborator(name: "Porteur historique", role: "")
        context.insert(locuteur); context.insert(porteurHistorique)
        reunion.participants = [locuteur, porteurHistorique]

        let segment = TranscriptSegment(orderIndex: 0, startSeconds: 5, endSeconds: 9,
                                        text: "Vérifier l'état des comptes.", speakerID: 1)
        segment.speaker = locuteur
        context.insert(segment)
        segment.meeting = reunion

        let ancienne = ActionTask(title: "Vérifier l'état des droits")
        ancienne.collaborator = porteurHistorique
        ancienne.createdAt = Date(timeIntervalSince1970: 9_000)
        context.insert(ancienne)

        let action = ActionTask(title: "Vérifier l'état des comptes GitLab")
        context.insert(action)
        action.meeting = reunion
        action.sourceRef = SourceRef(kind: .transcript, stableID: segment.stableID ?? UUID(), t: 5)

        #expect(OwnerSuggestion.suggestion(for: action, in: reunion,
                                           projectTasks: [ancienne]) === locuteur)
    }

    @Test("Règle 3 : le participant unique qui ne porte encore rien")
    func singleRemainingParticipant() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let occupe = Collaborator(name: "Déjà chargé", role: "")
        let libre = Collaborator(name: "Encore libre", role: "")
        context.insert(occupe); context.insert(libre)
        reunion.participants = [occupe, libre]

        let deja = ActionTask(title: "Action déjà portée")
        deja.collaborator = occupe
        context.insert(deja)
        deja.meeting = reunion

        let action = ActionTask(title: "Action neuve sans source")
        context.insert(action)
        action.meeting = reunion

        #expect(OwnerSuggestion.suggestion(for: action, in: reunion, projectTasks: []) === libre)
    }

    @Test("Deux participants libres : aucune suggestion, deviner serait pire que rien")
    func twoFreeParticipantsSuggestNothing() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        for nom in ["Alice Berger", "Bruno Colin"] {
            let c = Collaborator(name: nom, role: "")
            context.insert(c)
            reunion.participants.append(c)
        }
        let action = ActionTask(title: "Action neuve")
        context.insert(action)
        action.meeting = reunion

        #expect(OwnerSuggestion.suggestion(for: action, in: reunion, projectTasks: []) == nil)
    }

    @Test("Aucun candidat : nil, jamais un porteur arbitraire")
    func noCandidate() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion sans participant", date: .now)
        context.insert(reunion)
        let action = ActionTask(title: "Action orpheline")
        context.insert(action)
        action.meeting = reunion
        #expect(OwnerSuggestion.suggestion(for: action, in: reunion, projectTasks: []) == nil)
    }
}
