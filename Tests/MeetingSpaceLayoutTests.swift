import Testing
import CoreGraphics
@testable import OneToOne

/// Critère d'acceptation n° 5 du chantier 1 (spec §2, « Critères d'acceptation ») :
/// « Sur une fenêtre de 1280 px, aucune colonne fixe ne se chevauche ; la colonne
/// fluide fait au moins 520 px. »
///
/// Le calcul est extrait de la vue pour être vérifiable sans session graphique :
/// une largeur négative ne se voit pas dans un test de rendu, elle se voit ici.
@Suite("Largeurs des colonnes de l'espace Réunion")
struct MeetingSpaceLayoutTests {

    @Test("À 1 280 px, la colonne fluide dépasse 520 px avec le rail de 330")
    func fluidAt1280() {
        let c = MeetingSpaceLayout.columns(totalWidth: 1280,
                                           rail: One2OneToken.actionsRailWidth,
                                           sideNav: nil)
        #expect(c.rail == One2OneToken.actionsRailWidth)
        #expect(c.sideNav == 0)
        #expect(c.fluid >= MeetingSpaceLayout.fluidMinimum)
        #expect(c.fluid + c.rail + c.sideNav <= 1280)
    }

    @Test("Le mode Relire ajoute la nav de 190 px sans descendre sous 520")
    func reviewAt1280() {
        let c = MeetingSpaceLayout.columns(totalWidth: 1280,
                                           rail: One2OneToken.actionsRailWidth,
                                           sideNav: One2OneToken.sideNavWidth)
        #expect(c.sideNav == One2OneToken.sideNavWidth)
        #expect(c.rail == One2OneToken.actionsRailWidth)
        #expect(c.fluid >= MeetingSpaceLayout.fluidMinimum)
        #expect(c.fluid + c.rail + c.sideNav <= 1280)
    }

    @Test("Sous le minimum, le rail est retiré plutôt que chevauché")
    func railDropsBelowMinimum() {
        #expect(MeetingSpaceLayout.showsRail(totalWidth: 1280))
        #expect(!MeetingSpaceLayout.showsRail(totalWidth: 820))
        let c = MeetingSpaceLayout.columns(totalWidth: 820,
                                           rail: One2OneToken.actionsRailWidth,
                                           sideNav: nil)
        #expect(c.rail == 0)
        #expect(c.fluid == 820)
    }

    @Test("La nav latérale part avant le rail : c'est le rail que la spec dit permanent")
    func sideNavGoesFirst() {
        // 520 + 330 + 190 = 1040 : à 1 000 px, une seule colonne fixe tient.
        let c = MeetingSpaceLayout.columns(totalWidth: 1000,
                                           rail: One2OneToken.actionsRailWidth,
                                           sideNav: One2OneToken.sideNavWidth)
        #expect(c.sideNav == 0)
        #expect(c.rail == One2OneToken.actionsRailWidth)
        #expect(c.fluid >= MeetingSpaceLayout.fluidMinimum)
    }

    @Test("À la largeur exacte de 1 040 px, les trois colonnes tiennent encore")
    func exactFit() {
        let total = MeetingSpaceLayout.fluidMinimum
            + One2OneToken.actionsRailWidth
            + One2OneToken.sideNavWidth
        let c = MeetingSpaceLayout.columns(totalWidth: total,
                                           rail: One2OneToken.actionsRailWidth,
                                           sideNav: One2OneToken.sideNavWidth)
        #expect(c.fluid == MeetingSpaceLayout.fluidMinimum)
        #expect(c.sideNav == One2OneToken.sideNavWidth)
    }

    @Test("Aucune largeur n'est négative, même sur une fenêtre absurde")
    func neverNegative() {
        for largeur in [CGFloat(0), 1, 200, 400] {
            let c = MeetingSpaceLayout.columns(totalWidth: largeur, rail: 330, sideNav: 190)
            #expect(c.fluid >= 0)
            #expect(c.rail >= 0)
            #expect(c.sideNav >= 0)
            #expect(c.fluid + c.rail + c.sideNav <= largeur)
        }
    }

    @Test("Les deux colonnes de la carte Notes ↔ transcription sont égales, filet compris")
    func notesAndTranscriptSplitEvenly() {
        let (gauche, droite) = MeetingSpaceLayout.evenSplit(width: 801)
        #expect(gauche == droite)
        #expect(gauche + droite + MeetingSpaceLayout.hairlineWidth == 801)
        // Une largeur trop petite ne rend pas de colonne négative.
        let minuscule = MeetingSpaceLayout.evenSplit(width: 0)
        #expect(minuscule.0 == 0 && minuscule.1 == 0)
    }
}
