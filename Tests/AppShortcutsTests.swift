import Testing
import Foundation
import SwiftUI
@testable import OneToOne

/// Spec §1.4 de la refonte réunion, **amendée** par la décision **D1** de la
/// refonte de la gestion des projets : la table des raccourcis est une table.
/// Ce test est le seul endroit qui la relie au texte des specs, et le seul qui
/// interdise un second déclarant silencieux.
///
/// La table s'appelle `AppShortcut` depuis D1 : `⌘K` va à la **palette**, qui
/// s'ouvre depuis n'importe quel écran, et l'assistant de réunion passe à
/// `⌘⇧K` (ADR `docs/adr/2026-09-09-palette-commande-k.md`).
@Suite("Raccourcis de l'application")
struct AppShortcutsTests {

    /// Les jetons attendus : la première colonne de la table §1.4, `⌘K`
    /// réaffecté à la palette et `⌘⇧K` ajouté pour l'assistant (D1). `/` en
    /// début de ligne figure aussi dans la spec réunion, mais c'est la palette
    /// de commandes de note, pas un raccourci clavier : elle n'est pas dans
    /// cette liste.
    private let specJetons = ["⌘K", "⌘⇧K", "⌘M", "⌘⇧A", "⌘⇧S", "⌘⇧N", "⌘⇧V", "⌘⏎", "⌃⌘F"]

    @Test("chaque raccourci de la spec est déclaré dans la table")
    func tableCouvreLaSpec() {
        let declares = Set(AppShortcut.allCases.map(\.jeton))
        for jeton in specJetons {
            #expect(declares.contains(jeton), "raccourci \(jeton) absent de AppShortcut")
        }
    }

