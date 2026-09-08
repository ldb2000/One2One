import Testing
@testable import OneToOne

/// Ce que la navigation de l'écran de réunion propose selon le type.
///
/// Adaptée au lot 1 : les sept onglets de `MeetingView.MeetingSection` cèdent la
/// place aux trois espaces de la spec §1.1 (`Réunion` · `Rapport` · `Ressources`)
/// et au sous-mode temporel (`Préparer` / `En séance` / `Relire`). La règle de
/// fond, elle, ne change pas : **une note n'a ni rapport, ni séance** — elle n'a
/// que son corps et ses pièces jointes.
@Suite("Espaces visibles selon le type de réunion")
struct MeetingVisibleSectionsTests {

    @Test("Une note n'a que son corps et ses ressources — ni rapport, ni modes")
    func noteHasTwoSpaces() {
        #expect(MeetingSpaceRouting.spaces(for: .note) == [.meeting, .resources])
        // Pas de sélecteur de mode : une note ne se prépare pas et ne se
        // relit pas, elle s'écrit. C'est l'équivalent, côté espaces, des cinq
        // onglets que `visibleSections(for: .note)` retirait.
        #expect(MeetingSpaceRouting.modes(for: .note).isEmpty)
    }

    @Test("Tous les autres types ont les trois espaces et les trois modes")
    func othersHaveEverything() {
        for kind in MeetingKind.allCases where kind != .note {
            #expect(MeetingSpaceRouting.spaces(for: kind) == [.meeting, .report, .resources],
                    "espaces inattendus pour \(kind.label)")
            #expect(MeetingSpaceRouting.modes(for: kind) == [.prepare, .live, .review],
                    "modes inattendus pour \(kind.label)")
        }
    }

    @Test("Un espace mémorisé devenu invisible retombe sur Réunion, en séance")
    func fallbackWhenKindChanges() {
        // Le cas réel : une réunion Projet dont on change le type en Note
        // alors que l'espace Rapport était affiché. L'ancien code faisait la
        // même chose sur `activeSection` dans deux `onChange`.
        let repli = MeetingSpaceRouting.fallback(space: .report, mode: .review, for: .note)
        #expect(repli.space == .meeting)
        #expect(repli.mode == .live)
    }

    @Test("Un espace encore visible n'est pas déplacé")
    func fallbackKeepsValidChoice() {
        let garde = MeetingSpaceRouting.fallback(space: .report, mode: .review, for: .project)
        #expect(garde.space == .report)
        #expect(garde.mode == .review)
    }

    @Test("Les espaces et les modes portent les libellés de la capture 1a")
    func labelsMatchTheCapture() {
        #expect(MeetingScreenModel.Space.meeting.label == "Réunion")
        #expect(MeetingScreenModel.Space.report.label == "Rapport")
        #expect(MeetingScreenModel.Space.resources.label == "Ressources")
        #expect(MeetingScreenModel.Mode.prepare.label == "Préparer")
        #expect(MeetingScreenModel.Mode.live.label == "En séance")
        #expect(MeetingScreenModel.Mode.review.label == "Relire")
    }

    @Test("Le libellé du corps d'une note reste « Note »")
    func noteBodyLabel() {
        // L'ancienne suite vérifiait `MeetingSection.liveNotes.label(for:)` :
        // même exigence, portée par l'espace Réunion.
        #expect(MeetingSpaceRouting.meetingSpaceLabel(for: .note) == "Note")
        #expect(MeetingSpaceRouting.meetingSpaceLabel(for: .oneToOne) == "Réunion")
    }
}
