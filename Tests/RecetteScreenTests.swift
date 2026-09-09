import Testing
import Foundation
@testable import OneToOne

/// La table des écrans qu'une recette visuelle sait ouvrir sans clic.
///
/// Elle n'était vérifiée par rien : c'est pourtant elle qui décide quelle
/// réunion s'ouvre et à quel mode, et la refonte de la gestion des projets
/// lui ajoute six codes **préfixés `p`** — parce que `1a`, `1c`, `2a` et `2b`
/// désignaient déjà quatre écrans de réunion (constat §2.4 de la spec,
/// décision **D6**).
///
/// Deux contraintes viennent du script, pas du code, et ne se voient donc pas
/// à la compilation : `Scripts/recette-run.sh` extrait la liste des codes avec
/// `sed -n 's/^ *case [a-zA-Z]* = "\([0-9a-z]*\)"/\1/p'`. Un code en
/// majuscules, un nom de cas avec un chiffre, ou une valeur brute implicite
/// disparaîtraient de la liste que le script accepte — silencieusement.
@Suite("Table des écrans de recette — D6")
struct RecetteScreenTests {

    @Test("Les codes d'écran sont uniques")
    func codesUniques() {
        let codes = RecetteScreen.allCases.map(\.rawValue)
        #expect(Set(codes).count == codes.count)
    }

