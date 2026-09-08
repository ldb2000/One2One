#!/usr/bin/env swift
// window-titles.swift — les titres des fenêtres à l'écran d'une application,
// désignée par le nom de son processus.
//
// Usage
//   swift Scripts/window-titles.swift MSTeams [MicrosoftTeams …]
//   → une ligne par fenêtre : « <propriétaire>\t<pid>\t<titre> »
//
// À quoi ça sert
//   `Scripts/recette-run.sh` refuse de lancer une recette pendant une réunion
//   Teams : elle redimensionne des fenêtres et photographie l'écran. Encore
//   faut-il savoir si Teams est en appel, ce qui ne se lit que dans le **titre**
//   de ses fenêtres.
//
//   Pourquoi pas AppleScript : `first application process whose unix id is …`
//   résout mal le processus quand deux instances partagent le
//   `CFBundleIdentifier`, et c'est ainsi qu'une fenêtre de production a été
//   redimensionnée pendant la recette des vagues 1-4 (écart (c) n° 7). Ici, on
//   lit, on ne touche à rien.
//
//   Pourquoi pas Python : `Quartz` (pyobjc) n'est pas dans le python3 du
//   système sur ce poste — un garde-fou muet est pire qu'aucun garde-fou.
//
// Sortie vide = aucune fenêtre nommée pour cette application. Code 0 dans tous
// les cas : c'est un outil de lecture, pas un test.
//
// Le nom de propriétaire est comparé sans espaces ni casse : « Microsoft Teams »
// correspond à `MicrosoftTeams`.

import CoreGraphics
import Foundation

let cibles = CommandLine.arguments
    .dropFirst()
    .map { $0.replacingOccurrences(of: " ", with: "").lowercased() }

guard !cibles.isEmpty else {
    FileHandle.standardError.write(Data(
        "usage : swift Scripts/window-titles.swift <NomDeProcessus> […]\n".utf8))
    exit(0)
}

let fenetres = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
    as? [[String: Any]] ?? []

for fenetre in fenetres {
    let proprietaire = fenetre[kCGWindowOwnerName as String] as? String ?? ""
    let normalise = proprietaire.replacingOccurrences(of: " ", with: "").lowercased()
    guard cibles.contains(normalise) else { continue }
    let titre = fenetre[kCGWindowName as String] as? String ?? ""
    guard !titre.isEmpty else { continue }
    let pid = fenetre[kCGWindowOwnerPID as String] as? Int ?? 0
    print("\(proprietaire)\t\(pid)\t\(titre)")
}
