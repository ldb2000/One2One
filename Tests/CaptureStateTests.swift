import Testing
import CoreGraphics
import Foundation
@testable import OneToOne

/// L'état d'écran de la capture et ses décisions pures (spec §5.1, §5.2,
/// critère d'acceptation n° 1 du chantier 4).
@Suite("CaptureState")
@MainActor
struct CaptureStateTests {

    private func option(_ source: CaptureSource,
                        active: Bool = true,
                        windowID: CGWindowID = 1) -> CaptureSourceOption {
        CaptureSourceOption(source: source,
                            badge: "TEAMS",
                            title: "Microsoft Teams",
                            subtitle: active ? "Réunion · partage de Sylvain en cours" : "Aucune réunion active",
                            windowID: windowID,
                            isActive: active)
    }

    // MARK: - Critère n° 1 : tout se lit sans ouvrir de menu

    @Test("la pilule dit l'état, la source et le compteur sans ouvrir de menu")
    func pillSaysEverything() {
        let armee = CaptureState.pill(sessionOpen: true,
                                      sourceLost: false,
                                      source: .teams,
                                      count: 3,
                                      automatic: true)
        #expect(armee == .armed(source: .teams, count: 3, automatic: true))
        #expect(armee.label == "Capture · Teams 3")
        #expect(armee.count == 3)
    }

    @Test("sans session, la pilule est un bouton neutre `Capture`")
    func pillIdle() {
        let etat = CaptureState.pill(sessionOpen: false,
                                     sourceLost: false,
                                     source: .teams,
                                     count: 7,
                                     automatic: true)
        #expect(etat == .idle)
        #expect(etat.label == "Capture")
    }

    @Test("source perdue : la pilule le dit et conserve le compteur")
    func pillLost() {
        let etat = CaptureState.pill(sessionOpen: true,
                                     sourceLost: true,
                                     source: .teams,
                                     count: 2,
                                     automatic: true)
        #expect(etat == .lost(count: 2))
        #expect(etat.label == "Source perdue")
        // Les captures déjà prises ne disparaissent pas avec la source.
        #expect(etat.count == 2)
    }

    @Test("la pilule distingue la capture armée automatiquement de celle qui attend un geste")
    func pillReportsAutomatic() {
        let manuelle = CaptureState.pill(sessionOpen: true,
                                         sourceLost: false,
                                         source: .zoom,
                                         count: 0,
                                         automatic: false)
        #expect(manuelle == .armed(source: .zoom, count: 0, automatic: false))
        #expect(manuelle.label == "Capture · Zoom 0")
    }

    // MARK: - ⌘⇧S

    @Test("⌘⇧S ouvre le sélecteur à la première utilisation")
    func shortcutOpensSelectorFirst() {
        #expect(CaptureState.shortcutOutcome(selected: nil, sourceLost: false) == .openSelector)
    }

    @Test("⌘⇧S capture directement ensuite, sur la dernière source valide")
    func shortcutCapturesAfterwards() {
        #expect(CaptureState.shortcutOutcome(selected: option(.teams), sourceLost: false) == .captureNow)
    }

    @Test("⌘⇧S rouvre le sélecteur si la source retenue n'est plus valide")
    func shortcutReopensOnInvalidSource() {
        #expect(CaptureState.shortcutOutcome(selected: option(.teams, active: false),
                                             sourceLost: false) == .openSelector)
        #expect(CaptureState.shortcutOutcome(selected: option(.teams),
                                             sourceLost: true) == .openSelector)
    }

    // MARK: - Bascules et défauts par type

    @Test("les défauts du type s'appliquent une seule fois")
    func kindDefaultsApplyOnce() {
        let etat = CaptureState()
        etat.applyDefaultsIfNeeded(for: .oneToOne)
        #expect(!etat.detectsAutomatically)

        // Un geste de l'utilisateur, puis un second passage (remontage de la
        // vue) : le geste survit.
        etat.setAutomaticDetection(true)
        etat.didApplyKindDefaults = false
        etat.applyDefaultsIfNeeded(for: .oneToOne)
        #expect(etat.detectsAutomatically)
    }

    @Test("le profil Atelier arme la capture périodique")
    func workshopDefaults() {
        let etat = CaptureState()
        etat.applyDefaultsIfNeeded(for: .workshop)
        #expect(etat.detectsAutomatically)
        #expect(etat.periodicCapture == CaptureState.periodicInterval)
    }

    @Test("un second appel ne rejoue pas les défauts")
    func defaultsAreAppliedOnlyOnce() {
        let etat = CaptureState()
        etat.applyDefaultsIfNeeded(for: .workshop)
        etat.periodicCapture = nil
        etat.applyDefaultsIfNeeded(for: .workshop)
        #expect(etat.periodicCapture == nil)
    }

    // MARK: - Catalogue

    @Test("le rafraîchissement du catalogue suit le nouvel identifiant de fenêtre")
    func refreshFollowsWindowID() {
        let etat = CaptureState()
        etat.selected = option(.teams, windowID: 1)
        etat.refresh(options: [option(.teams, windowID: 99)])
        // Teams relancé : l'identifiant a changé, la sélection le suit — sinon
        // la capture viserait une fenêtre qui n'existe plus.
        #expect(etat.selected?.windowID == 99)
    }

    @Test("une source disparue du catalogue reste sélectionnée, pour que la pilule puisse le dire")
    func refreshKeepsVanishedSelection() {
        let etat = CaptureState()
        etat.selected = option(.zoom, windowID: 5)
        etat.refresh(options: [option(.teams, windowID: 1)])
        #expect(etat.selected?.source == .zoom)
    }

    // MARK: - Libellés

    @Test("le sous-titre de la bande annonce le compteur et la source")
    func stripSubtitle() {
        #expect(CaptureState.stripSubtitle(count: 3, source: .teams) == "3 · source Teams")
        #expect(CaptureState.stripSubtitle(count: 0, source: nil) == "0 · aucune source")
    }

    @Test("la bascille de détection indisponible s'explique")
    func automaticUnavailableExplains() {
        #expect(CaptureState.automaticUnavailableReason(for: nil) != nil)
        let inactive = CaptureState.automaticUnavailableReason(for: option(.teams, active: false))
        #expect(inactive?.contains("Microsoft Teams") == true)
        // Une source active n'a rien à expliquer : la bascule est disponible.
        #expect(CaptureState.automaticUnavailableReason(for: option(.teams)) == nil)
    }
}