    /// La regex du script : `[0-9a-z]*`. Une majuscule, un tiret ou un accent
    /// et le code n'est plus proposé par `--help` ni accepté par `--screen`.
    @Test("Chaque code d'écran ne s'écrit qu'en chiffres et minuscules")
    func codesEnMinuscules() {
        let permis = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyz")
        for ecran in RecetteScreen.allCases {
            #expect(!ecran.rawValue.isEmpty, "code vide")
            #expect(ecran.rawValue.unicodeScalars.allSatisfy(permis.contains),
                    "« \(ecran.rawValue) » sort de [0-9a-z]")
        }
    }

    /// Le `sed` du script ne reconnaît un cas que si son **nom** est purement
    /// alphabétique.
    @Test("Le nom de chaque cas est purement alphabétique")
    func nomsAlphabetiques() {
        let lettres = CharacterSet.letters
        for ecran in RecetteScreen.allCases {
            let nom = String(describing: ecran)
            #expect(nom.unicodeScalars.allSatisfy(lettres.contains),
                    "le cas « \(nom) » n'est pas lisible par le sed de recette-run.sh")
        }
    }

    @Test("Un code se lit depuis l'environnement, quelle que soit sa casse")
    func lectureDepuisEnvironnement() {
        #expect(RecetteScreen.from(environment: "p1a") == .portefeuille)
        #expect(RecetteScreen.from(environment: "P1A") == .portefeuille)
        #expect(RecetteScreen.from(environment: nil) == nil)
        #expect(RecetteScreen.from(environment: "") == nil)
        #expect(RecetteScreen.from(environment: "9z") == nil)
    }

    // MARK: - Les six écrans de la refonte des projets

    @Test("Les six écrans de la refonte des projets portent le préfixe « p »")
    func sixCodesPrefixes() {
        let attendus = ["p2b", "p1a", "p1c", "p1d", "p1f", "p2a"]
        let codes = RecetteScreen.allCases.map(\.rawValue)
        for code in attendus { #expect(codes.contains(code), "\(code) absent de la table") }
        // Et les quatre codes de réunion qu'ils auraient percutés sont intacts.
        for code in ["1a", "1c", "2a", "2b"] { #expect(codes.contains(code)) }
    }

    @Test("Les six écrans de la refonte des projets ouvrent la fenêtre principale")
    func sixCiblesFenetrePrincipale() throws {
        let routes: [(RecetteScreen, MainRoute)] = [
            (.sectionProjets, .portfolio),
            (.portefeuille, .portfolio),
            (.palette, .portfolio),
            (.ecranProjet, .project(RefonteDemoSeed.portfolioFocusProjectStableID, .pilotage)),
            (.aRisque, .atRisk),
            (.sectionProjetsFinale, .portfolio),
        ]
        for (ecran, attendue) in routes {
            #expect(ecran.cible == .fenetrePrincipale(attendue),
                    "\(ecran.rawValue) n'ouvre pas la bonne route")
        }
    }

    /// Les écrans de réunion n'ont pas changé de cible : le nouveau cas de
    /// `Cible` s'ajoute, il ne redirige rien.
    @Test("Les douze écrans de réunion gardent leur cible")
    func ciblesDeReunionIntactes() {
        #expect(RecetteScreen.cockpit.cible == .demonstration)
        #expect(RecetteScreen.posteDePilotage.cible == .demonstration)
        #expect(RecetteScreen.oneOnOneSession.cible == .entretienMene)
        #expect(RecetteScreen.collaboratorSession.cible == .entretienSubi)
        #expect(RecetteScreen.atelierPlanche.cible == .atelier)
    }

    /// Seul `p1c` porte un terme de palette : c'est le « ged » de la capture
    /// `1c-palette-cmdk.png`, et le semis garantit qu'il trouve deux projets.
    @Test("Seul l'écran de la palette porte un terme de recherche")
    func termeDePalette() {
        #expect(RecetteScreen.palette.termeDePalette == RefonteDemoSeed.portfolioPaletteQuery)
        #expect(RecetteScreen.palette.termeDePalette == "ged")
        for ecran in RecetteScreen.allCases where ecran != .palette {
            #expect(ecran.termeDePalette == nil, "\(ecran.rawValue) ne devrait pas ouvrir la palette")
        }
    }

    // MARK: - Le semis ne sort pas du bundle de recette

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    private static var racineDuDepot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racineDuDepot.appendingPathComponent(chemin),
                     encoding: .utf8)) ?? ""
    }

    /// Les **deux** items de menu qui sèment un jeu de démonstration doivent
    /// être **grisés** hors bundle de recette.
    ///
    /// Le semis écrit dans le store du processus qui le montre, et depuis le
    /// lot 0 de la refonte des projets il y verse aussi soixante-deux projets
    /// actifs et quatorze archivés : un clic dans l'application de tous les
    /// jours polluait le store de **production**, sans confirmation ni retour
    /// en arrière. Une lecture des sources, parce qu'un `Commands` ne
    /// s'instancie pas depuis un test — et parce qu'une garde retirée ne
    /// change l'état d'aucun modèle.
    @Test("Le semis de démonstration est grisé hors bundle de recette")
    func semisGardeParLEnvironnement() {
        let source = Self.source("OneToOne/Views/Menus/MeetingCommands.swift")
        #expect(!source.isEmpty, "MeetingCommands.swift introuvable")
        // La garde, et la variable exacte qu'elle lit — la même que le semis
        // automatique de `ContentView.maybeSeedRefonteDemo`.
        #expect(source.contains("ContentView.seedDemoEnvironmentKey"),
                "la garde doit lire la variable d'environnement du bundle de recette")
        // Les deux items : « refonte » (réunions + portefeuille) et
        // « atelier » (une réunion et ses planches). Le second en verse moins,
        // pas moins gravement.
        let gardes = source.components(separatedBy: ".disabled(demoContext == nil || !semisAutorise)")
            .count - 1
        #expect(gardes == 2, "les deux items de semis doivent être grisés, pas un seul")
        // Et la forme nue, qui ne gardait que l'absence de conteneur, a disparu
        // des deux — `contains` distingue bien les deux formes, la garde
        // complète n'ayant pas la parenthèse fermante après `nil`.
        #expect(!source.contains(".disabled(demoContext == nil)"),
                "un item de semis gardé par le seul conteneur écrirait en production")
        // Un item grisé sans raison est un défaut, pas une garde.
        #expect(MeetingCommands.semisReserveALaRecette == "Réservé au bundle de recette")
        let infobulles = source.components(separatedBy: "Self.semisReserveALaRecette").count - 1
        #expect(infobulles == 2, "l'infobulle est posée sur les deux items grisés")
    }

    /// Un écran de la fenêtre principale n'ouvre aucune réunion : son mode ne
    /// sert à rien, mais il doit rester une valeur définie — `RecetteScreen.mode`
    /// est total.
    @Test("Le mode d'un écran de fenêtre principale est neutre")
    func modeNeutre() {
        for ecran in RecetteScreen.allCases {
            guard case .fenetrePrincipale = ecran.cible else { continue }
            #expect(ecran.mode == .prepare)
        }
    }
}
