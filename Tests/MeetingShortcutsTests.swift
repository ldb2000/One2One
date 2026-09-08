import Testing
import Foundation
import SwiftUI
@testable import OneToOne

/// Spec §1.4 : la table des raccourcis est une table. Ce test est le seul
/// endroit qui la relie au texte de la spec, et le seul qui interdise un
/// second déclarant silencieux.
@Suite("Raccourcis de l'écran de réunion (spec §1.4)")
struct MeetingShortcutsTests {

    /// La première colonne de la table §1.4, recopiée à la lettre. `/` en
    /// début de ligne y figure aussi, mais c'est la palette de commandes de
    /// note, pas un raccourci clavier : elle n'est pas dans cette liste.
    private let specJetons = ["⌘K", "⌘M", "⌘⇧A", "⌘⇧S", "⌘⇧N", "⌘⇧V", "⌘⏎", "⌃⌘F"]

    @Test("chaque raccourci de la spec est déclaré dans la table")
    func tableCouvreLaSpec() {
        let declares = Set(MeetingShortcut.allCases.map(\.jeton))
        for jeton in specJetons {
            #expect(declares.contains(jeton), "raccourci \(jeton) absent de MeetingShortcut")
        }
    }

    @Test("la table ne déclare rien que la spec ne demande")
    func tableNAjouteRien() {
        for raccourci in MeetingShortcut.allCases {
            #expect(specJetons.contains(raccourci.jeton),
                    "\(raccourci.jeton) n'est pas dans la table §1.4")
        }
    }

    @Test("aucune combinaison n'est déclarée deux fois dans la table")
    func aucunDoublonDansLaTable() {
        #expect(MeetingShortcut.doublons().isEmpty,
                "doublons : \(MeetingShortcut.doublons())")
        #expect(MeetingShortcut.allCases.count == specJetons.count)
    }

    @Test("chaque raccourci porte un libellé français et un jeton lisible")
    func libellesRenseignes() {
        for raccourci in MeetingShortcut.allCases {
            #expect(!raccourci.libelle.isEmpty)
            #expect(!raccourci.jeton.isEmpty)
        }
    }

    @Test("le jeton se déduit de la touche et des modificateurs, sans les répéter")
    func jetonCoherentAvecLaCombinaison() {
        for raccourci in MeetingShortcut.allCases {
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
        for raccourci in MeetingShortcut.allCases {
            guard case .menu = raccourci.surface else { continue }
            #expect(source.contains("MeetingShortcut.\(raccourci.rawValue)"),
                    "MeetingCommands doit prendre \(raccourci.jeton) dans la table")
        }
        // Plus aucun littéral des raccourcis §1.4 dans le menu : la table est
        // la seule à les épeler.
        #expect(!source.contains("keyboardShortcut(\"k\", modifiers: .command)"))
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
    /// `MeetingShortcut.note` et renvoyé comme décision produit.
    @Test("aucun second déclarant hors exceptions nommées")
    func aucunSecondDeclarant() {
        let motifs: [String: String] = [
            "⌘K": "keyboardShortcut(\"k\", modifiers: .command)",
            "⌘M": "keyboardShortcut(\"m\", modifiers: .command)",
            "⌘⇧A": "keyboardShortcut(\"a\", modifiers: [.command, .shift])",
            "⌘⇧S": "keyboardShortcut(\"s\", modifiers: [.command, .shift])",
            "⌘⇧N": "keyboardShortcut(\"n\", modifiers: [.command, .shift])",
            "⌘⇧V": "keyboardShortcut(\"v\", modifiers: [.command, .shift])",
            "⌃⌘F": "keyboardShortcut(\"f\", modifiers: [.control, .command])",
        ]
        // Déclarants légitimes. `Views/Menus/MeetingShortcut.swift` n'y figure
        // jamais : la table donne `key` et `modifiers`, elle n'appelle pas
        // `keyboardShortcut` avec des littéraux.
        //
        // Les trois entrées de `Views/Meeting/Session/**` sont des doublons
        // **assumés**, chacun commenté dans son fichier : le dossier est tenu
        // par un correctif concurrent (#42) et le lot 19c ne l'ouvre pas.
        // Toute entrée nouvelle dans cette table doit être justifiée en PR.
        let attendus: [String: Set<String>] = [
            "⌘K": ["Views/Meeting/Session/SessionAssistantPanel.swift"],
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

    @Test("la feuille d'aide rend la table, elle n'en tient pas une seconde")
    func feuilleLitLaTable() {
        let source = Self.source("OneToOne/Views/Menus/MeetingShortcutsSheet.swift")
        #expect(!source.isEmpty, "MeetingShortcutsSheet.swift introuvable")
        #expect(source.contains("MeetingShortcut.allCases"))
        for raccourci in MeetingShortcut.allCases {
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
