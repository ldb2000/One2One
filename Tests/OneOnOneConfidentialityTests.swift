import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les défauts par rôle (spec §6.1 : « visibilité par défaut des notes —
/// manager `shared`, collaborateur `private`, le partage est un geste explicite
/// par ligne ») et le compte des lignes exclues, qui doit s'afficher
/// « systématiquement » sur le bouton de clôture (spec §3.2).
@Suite("Confidentialité 1:1 — défaut par rôle et compte des exclusions (spec §3.2, §6.1)")
@MainActor
struct OneOnOneConfidentialityTests {

    private struct Ligne: Confidential {
        let visibility: Visibility
    }

    private func makeFil(role: OneOnOneSide) throws -> (OneOnOneThread, ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let personne = Collaborator(name: "Laurent NOMINÉ")
        context.insert(personne)
        let kind = OneOnOneThreadStore.meetingKind(for: role)
        let fil = try #require(OneOnOneThreadStore.thread(for: personne, kind: kind, in: context))
        return (fil, context)
    }

    // MARK: - Défaut par rôle

    @Test("Le manager partage par défaut, le collaborateur garde pour lui")
    func defautParRole() {
        #expect(OneOnOneConfidentiality.defaultVisibility(for: .manager) == .shared)
        #expect(OneOnOneConfidentiality.defaultVisibility(for: .collaborator) == .private)
    }

    @Test("Sans fil, le défaut reste celui d'une réunion ordinaire")
    func defautSansFil() {
        #expect(OneOnOneConfidentiality.defaultVisibility(for: nil as OneOnOneThread?) == .shared)
    }

    @Test("Le défaut du fil suit son rôle")
    func defautDuFil() throws {
        let (menee, _) = try makeFil(role: .manager)
        let (subie, _) = try makeFil(role: .collaborator)
        #expect(OneOnOneConfidentiality.defaultVisibility(for: menee) == .shared)
        #expect(OneOnOneConfidentiality.defaultVisibility(for: subie) == .private)
    }

    @Test("Le défaut par rôle et le défaut par type de réunion disent la même chose")
    func coherenceAvecLeStore() {
        // `MeetingNoteStore.defaultVisibility(for kind:)` est ce que le
        // composeur appelle quand il n'a pas de fil sous la main. Les deux
        // chemins ne doivent pas diverger.
        #expect(MeetingNoteStore.defaultVisibility(for: .oneToOne)
                == OneOnOneConfidentiality.defaultVisibility(for: .manager))
        #expect(MeetingNoteStore.defaultVisibility(for: .manager)
                == OneOnOneConfidentiality.defaultVisibility(for: .collaborator))
    }

    // MARK: - Bascule /privé

    @Test("La bascule /privé va et revient au défaut du rôle")
    func basculePrive() {
        #expect(OneOnOneConfidentiality.toggledPrivacy(.shared, role: .manager) == .private)
        #expect(OneOnOneConfidentiality.toggledPrivacy(.private, role: .manager) == .shared)

        #expect(OneOnOneConfidentiality.toggledPrivacy(.private, role: .collaborator) == .shared)
        #expect(OneOnOneConfidentiality.toggledPrivacy(.shared, role: .collaborator) == .private)
    }

    @Test("Depuis escaladé, la bascule ramène au privé")
    func basculeDepuisEscalade() {
        // Ne jamais retomber sur `shared` depuis `escalated` : ce serait
        // rendre visible au collaborateur une ligne montée à la hiérarchie.
        #expect(OneOnOneConfidentiality.toggledPrivacy(.escalated, role: .manager) == .private)
        #expect(OneOnOneConfidentiality.toggledPrivacy(.escalated, role: .collaborator) == .private)
    }

    // MARK: - Lignes exclues

    @Test("Le compte des lignes exclues suit l'audience")
    func lignesExclues() {
        let lignes: [any Confidential] = [
            Ligne(visibility: .private),
            Ligne(visibility: .private),
            Ligne(visibility: .private),
            Ligne(visibility: .shared),
            Ligne(visibility: .escalated)
        ]

        // Capture 5a : « 3 lignes privées seront exclues. »
        #expect(OneOnOneConfidentiality.excludedLinesCount(lignes, for: .collaborator) == 4)
        #expect(OneOnOneConfidentiality.privateLinesCount(lignes) == 3)
        #expect(OneOnOneConfidentiality.excludedLinesCount(lignes, for: .me) == 0)
        #expect(OneOnOneConfidentiality.excludedLinesCount(lignes, for: .hr) == 4)
    }

    @Test("Le libellé des lignes exclues s'accorde en nombre")
    func libelleDesExclusions() {
        #expect(OneOnOneConfidentiality.excludedLinesLabel(0) == nil)
        #expect(OneOnOneConfidentiality.excludedLinesLabel(1) == "1 ligne privée sera exclue.")
        #expect(OneOnOneConfidentiality.excludedLinesLabel(3) == "3 lignes privées seront exclues.")
    }

    // MARK: - Audience de sortie (D9)

    @Test("Le récap va au collaborateur côté manager, au manager côté collaborateur")
    func audienceDuRecap() {
        #expect(OneOnOneConfidentiality.recapAudience(for: .manager) == .collaborator)
        #expect(OneOnOneConfidentiality.recapAudience(for: .collaborator) == .manager)
        #expect(OneOnOneConfidentiality.escalationAudience == .hr)
    }

    // MARK: - Confirmation d'escalade (D9)

    @Test("La confirmation d'escalade est demandée une fois par réunion")
    func confirmationParReunion() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let premiere = Meeting(title: "1:1 A", date: Date(), notes: "")
        let seconde = Meeting(title: "1:1 B", date: Date(), notes: "")
        context.insert(premiere)
        context.insert(seconde)

        let etat = OneOnOneScreenState(persistsAcrossLaunches: false)
        #expect(etat.needsEscalationConfirmation(for: premiere))
        etat.confirmEscalation(for: premiere)
        #expect(!etat.needsEscalationConfirmation(for: premiere))
        #expect(etat.isEscalationConfirmed(for: premiere))
        // Une autre réunion redemande : la confirmation est par séance.
        #expect(etat.needsEscalationConfirmation(for: seconde))
    }

    @Test("Le filtre d'engagements démarre sur « Les deux »")
    func filtreParDefaut() {
        let etat = OneOnOneScreenState(persistsAcrossLaunches: false)
        #expect(etat.commitmentSideFilter == nil)
    }
}
