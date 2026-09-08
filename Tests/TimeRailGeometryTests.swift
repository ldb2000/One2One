import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// La colonne temps du mode séance plein écran (spec §2.6, capture
/// `1b-mode-seance.png`).
///
/// Tout est borné : une séance qui vient de démarrer a une durée nulle, et
/// c'est le cas **courant** de cet écran. Un `Canvas` à qui l'on passe un `NaN`
/// ne dessine rien sans rien signaler — d'où ces tests plutôt qu'un coup d'œil.
@Suite("Géométrie de la colonne temps")
struct TimeRailGeometryTests {

    // MARK: - Axe

    @Test("La position à mi-course tombe au milieu de l'axe")
    func midpoint() {
        #expect(TimeRailGeometry.y(t: 300, duration: 600, length: 400) == 200)
        #expect(TimeRailGeometry.elapsedLength(t: 300, duration: 600, length: 400) == 200)
    }

    @Test("Une durée nulle ne divise rien par zéro")
    func zeroDuration() {
        #expect(TimeRailGeometry.y(t: 42, duration: 0, length: 400) == 0)
        #expect(TimeRailGeometry.y(t: 42, duration: -1, length: 400) == 0)
        #expect(TimeRailGeometry.elapsedLength(t: 42, duration: 0, length: 400) == 0)
        #expect(TimeRailGeometry.t(y: 100, duration: 0, length: 400) == 0)
    }

    @Test("Une position hors de la durée reste sur l'axe")
    func clamped() {
        #expect(TimeRailGeometry.y(t: 1_000, duration: 600, length: 400) == 400)
        #expect(TimeRailGeometry.y(t: -10, duration: 600, length: 400) == 0)
        #expect(TimeRailGeometry.y(t: .nan, duration: 600, length: 400) == 0)
    }

    @Test("Le clic sur l'axe rend l'instant correspondant, borné")
    func inverse() {
        #expect(TimeRailGeometry.t(y: 200, duration: 600, length: 400) == 300)
        #expect(TimeRailGeometry.t(y: -5, duration: 600, length: 400) == 0)
        #expect(TimeRailGeometry.t(y: 900, duration: 600, length: 400) == 600)
    }

    @Test("Aller-retour position → instant → position")
    func roundTrip() {
        let y = TimeRailGeometry.y(t: 1_122, duration: 1_404, length: 620)
        let t = TimeRailGeometry.t(y: y, duration: 1_404, length: 620)
        #expect(abs(t - 1_122) < 0.001)
    }

    // MARK: - Formes

    @Test("Une décision est un carré, tout le reste un rond")
    func shapes() {
        #expect(TimeRailGeometry.shape(for: .decision) == .square)
        #expect(TimeRailGeometry.shape(for: .note) == .dot)
        #expect(TimeRailGeometry.shape(for: .risk) == .dot)
        #expect(TimeRailGeometry.shape(for: .capture) == .dot)
        #expect(TimeRailGeometry.shape(for: .board) == .dot)
    }

    @Test("Le carré de la décision porte le rayon de 3 px de la spec")
    func decisionRadius() {
        #expect(TimeRailGeometry.decisionCornerRadius == 3)
        #expect(TimeRailGeometry.axisWidth == 3)
        #expect(TimeRailGeometry.size(of: .square) == TimeRailGeometry.decisionSide)
        #expect(TimeRailGeometry.size(of: .dot) == TimeRailGeometry.noteDiameter)
    }

    @Test("Le libellé mono est à 30 px du rail, dans une colonne de 78")
    func labelPosition() {
        #expect(TimeRailGeometry.labelInset == 30)
        #expect(TimeRailGeometry.columnWidth == 78)
        #expect(TimeRailGeometry.labelX == TimeRailGeometry.axisCenterX - 30)
        // Le libellé passe derrière l'axe : sur la capture on lit `04:1`.
        #expect(TimeRailGeometry.labelX + TimecodeLabel.width > TimeRailGeometry.axisCenterX)
    }

    // MARK: - Libellés

    private func marker(_ t: Double, _ kind: MeetingPlayhead.Marker.Kind) -> MeetingPlayhead.Marker {
        MeetingPlayhead.Marker(t: t, kind: kind)
    }

    @Test("Les cinq libellés de la capture, dans l'ordre du haut vers le bas")
    func capturedLabels() {
        // 04:12 · 07:48 · 11:03 · 15:20 (repères) puis 18:42 (position),
        // sur les 23:24 de la réunion de démonstration.
        let reperes = [marker(252, .note), marker(468, .note),
                       marker(663, .decision), marker(920, .note)]
        let libelles = TimeRailGeometry.labels(markers: reperes,
                                               position: 1_122,
                                               duration: 1_404,
                                               length: 620)
        #expect(libelles.map(\.text) == ["04:12", "07:48", "11:03", "15:20", "18:42"])
        #expect(libelles.map(\.isPosition) == [false, false, false, false, true])
        #expect(libelles.map(\.y).sorted() == libelles.map(\.y))
    }

    @Test("Les repères désordonnés sont remis dans l'ordre du temps")
    func unsortedMarkers() {
        let libelles = TimeRailGeometry.labels(markers: [marker(920, .note), marker(252, .note)],
                                               position: nil,
                                               duration: 1_404,
                                               length: 620)
        #expect(libelles.map(\.text) == ["04:12", "15:20"])
    }

    @Test("Deux repères trop proches ne rendent qu'un libellé")
    func collidingMarkers() {
        // Deux secondes d'écart sur un axe de 620 px pour 1 404 s : moins d'un
        // point. Deux libellés superposés seraient illisibles.
        let libelles = TimeRailGeometry.labels(markers: [marker(600, .note), marker(602, .note)],
                                               position: nil,
                                               duration: 1_404,
                                               length: 620)
        #expect(libelles.count == 1)
        #expect(libelles.first?.text == "10:00")
    }

    @Test("La position évince le repère qu'elle recouvre")
    func positionWins() {
        let libelles = TimeRailGeometry.labels(markers: [marker(600, .note)],
                                               position: 601,
                                               duration: 1_404,
                                               length: 620)
        #expect(libelles.count == 1)
        #expect(libelles.first?.isPosition == true)
        #expect(libelles.first?.text == "10:01")
    }

    @Test("Sans position, aucun libellé n'est marqué comme tel")
    func noPosition() {
        let libelles = TimeRailGeometry.labels(markers: [marker(252, .note)],
                                               position: nil,
                                               duration: 1_404,
                                               length: 620)
        #expect(libelles.count == 1)
        #expect(libelles.allSatisfy { !$0.isPosition })
    }

    @Test("Aucun libellé sans repère ni position")
    func empty() {
        #expect(TimeRailGeometry.labels(markers: [], position: nil,
                                        duration: 1_404, length: 620).isEmpty)
    }
}