    @Test("la table ne déclare rien que la spec ne demande")
    func tableNAjouteRien() {
        for raccourci in AppShortcut.allCases {
            #expect(specJetons.contains(raccourci.jeton),
                    "\(raccourci.jeton) n'est pas dans la table §1.4")
        }
    }

    @Test("aucune combinaison n'est déclarée deux fois dans la table")
    func aucunDoublonDansLaTable() {
        #expect(AppShortcut.doublons().isEmpty,
                "doublons : \(AppShortcut.doublons())")
        #expect(AppShortcut.allCases.count == specJetons.count)
    }

    @Test("chaque raccourci porte un libellé français et un jeton lisible")
    func libellesRenseignes() {
        for raccourci in AppShortcut.allCases {
            #expect(!raccourci.libelle.isEmpty)
            #expect(!raccourci.jeton.isEmpty)
        }
    }

    @Test("le jeton se déduit de la touche et des modificateurs, sans les répéter")
    func jetonCoherentAvecLaCombinaison() {
        for raccourci in AppShortcut.allCases {
            if raccourci.modifiers.contains(.shift) {
                #expect(raccourci.jeton.contains("⇧"), "\(raccourci.jeton) porte ⇧")
            } else {
                #expect(!raccourci.jeton.contains("⇧"))
            }
            if raccourci.modifiers.contains(.control) {
                #expect(raccourci.jeton.contains("⌃"))
            }
            #expect(raccourci.jeton.contains("⌘"), "tous les raccourcis §1.4 sont ⌘")
        }
    }

    @Test("les raccourcis de surface menu sont ceux que MeetingCommands déclare")
    func menuDeclareSesRaccourcis() {
        let source = Self.source("OneToOne/Views/Menus/MeetingCommands.swift")
        #expect(!source.isEmpty, "MeetingCommands.swift introuvable")
        for raccourci in AppShortcut.allCases {
            guard case .menu = raccourci.surface else { continue }
            #expect(source.contains("AppShortcut.\(raccourci.rawValue)"),
                    "MeetingCommands doit prendre \(raccourci.jeton) dans la table")
        }
        // Plus aucun littéral des raccourcis §1.4 dans le menu : la table est
        // la seule à les épeler.
        #expect(!source.contains("keyboardShortcut(\"k\", modifiers: .command)"))
        #expect(!source.contains("keyboardShortcut(\"k\", modifiers: [.command, .shift])"))
        #expect(!source.contains("keyboardShortcut(\"m\", modifiers: .command)"))
        #expect(!source.contains("keyboardShortcut(\"v\", modifiers: [.command, .shift])"))
        #expect(!source.contains("keyboardShortcut(\"s\", modifiers: [.command, .shift])"))
        #expect(!source.contains("keyboardShortcut(\"f\", modifiers: [.control, .command])"))
    }

    /// Le vrai garde-fou : personne ne redéclare l'un des sept raccourcis
    /// (⌘⏎ excepté, cf. ci-dessous) ailleurs dans les sources.
    ///
    /// ⌘⏎ est hors du scan : `.keyboardShortcut(.defaultAction)` est le geste
    /// standard du bouton par défaut d'une feuille, et le dépôt en pose une
    /// dizaine. Le conflit réel — « Générer le rapport » dans le menu contre
    /// « valider le composeur » dans la spec — est documenté par
    /// `AppShortcut.note` et renvoyé comme décision produit.
    @Test("aucun second déclarant hors exceptions nommées")
    func aucunSecondDeclarant() {
        let motifs: [String: String] = [
            "⌘K": "keyboardShortcut(\"k\", modifiers: .command)",
            "⌘⇧K": "keyboardShortcut(\"k\", modifiers: [.command, .shift])",
            "⌘M": "keyboardShortcut(\"m\", modifiers: .command)",
            "⌘⇧A": "keyboardShortcut(\"a\", modifiers: [.command, .shift])",
            "⌘⇧S": "keyboardShortcut(\"s\", modifiers: [.command, .shift])",
            "⌘⇧N": "keyboardShortcut(\"n\", modifiers: [.command, .shift])",
            "⌘⇧V": "keyboardShortcut(\"v\", modifiers: [.command, .shift])",
            "⌃⌘F": "keyboardShortcut(\"f\", modifiers: [.control, .command])",
        ]
        // Déclarants légitimes. `Views/Menus/AppShortcut.swift` n'y figure
        // jamais : la table donne `key` et `modifiers`, elle n'appelle pas
        // `keyboardShortcut` avec des littéraux.
        //
        // Les trois entrées de `Views/Meeting/Session/**` sont des doublons
        // **assumés**, chacun commenté dans son fichier : le dossier est tenu
        // par un correctif concurrent (#42) et le lot 19c ne l'ouvre pas.
        // Toute entrée nouvelle dans cette table doit être justifiée en PR.
        //
        // `⌘K` n'admet **aucun** second déclarant : la palette est le seul
        // usage, et elle prend son raccourci dans la table (décision **D1**).
        // C'est `SessionAssistantPanel` qui porte désormais `⌘⇧K`, le doublon
        // assumé de l'assistant en mode séance.
        let attendus: [String: Set<String>] = [
            "⌘K": [],
            "⌘⇧K": ["Views/Meeting/Session/SessionAssistantPanel.swift"],
            "⌘M": ["Views/Meeting/Session/TimeRailColumn.swift"],
            "⌘⇧A": ["Views/Meeting/Spaces/Transcript/TranscriptColumn.swift"],
            "⌘⇧S": [],
            "⌘⇧N": ["Views/Meeting/Spaces/Notes/NoteComposer.swift"],
            "⌘⇧V": [],
            "⌃⌘F": ["Views/Meeting/Session/SessionFullscreenPresenter.swift"],
        ]
        for (jeton, motif) in motifs {
            let trouves = Self.fichiersContenant(motif)
            #expect(trouves == attendus[jeton],
                    "\(jeton) : déclarants \(trouves.sorted()) ≠ \(attendus[jeton]!.sorted())")
        }
    }

    @Test("la palette prend son raccourci dans la table, et le menu l'annonce")
    func paletteDansLaTable() {
        let palette = AppShortcut.palette
        #expect(palette.jeton == "⌘K")
        #expect(palette.libelle
            == "Palette — projets et actions, depuis n'importe quel écran")
        // La palette est un item de menu natif : c'est le seul mécanisme qui
        // fonctionne « depuis n'importe quel écran », sans vue focalisée.
        guard case .menu(let item) = palette.surface else {
            Issue.record("la palette doit être déclarée en surface menu")
            return
        }
        #expect(item == .palette)
        // L'assistant de réunion a cédé ⌘K et pris ⌘⇧K.
        #expect(AppShortcut.assistant.jeton == "⌘⇧K")

        let source = Self.source("OneToOne/Views/Menus/MeetingCommands.swift")
        #expect(source.contains("AppShortcut.palette"))
        #expect(source.contains("Palette…"))
        // La palette n'est **pas** grisée quand aucune réunion n'a le focus :
        // c'est tout l'intérêt du raccourci.
        #expect(!source.contains("isEnabled(.palette)"))
    }

    @Test("plus aucune trace du nom MeetingShortcut, ni dans OneToOne/ ni dans Tests/")
    func plusDeMeetingShortcut() {
        // D1 interdit un `typealias MeetingShortcut = AppShortcut` à la fin du
        // lot : tous les appelants sont renommés. Le scan couvre **aussi**
        // `Tests/`, où trois commentaires citaient encore l'ancien nom de
        // cette suite — un renvoi faux dans un test est une piste morte pour
        // qui cherche le garde-fou dont il s'inspire.
        //
        // Deux exclusions, et deux seulement :
        // - `MeetingShortcutsSheet`, la feuille du menu `⋯` d'une **réunion**,
        //   qui garde son nom à dessein (cf. l'ADR) — un fichier n'est excusé
        //   que si **toutes** ses occurrences sont celles de la feuille ;
        // - ce fichier-ci, qui doit épeler le mot interdit pour l'interdire.
        let moi = "Tests/AppShortcutsTests.swift"
        let trouves = Self.fichiersDuDepotContenant("MeetingShortcut",
                                                    dans: ["OneToOne", "Tests"])
            .subtracting([moi])
            .filter { chemin in
                let contenu = Self.source(chemin)
                return contenu.components(separatedBy: "MeetingShortcut")
                    .dropFirst()
                    .contains { !$0.hasPrefix("sSheet") }
            }
        #expect(trouves.isEmpty, "MeetingShortcut subsiste dans \(trouves.sorted())")
        // Le garde-fou garde-t-il quelque chose ? Sans ces attentes, un scan
        // qui ne lirait plus aucun fichier passerait tout aussi vert.
        #expect(Self.fichiersDuDepotContenant("MeetingShortcut",
                                              dans: ["OneToOne", "Tests"]).contains(moi))
        #expect(Self.fichiersDuDepotContenant("AppShortcut",
                                              dans: ["OneToOne"]).count >= 3)
    }

    @Test("la feuille d'aide rend la table, elle n'en tient pas une seconde")
    func feuilleLitLaTable() {
        let source = Self.source("OneToOne/Views/Menus/MeetingShortcutsSheet.swift")
        #expect(!source.isEmpty, "MeetingShortcutsSheet.swift introuvable")
        #expect(source.contains("AppShortcut.allCases"))
        for raccourci in AppShortcut.allCases {
            #expect(!source.contains("\"\(raccourci.jeton)\""),
                    "la feuille ne doit pas réécrire le jeton \(raccourci.jeton)")
        }
    }

    @Test("le menu ⋯ de la barre du haut ouvre la feuille")
    func menuPlusOuvreLaFeuille() {
        let source = Self.source("OneToOne/Views/Meeting/MeetingTopChromeBar.swift")
        #expect(source.contains("MeetingShortcutsSheet()"))
        #expect(source.contains("Raccourcis clavier"))
    }

    // MARK: - Lecture des sources

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    /// Motif déjà employé par `Tests/ReviewStateTests.swift`.
    private static var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8)) ?? ""
    }

    /// Chemins **depuis la racine du dépôt** des fichiers Swift de `dossiers`
    /// contenant `motif`.
    ///
    /// Deux fonctions et non une paramétrée : la table `attendus` du test des
    /// seconds déclarants énumère des chemins relatifs à `OneToOne/` depuis le
    /// lot 19c, et les préfixer tous pour un seul appelant aurait touché à un
    /// garde-fou qui n'a rien demandé.
    private static func fichiersDuDepotContenant(_ motif: String,
                                                 dans dossiers: [String]) -> Set<String> {
        var trouves: Set<String> = []
        for dossier in dossiers {
            let base = racine.appendingPathComponent(dossier)
            guard let enumerateur = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: nil) else { continue }
            let prefixe = base.standardizedFileURL.path + "/"
            for cas in enumerateur {
                guard let url = cas as? URL, url.pathExtension == "swift" else { continue }
                guard let contenu = try? String(contentsOf: url, encoding: .utf8),
                      contenu.contains(motif) else { continue }
                let complet = url.standardizedFileURL.path
                guard complet.hasPrefix(prefixe) else { continue }
                trouves.insert(dossier + "/" + String(complet.dropFirst(prefixe.count)))
            }
        }
        return trouves
    }

    /// Chemins relatifs, sous `OneToOne/`, des fichiers Swift contenant `motif`.
    private static func fichiersContenant(_ motif: String) -> Set<String> {
        let base = racine.appendingPathComponent("OneToOne")
        guard let enumerateur = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil)
        else { return [] }
        var trouves: Set<String> = []
        let prefixe = base.standardizedFileURL.path + "/"
        for cas in enumerateur {
            guard let url = cas as? URL, url.pathExtension == "swift" else { continue }
            guard let contenu = try? String(contentsOf: url, encoding: .utf8),
                  contenu.contains(motif) else { continue }
            let complet = url.standardizedFileURL.path
            guard complet.hasPrefix(prefixe) else { continue }
            trouves.insert(String(complet.dropFirst(prefixe.count)))
        }
        return trouves
    }
}
