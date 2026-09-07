import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// L'enveloppe de taille de la fenêtre `1to1-meeting`.
///
/// Ces tests gardent un **crash**, pas une préférence esthétique : sans
/// enveloppe déclarée, le `NSHostingView` racine de la fenêtre déduit
/// `contentMinSize`/`contentMaxSize` en mesurant tout l'écran de réunion
/// pendant la passe Auto Layout de la fenêtre, la passe se relance sans fin et
/// AppKit lève `NSGenericException` (« more Update Constraints in Window passes
/// than there are views in the window »). Reproduit en bundle release à chaque
/// ouverture de la fenêtre dédiée depuis le commit 6cc892b (barre du haut sur
/// une ligne), corrigé en déclarant l'enveloppe.
///
/// Ce que `swift test` peut vérifier : que les constantes tiennent le contrat
/// de mise en page, et que la fenêtre les applique toujours. Ce qu'il ne peut
/// pas : la passe Auto Layout elle-même, qui exige un bundle `.app` — d'où le
/// test de fumée consigné dans `STATUS.md`.
@Suite("Enveloppe de la fenêtre de réunion")
struct MeetingWindowSizingTests {

    @Test("Le plancher de largeur garde le rail d'actions affiché")
    func minWidthKeepsRail() {
        // Sous `fluidMinimum + actionsRailWidth`, `MeetingSpaceLayout` sacrifie
        // le rail — que la spec §1.1 veut permanent. Le plancher de la fenêtre
        // doit donc rester au-dessus.
        #expect(MeetingWindowSizing.minWidth
                >= MeetingSpaceLayout.fluidMinimum + One2OneToken.actionsRailWidth)
        #expect(MeetingSpaceLayout.showsRail(totalWidth: MeetingWindowSizing.minWidth))

        let colonnes = MeetingSpaceLayout.columns(
            totalWidth: MeetingWindowSizing.minWidth,
            rail: One2OneToken.actionsRailWidth,
            sideNav: nil
        )
        #expect(colonnes.rail == One2OneToken.actionsRailWidth)
        #expect(colonnes.fluid >= MeetingSpaceLayout.fluidMinimum)
    }

    @Test("Le plancher de hauteur laisse la place aux deux barres et aux colonnes")
    func minHeightLeavesRoom() {
        let barres = MeetingTopChromeBar.height + MeetingSpacesBar.height
        #expect(MeetingWindowSizing.minHeight > barres)
        // Ce qui reste doit rester utilisable : au moins l'en-tête de la carte
        // « Notes & transcription » et une hauteur de lecture réelle.
        #expect(MeetingWindowSizing.minHeight - barres >= 400)
    }

    @Test("La taille d'ouverture ne descend pas sous le plancher")
    func idealAboveMinimum() {
        #expect(MeetingWindowSizing.idealWidth >= MeetingWindowSizing.minWidth)
        #expect(MeetingWindowSizing.idealHeight >= MeetingWindowSizing.minHeight)
    }

    /// Garde de non-régression du correctif lui-même : la fenêtre doit
    /// **appliquer** l'enveloppe. Une enveloppe déclarée mais non branchée
    /// laisserait le crash revenir sans qu'aucun autre test ne bronche, et la
    /// passe Auto Layout n'est pas observable depuis `swift test`.
    @Test("La fenêtre 1to1-meeting applique l'enveloppe à son contenu racine")
    func windowContentAppliesEnvelope() throws {
        let racine = URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // racine du paquet
        let source = try String(contentsOf: racine.appending(path: "OneToOne/OneToOneApp.swift"),
                                encoding: .utf8)

        let debut = try #require(source.range(of: "struct OneToOneMeetingWindowContent"))
        let corps = source[debut.lowerBound...]
        let fin = corps.range(of: "\n}\n") ?? corps.range(of: "\n}")
        let contenu = fin.map { String(corps[..<$0.lowerBound]) } ?? String(corps)

        #expect(contenu.contains("MeetingWindowSizing.minWidth"))
        #expect(contenu.contains("MeetingWindowSizing.minHeight"))
    }
}
