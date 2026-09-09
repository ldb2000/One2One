import Testing
import CoreGraphics
@testable import OneToOne

/// Où poser la fenêtre principale quand le cadre enregistré ne correspond plus
/// aux écrans branchés.
///
/// **Le test qui manquait.** Le 2026-09-09, une recette a perdu trois heures
/// parce que la fenêtre principale était restaurée à `x = 2048`, sur un second
/// écran 1920 × 1050 débranché depuis : entièrement hors de tout écran, donc
/// sans surface, jamais rendue, `onAppear` jamais parti, aucun semis. La règle
/// « intersecte un écran visible » existait bien dans le code, mais enfouie
/// dans une `NSView` privée et appliquée à **une seule** des deux clés de cadre
/// — la nôtre, pas celle que SwiftUI restaure de son côté. Une règle enfouie
/// n'est pas testable ; sortie en fonction pure, elle l'est, et elle s'applique
/// aux deux sources.
@Suite("Placement de la fenêtre principale")
struct MainWindowPlacementTests {

    /// L'écran interne du poste, tel que la recette l'a relevé.
    private let ecranInterne = CGRect(x: 0, y: 0, width: 1_728, height: 1_084)
    private let tailleParDefaut = CGSize(width: MainWindowSizing.defaultWidth,
                                         height: MainWindowSizing.defaultHeight)

    @Test("Un cadre visible n'est pas touché")
    func cadreVisible() {
        let cadre = CGRect(x: 224, y: 142, width: 1_280, height: 800)
        #expect(MainWindowPlacement.corrige(cadre: cadre,
                                            ecrans: [ecranInterne],
                                            tailleParDefaut: tailleParDefaut) == cadre)
    }

    @Test("Un cadre entièrement hors écran à droite est recentré à la taille par défaut")
    func cadreHorsEcran() {
        // Le cadre exact du domaine de préférences du 2026-09-09.
        let cadre = CGRect(x: 2_048, y: 162, width: 1_280, height: 800)
        let corrige = MainWindowPlacement.corrige(cadre: cadre,
                                                   ecrans: [ecranInterne],
                                                   tailleParDefaut: tailleParDefaut)
        #expect(corrige != cadre)
        #expect(corrige.size == tailleParDefaut)
        #expect(ecranInterne.intersects(corrige))
        // Centré sur l'écran.
        #expect(corrige.midX == ecranInterne.midX)
        #expect(corrige.midY == ecranInterne.midY)
    }

    @Test("Un cadre sur un écran secondaire encore branché n'est pas touché")
    func ecranSecondairePresent() {
        let secondaire = CGRect(x: 1_728, y: 37, width: 1_920, height: 1_050)
        let cadre = CGRect(x: 2_048, y: 162, width: 1_280, height: 800)
        #expect(MainWindowPlacement.corrige(cadre: cadre,
                                            ecrans: [ecranInterne, secondaire],
                                            tailleParDefaut: tailleParDefaut) == cadre)
    }

    @Test("Sans écran connu, ne rien décider")
    func aucunEcran() {
        // Pendant la veille, `NSScreen.screens` peut être vide : recentrer sur
        // un écran qu'on ne connaît pas serait pire que de ne rien faire.
        let cadre = CGRect(x: 2_048, y: 162, width: 1_280, height: 800)
        #expect(MainWindowPlacement.corrige(cadre: cadre,
                                            ecrans: [],
                                            tailleParDefaut: tailleParDefaut) == cadre)
    }

    @Test("Un cadre nul est recentré, pas laissé à zéro")
    func cadreNul() {
        let corrige = MainWindowPlacement.corrige(cadre: .zero,
                                                   ecrans: [ecranInterne],
                                                   tailleParDefaut: tailleParDefaut)
        #expect(corrige.size == tailleParDefaut)
        #expect(ecranInterne.intersects(corrige))
    }

    @Test("Un cadre qui ne chevauche l'écran que d'un coin est laissé tel quel")
    func chevauchementPartiel() {
        // La valeur courante du poste, `{{60, -46}, {1242, 1130}}`, est plus
        // haute que l'écran et commence sous son bord : gênante, mais visible.
        // On corrige l'invisible, pas le gênant.
        let cadre = CGRect(x: 60, y: -46, width: 1_242, height: 1_130)
        #expect(MainWindowPlacement.corrige(cadre: cadre,
                                            ecrans: [ecranInterne],
                                            tailleParDefaut: tailleParDefaut) == cadre)
    }
}
