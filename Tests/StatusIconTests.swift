import Testing
import SwiftUI
@testable import OneToOne

/// La pastille de statut, migrée sur les jetons et sortie de
/// `ProjectListView.swift` (décision **D16**).
///
/// Ce qui se teste d'une pastille, c'est sa **table** : quel statut persisté
/// donne quelle teinte, et ce que devient une valeur que le portfolio externe
/// écrirait sans qu'on l'ait prévue. La taille, elle, est un paramètre par
/// défaut — et c'est ce défaut que la capture `1a-portfolio.png` fixe à 9 px.
@Suite("Pastille de statut — D16")
struct StatusIconTests {

    @Test("La table du handoff : Green ok · Yellow warn · Red report · Unknown neutre")
    func table() {
        #expect(StatusIcon.teinte("Green") == One2OneToken.ok)
        #expect(StatusIcon.teinte("Yellow") == One2OneToken.warn)
        #expect(StatusIcon.teinte("Red") == One2OneToken.report)
        #expect(StatusIcon.teinte("Unknown") == One2OneToken.inkMuted)
    }

    @Test("La lecture du statut ignore la casse et les espaces de bord")
    func casseEtEspaces() {
        #expect(StatusIcon.teinte("green") == One2OneToken.ok)
        #expect(StatusIcon.teinte("  RED  ") == One2OneToken.report)
        #expect(StatusIcon.teinte("YeLLoW") == One2OneToken.warn)
    }

    @Test("Une valeur hors table s'affiche en neutre, jamais en couleur d'alerte")
    func horsTable() {
        // « Réalisation » est la valeur que le semis historique écrit dans
        // `phase` ; rien n'empêche un import d'en écrire l'équivalent dans
        // `status` (constat §2.7 de la spec).
        #expect(StatusIcon.teinte("Réalisation") == One2OneToken.inkMuted)
        #expect(StatusIcon.teinte("") == One2OneToken.inkMuted)
        #expect(StatusIcon.teinte("—") == One2OneToken.inkMuted)
    }

    @Test("La taille par défaut est celle de la colonne du Portfolio")
    func tailleParDefaut() {
        // 9 px : la mesure de la grille de la capture 1a. La section « Projets »
        // de la barre latérale demande 10, les appels historiques 12 — tous
        // passent donc le paramètre.
        #expect(StatusIcon(status: "Green").size == 9)
        #expect(StatusIcon(status: "Green", size: 10).size == 10)
    }
}
