# Lot 19c — Clôture : raccourcis, finitions, outillage de recette, documentation

> **Pour un exécutant agentique :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`
> (exécution en session) ou `superpowers:subagent-driven-development`. Les étapes sont des
> cases à cocher (`- [ ]`).

**But :** solder ce que les lots 0A à 18 ont renvoyé au lot 19 et que le lot 19a (PR #45,
retrait du code mort) n'a pas fait : la table des raccourcis §1.4 déclarée une fois et
vérifiée, les onze finitions renvoyées par la recette des vagues 1–4, l'outillage de recette
qui ne mente plus, la documentation d'architecture remise en accord avec le code, les DTO de
sauvegarde des neuf tables du lot 0B, et un `STATUS.md` lisible.

**Architecture :** aucune vue nouvelle sauf une feuille « Raccourcis ». Une table pure
(`MeetingShortcut`) devient la source de vérité des raccourcis de réunion, consommée par
`MeetingCommands` et par la feuille, et vérifiée par un test qui **relit les sources** —
le dépôt a déjà ce motif (`Tests/ReviewStateTests.swift` lit `MeetingView.swift` via
`#filePath`). Les finitions sont des corrections locales dans les vues, avec une fonction pure
testée quand la règle est partagée (teinte d'un niveau de risque). Les scripts de recette
gagnent des garde-fous ; les codes d'écran sont **dérivés** de `RecetteScreen.swift` au lieu
d'être recopiés.

**Pile technique :** SwiftUI + AppKit (`NSViewRepresentable`), SwiftData, Swift Testing +
XCTest, bash.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` (branche
`origin/docs/refonte-reunion-programme` — elle n'a jamais été fusionnée dans la pile ;
`git show origin/docs/refonte-reunion-programme:docs/superpowers/specs/refonte-2026-09/specs-one2one.md`)
§1.1, §1.2, §1.4, §2.1, §2.2, §4.1, §4.3 ; plan directeur
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §4 (D0–D11), §5 (lot 19),
§7, §8, §9 ; recette
`docs/superpowers/specs/refonte-2026-09/recette/2026-09-07-recette-vagues-1-4.md`, table
« (c) — écarts fonctionnels ».

## Contraintes globales

- Aucune dépendance SwiftPM nouvelle. Aucune version de schéma nouvelle (`CurrentSchema`
  reste `SchemaV3`).
- Aucune couleur hors `One2OneToken`. Aucune fonte hors `PlexFont` / `Font.plexSans` /
  `Font.plexMono`.
- `OneToOne/Views/MeetingView.swift` : **retraits uniquement**, jamais d'ajout.
- Interdits en écriture (lots concurrents en cours d'intégration) :
  `OneToOne/Views/Meeting/Workshop/**` et `.../Session/**` (lot 18 et correctif #42),
  `OneToOne/Views/Meeting/OneOnOne/CollaboratorPrep/**` (lot 14). Un `lineLimit` y est
  toléré seulement s'il est strictement nécessaire — ce plan n'en prévoit aucun.
- Libellés d'interface et commentaires en **français**, symboles en anglais.
- `swift build` propre ; `swift test` complet vert avant la PR. Référence de la base
  (#45, mesurée le 2026-09-08 à 05:27) : **1 898 tests Swift Testing / 234 suites**, plus la
  cible XCTest, run complet en exit 0.
- **Aucun lancement d'application graphique** dans ce lot : les scripts de recette sont
  modifiés et relus, pas exécutés jusqu'à l'ouverture d'une fenêtre.
- Énums persistées en `…Raw: String` + wrapper calculé.

---

## Carte des fichiers

| Fichier | Rôle |
| --- | --- |
| `OneToOne/Views/Menus/MeetingShortcut.swift` | **créé** — table pure des 8 raccourcis §1.4 : jeton, libellé, touche, modificateurs, surface de déclaration, note |
| `OneToOne/Views/Menus/MeetingShortcutsSheet.swift` | **créé** — feuille « Raccourcis », lit `MeetingShortcut.allCases` |
| `OneToOne/Views/Menus/MeetingCommands.swift` | consomme la table au lieu des littéraux |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | entrée « Raccourcis clavier… » dans `⋯` + feuille ; titre en style `plain` |
| `OneToOne/Views/Meeting/Capture/CapturesStrip.swift` | retrait du `⌘⇧S` en doublon du menu |
| `OneToOne/Views/EditableTextField.swift` | style `plain` + fonte injectable + ellipsis fiable |
| `OneToOne/Views/DesignSystem/One2OneTypography.swift` | `NSFont.plexSans` / `NSFont.plexMono` |
| `OneToOne/Views/DesignSystem/RiskLevelTint.swift` | **créé** — teinte canonique d'un `MeetingKPI.Level` |
| `OneToOne/Views/Meeting/Spaces/MeetingKPIBand.swift` | `teinte` délègue |
| `OneToOne/Views/Project/ProjectCardPanel.swift` | `color(for:)` délègue ; point de statut en édition ; pied scindé |
| `OneToOne/Views/Meeting/Resources/ResourceTile.swift` | `Citer` / `Envoyer` sur toute pièce |
| `OneToOne/Views/MeetingView.swift` | retrait de la condition qui masquait la bascule `Speakers` |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | retrait de `newTaskPomodoros` |
| 9 vues de réunion | `lineLimit(1)` + `truncationMode(.tail)` |
| `OneToOne/Services/BackupService.swift` | 8 DTO : notes, jalons, interlocuteurs, domaine 1:1 |
| `Scripts/recette-app.sh` | fraîcheur du binaire, `md5`, bundle de recette isolé |
| `Scripts/recette-run.sh` | verrou d'écran, Teams en réunion, codes d'écran dérivés |
| `Tests/MeetingShortcutsTests.swift` | **créé** — exhaustivité et unicité |
| `Tests/RefonteFinitionsTests.swift` | **créé** — les finitions vérifiables |
| `Tests/OneOnOneBackupTests.swift` | **créé** — aller-retour des 8 tables |
| `docs/architecture.md`, `docs/cleanup-report.md`, `CLAUDE.md`, `docs/adr/**`, `STATUS.md`, `docs/superpowers/specs/refonte-2026-09/journal-des-lots.md` | documentation |

---

## Tâche 1 : table des raccourcis, feuille d'aide, test d'exhaustivité

**Fichiers**
- Créer : `OneToOne/Views/Menus/MeetingShortcut.swift`
- Créer : `OneToOne/Views/Menus/MeetingShortcutsSheet.swift`
- Créer : `Tests/MeetingShortcutsTests.swift`
- Modifier : `OneToOne/Views/Menus/MeetingCommands.swift` (littéraux → table)
- Modifier : `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (`⋯` + `.sheet`)
- Modifier : `OneToOne/Views/Meeting/Capture/CapturesStrip.swift:58` (retrait du doublon)

**Interfaces**
- Produit : `enum MeetingShortcut: String, CaseIterable, Sendable` avec
  `var jeton: String`, `var libelle: String`, `var key: KeyEquivalent`,
  `var modifiers: EventModifiers`, `var surface: Surface`, `var note: String?`,
  `static let specJetons: [String]`, `static func doublons() -> [String]`.
- `enum MeetingShortcut.Surface { case menu(MeetingMenuItem), vue(String), global(String) }`.
- Consomme : `MeetingMenuItem` (`OneToOne/Views/Menus/MeetingMenuActions.swift:4`).

**Ce que l'état des lieux a établi** (à ne pas redécouvrir) : les 8 raccourcis existent tous,
le défaut est l'absence de source unique et la présence de doublons. Positions actuelles :
`MeetingCommands.swift` déclare ⌘K (:51), ⌘M (:54), ⌃⌘F (:59), ⌘⇧V (:63), ⌘⇧S (:70),
⌘⏎ (:75, pour « Générer le rapport ») ; `TranscriptColumn.swift:407` déclare ⌘⇧A ;
`NoteComposer.swift:57` déclare ⌘⇧N ; `CapturesStrip.swift:58` redéclare ⌘⇧S ;
`Services/Capture/CaptureHotkeys.swift` + `OneToOneApp.swift:414-430` posent ⌘⇧S et ⌘⇧N en
raccourcis globaux Carbon ; `Session/SessionAssistantPanel.swift:41` (⌘K),
`Session/TimeRailColumn.swift:170` (⌘M), `Session/SessionFullscreenPresenter.swift:162`
(⌃⌘F) redéclarent trois raccourcis **dans un dossier interdit à ce lot**.

Le lot ne supprime donc que le doublon qu'il peut atteindre (⌘⇧S de `CapturesStrip`) et
**inscrit les trois autres comme exceptions nommées** dans le test : elles sont volontaires
(chacune porte déjà son commentaire dans le code), et toute exception *nouvelle* fera échouer
le test.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/MeetingShortcutsTests.swift` :

```swift
import Testing
import Foundation
import SwiftUI
@testable import OneToOne

/// Spec §1.4 : la table des raccourcis est une table. Ce test est le seul
/// endroit qui la relie au texte de la spec, et le seul qui interdise un
/// second déclarant silencieux.
@Suite("Raccourcis de l'écran de réunion (spec §1.4)")
struct MeetingShortcutsTests {

    /// La colonne de gauche de la table §1.4, recopiée à la lettre. `/` en
    /// début de ligne est la palette de notes, pas un raccourci clavier :
    /// elle n'est pas dans cette liste.
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

    @Test("les raccourcis de surface menu sont ceux que MeetingCommands déclare")
    func menuDeclareSesRaccourcis() {
        let source = Self.source("OneToOne/Views/Menus/MeetingCommands.swift")
        for raccourci in MeetingShortcut.allCases {
            guard case .menu = raccourci.surface else { continue }
            #expect(source.contains("MeetingShortcut.\(raccourci.rawValue)"),
                    "MeetingCommands doit prendre \(raccourci.jeton) dans la table")
        }
        // Plus aucun littéral de raccourci de la spec dans le menu : la table
        // est la seule à les épeler.
        #expect(!source.contains("keyboardShortcut(\"k\", modifiers: .command)"))
        #expect(!source.contains("keyboardShortcut(\"m\", modifiers: .command)"))
    }

    /// Le vrai garde-fou : personne ne redéclare l'un des sept raccourcis
    /// (⌘⏎ excepté, cf. `exceptions`) ailleurs dans les vues de réunion.
    @Test("aucun second déclarant hors exceptions nommées")
    func aucunSecondDeclarant() {
        // Chaque motif est la forme textuelle exacte que SwiftUI impose.
        let motifs: [String: String] = [
            "⌘K":  "keyboardShortcut(\"k\", modifiers: .command)",
            "⌘M":  "keyboardShortcut(\"m\", modifiers: .command)",
            "⌘⇧A": "keyboardShortcut(\"a\", modifiers: [.command, .shift])",
            "⌘⇧S": "keyboardShortcut(\"s\", modifiers: [.command, .shift])",
            "⌘⇧N": "keyboardShortcut(\"n\", modifiers: [.command, .shift])",
            "⌘⇧V": "keyboardShortcut(\"v\", modifiers: [.command, .shift])",
            "⌃⌘F": "keyboardShortcut(\"f\", modifiers: [.control, .command])",
        ]
        // Déclarants légitimes, un par raccourci, plus les trois doublons
        // assumés de `Views/Meeting/Session/**` — dossier qu'un correctif
        // concurrent tient (#42) et que le lot 19c n'ouvre pas. Toute entrée
        // nouvelle ici doit être justifiée dans la PR.
        let attendus: [String: Set<String>] = [
            "⌘K":  ["Views/Menus/MeetingCommands.swift",
                    "Views/Meeting/Session/SessionAssistantPanel.swift"],
            "⌘M":  ["Views/Menus/MeetingCommands.swift",
                    "Views/Meeting/Session/TimeRailColumn.swift"],
            "⌘⇧A": ["Views/Meeting/Spaces/Transcript/TranscriptColumn.swift"],
            "⌘⇧S": ["Views/Menus/MeetingCommands.swift"],
            "⌘⇧N": ["Views/Meeting/Spaces/Notes/NoteComposer.swift"],
            "⌘⇧V": ["Views/Menus/MeetingCommands.swift"],
            "⌃⌘F": ["Views/Menus/MeetingCommands.swift",
                    "Views/Meeting/Session/SessionFullscreenPresenter.swift"],
        ]
        for (jeton, motif) in motifs {
            let trouves = Self.fichiersContenant(motif)
            #expect(trouves == attendus[jeton],
                    "\(jeton) : déclarants \(trouves.sorted()) ≠ \(attendus[jeton]!.sorted())")
        }
    }

    // MARK: - Lecture des sources

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
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
        for cas in enumerateur {
            guard let url = cas as? URL, url.pathExtension == "swift" else { continue }
            guard let contenu = try? String(contentsOf: url, encoding: .utf8),
                  contenu.contains(motif) else { continue }
            let complet = url.standardizedFileURL.path
            let prefixe = base.standardizedFileURL.path + "/"
            trouves.insert(String(complet.dropFirst(prefixe.count)))
        }
        return trouves
    }
}
```

- [ ] **Étape 2 : lancer, constater l'échec**

`swift test --filter MeetingShortcutsTests` → échec de compilation (`MeetingShortcut`
inconnu).

- [ ] **Étape 3 : écrire la table**

`OneToOne/Views/Menus/MeetingShortcut.swift` :

```swift
import SwiftUI

/// Les raccourcis de l'écran de réunion, spec §1.4 — **une** déclaration par
/// combinaison, et le seul endroit où la combinaison est épelée.
///
/// Trois surfaces, parce que trois mécanismes distincts portent ces gestes :
/// - `.menu` : un item de `MeetingCommands`, qui lit la table ci-dessous ;
/// - `.vue` : un `keyboardShortcut` local, quand le geste a besoin d'un
///   contexte que le menu n'a pas (le segment survolé, le champ à focaliser) ;
/// - `.global` : un raccourci système Carbon (`CaptureHotkeys`, lot 8), actif
///   même quand l'application n'a pas le focus.
///
/// `Tests/MeetingShortcutsTests.swift` vérifie que la table couvre la spec,
/// qu'aucune combinaison n'y figure deux fois, que `MeetingCommands` prend
/// bien ses raccourcis ici, et qu'aucun second déclarant n'apparaît dans les
/// vues sans être nommé.
enum MeetingShortcut: String, CaseIterable, Sendable {
    case assistant, marqueur, actionDepuisSelection, capture, note, collerRessource,
         validerComposeur, seancePleinEcran

    enum Surface: Sendable {
        /// Item de menu natif : `MeetingCommands` en tire touche et modificateurs.
        case menu(MeetingMenuItem)
        /// Raccourci local d'une vue, avec son chemin sous `OneToOne/`.
        case vue(String)
        /// Raccourci système, avec le nom de sa spécification `CaptureHotkey`.
        case global(String)
    }

    /// Le jeton affiché : celui de la première colonne de la table §1.4.
    var jeton: String {
        switch self {
        case .assistant:             return "⌘K"
        case .marqueur:              return "⌘M"
        case .actionDepuisSelection: return "⌘⇧A"
        case .capture:               return "⌘⇧S"
        case .note:                  return "⌘⇧N"
        case .collerRessource:       return "⌘⇧V"
        case .validerComposeur:      return "⌘⏎"
        case .seancePleinEcran:      return "⌃⌘F"
        }
    }

    /// L'effet, dans les mots de la spec §1.4.
    var libelle: String {
        switch self {
        case .assistant:
            return "Assistant — barre d'invocation, contexte = réunion courante"
        case .marqueur:
            return "Marqueur sur l'axe temps à l'instant courant"
        case .actionDepuisSelection:
            return "Créer une action depuis la sélection"
        case .capture:
            return "Capture d'écran de la source configurée"
        case .note:
            return "Nouvelle ligne de note au timecode courant"
        case .collerRessource:
            return "Coller un lien ou une image dans les ressources"
        case .validerComposeur:
            return "Valider le composeur (action, engagement, sujet)"
        case .seancePleinEcran:
            return "Mode séance plein écran"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .assistant:             return "k"
        case .marqueur:              return "m"
        case .actionDepuisSelection: return "a"
        case .capture:               return "s"
        case .note:                  return "n"
        case .collerRessource:       return "v"
        case .validerComposeur:      return .return
        case .seancePleinEcran:      return "f"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .assistant, .marqueur, .validerComposeur:
            return .command
        case .actionDepuisSelection, .capture, .note, .collerRessource:
            return [.command, .shift]
        case .seancePleinEcran:
            return [.control, .command]
        }
    }

    var surface: Surface {
        switch self {
        case .assistant:             return .menu(.assistant)
        case .marqueur:              return .menu(.marker)
        case .collerRessource:       return .menu(.pasteResource)
        case .capture:               return .menu(.captureNow)
        case .seancePleinEcran:      return .menu(.sessionFullscreen)
        case .actionDepuisSelection:
            return .vue("Views/Meeting/Spaces/Transcript/TranscriptColumn.swift")
        case .note:
            return .vue("Views/Meeting/Spaces/Notes/NoteComposer.swift")
        case .validerComposeur:
            return .vue("Views/Meeting/Spaces/Rail/ActionComposer.swift")
        }
    }

    /// Ce que la feuille d'aide ajoute au libellé : la précision qui évite un
    /// ticket. Renseignée seulement quand il y a une surprise à annoncer.
    var note: String? {
        switch self {
        case .capture:
            return "Aussi en raccourci système, si la case est cochée dans les réglages ; "
                 + "à la première utilisation, ouvre le sélecteur de source."
        case .note:
            return "Depuis la pastille flottante aussi, en raccourci système."
        case .validerComposeur:
            return "Le menu Réunion emploie ⌘⏎ pour « Générer le rapport » : "
                 + "les composeurs interceptent la touche eux-mêmes."
        case .actionDepuisSelection:
            return "Sur la phrase de transcription survolée."
        default:
            return nil
        }
    }

    /// Les combinaisons déclarées plus d'une fois dans la table. Vide attendu.
    static func doublons() -> [String] {
        var vus: Set<String> = []
        var doubles: [String] = []
        for raccourci in allCases {
            if !vus.insert(raccourci.jeton).inserted { doubles.append(raccourci.jeton) }
        }
        return doubles
    }
}

extension View {
    /// Pose un raccourci de la table. Le seul chemin autorisé.
    func meetingShortcut(_ raccourci: MeetingShortcut) -> some View {
        keyboardShortcut(raccourci.key, modifiers: raccourci.modifiers)
    }
}
```

- [ ] **Étape 4 : faire consommer la table par `MeetingCommands`**

Dans `OneToOne/Views/Menus/MeetingCommands.swift`, remplacer les cinq littéraux des
raccourcis §1.4 (⌘K, ⌘M, ⌃⌘F, ⌘⇧V, ⌘⇧S) par `.meetingShortcut(MeetingShortcut.<cas>)`.
Exemple pour l'assistant :

```swift
            Button("Assistant…") { menu?.openAssistant() }
                .meetingShortcut(MeetingShortcut.assistant)
                .disabled(!isEnabled(.assistant))
```

Ne pas toucher aux raccourcis hors §1.4 (⌘⇧C, ⌘⇧E, ⌘⇧R, ⌘⇧T, ⌘⌫), ni au ⌘⏎ de
« Générer le rapport » : le changer est une décision produit, renvoyée (cf. §Renvois).

- [ ] **Étape 5 : retirer le doublon atteignable**

`OneToOne/Views/Meeting/Capture/CapturesStrip.swift:58` — supprimer le
`.keyboardShortcut("s", modifiers: [.command, .shift])`. Le badge « ⌘⇧S » de la bande
(`:164`) reste : le menu et le raccourci système portent le geste. Ajouter un commentaire
d'une ligne qui dit pourquoi.

- [ ] **Étape 6 : écrire la feuille « Raccourcis »**

`OneToOne/Views/Menus/MeetingShortcutsSheet.swift` :

```swift
import SwiftUI

/// La feuille « Raccourcis », ouverte depuis le menu `⋯` de la barre du haut.
/// Rend la table `MeetingShortcut` — il n'y a donc pas de seconde liste à
/// tenir en phase avec les déclarations.
struct MeetingShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Raccourcis clavier")
                .font(.plexSans(15, .semibold))
                .foregroundStyle(One2OneToken.ink1)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider().overlay(One2OneToken.hair)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(MeetingShortcut.allCases, id: \.self) { raccourci in
                        ligne(raccourci)
                    }
                    Divider().overlay(One2OneToken.hair).padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("/ en début de ligne")
                            .font(.plexMono(11, .semibold))
                            .foregroundStyle(One2OneToken.ink2)
                        Text("Palette de commandes de note : /action /décision /risque "
                             + "/citer /privé /engagement /feedback /promesse /demande /preuve")
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            Divider().overlay(One2OneToken.hair)
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 440)
        .background(One2OneToken.surface)
    }

    private func ligne(_ raccourci: MeetingShortcut) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(raccourci.jeton)
                .font(.plexMono(11, .semibold))
                .foregroundStyle(One2OneToken.ink1)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.bgApp)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.hair, lineWidth: 1)
                )
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(raccourci.libelle)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = raccourci.note {
                    Text(note)
                        .font(.plexSans(11))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Étape 7 : brancher la feuille sur `⋯`**

Dans `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` : un `@State private var
showsShortcuts = false`, une entrée dans `moreMenu` juste avant le `Divider()` qui précède
« Supprimer la réunion… » :

```swift
            Button { showsShortcuts = true } label: {
                Label("Raccourcis clavier…", systemImage: "keyboard")
            }
```

et, sur le corps de la barre (là où vivent déjà ses autres présentations),
`.sheet(isPresented: $showsShortcuts) { MeetingShortcutsSheet() }`.

- [ ] **Étape 8 : `swift build` puis le test**

`swift build` puis `swift test --filter MeetingShortcutsTests` → tout passe. Si
`aucunSecondDeclarant` échoue sur un fichier non listé, c'est un vrai doublon : le retirer
s'il est atteignable, sinon l'ajouter à `attendus` **avec** une justification dans la PR.

- [ ] **Étape 9 : commit**

```bash
git add OneToOne/Views/Menus/MeetingShortcut.swift \
        OneToOne/Views/Menus/MeetingShortcutsSheet.swift \
        OneToOne/Views/Menus/MeetingCommands.swift \
        OneToOne/Views/Meeting/MeetingTopChromeBar.swift \
        OneToOne/Views/Meeting/Capture/CapturesStrip.swift \
        Tests/MeetingShortcutsTests.swift
git commit -m "feat(refonte): table unique des raccourcis §1.4 et feuille d'aide (lot 19c)"
```

---

## Tâche 2 : le titre de réunion redevient un titre (écart (c) n° 3 et n° 11)

**Fichiers**
- Modifier : `OneToOne/Views/EditableTextField.swift:503-530`
- Modifier : `OneToOne/Views/DesignSystem/One2OneTypography.swift` (fin de fichier)
- Modifier : `OneToOne/Views/Meeting/MeetingTopChromeBar.swift:531-535`
- Créer : `Tests/RefonteFinitionsTests.swift`

**Interfaces**
- Produit : `EditableTextField(placeholder:text:isSecure:style:font:)` avec
  `enum EditableTextField.Style { case bezeled, plain }` (défaut `.bezeled`) et
  `font: NSFont?` (défaut `nil` → fonte système, comportement actuel).
- Produit : `NSFont.plexSans(_ size: CGFloat, _ weight: PlexWeight = .regular) -> NSFont` et
  `NSFont.plexMono(_:_:)`.

**Pourquoi** : `EditableTextField` force `isBezeled = true`, `bezelStyle = .roundedBezel` et
`NSFont.systemFont`, et un `NSViewRepresentable` ignore le `.font()` de l'environnement — le
`.font(.plexSans(13, .semibold))` de `titleField` n'avait aucun effet. Le champ ne pose pas
non plus `usesSingleLineMode`, sans quoi AppKit ignore `lineBreakMode` : c'est la cause de
« tronque sans ellipsis » dans la fiche projet en édition (écart n° 11). Les 25 autres usages
gardent le comportement actuel grâce aux valeurs par défaut.

- [ ] **Étape 1 : écrire les tests qui échouent**

`Tests/RefonteFinitionsTests.swift` (premier bloc ; les tâches 3 à 8 y ajoutent des suites) :

```swift
import Testing
import Foundation
import SwiftUI
import AppKit
@testable import OneToOne

/// Écart (c) n° 3 de la recette des vagues 1–4 : « le titre de réunion n'est
/// pas un titre ».
@Suite("Finitions du lot 19c — champ de titre")
@MainActor
struct ChampDeTitreTests {

    @Test("le style plain ne dessine ni bezel ni bordure et prend la fonte demandée")
    func stylePlain() {
        var texte = "Réunion de cadrage"
        let champ = EditableTextField(placeholder: "Titre",
                                      text: Binding(get: { texte },
                                                    set: { texte = $0 }),
                                      style: .plain,
                                      font: .plexSans(13, .semibold))
        let vue = champ.makeNSView(context: Self.contexte(for: champ))
        #expect(vue.isBezeled == false)
        #expect(vue.isBordered == false)
        #expect(vue.drawsBackground == false)
        #expect(vue.focusRingType == .none)
        #expect(vue.font?.pointSize == 13)
    }

    @Test("le style bezelé reste le défaut, inchangé pour les 25 autres usages")
    func styleBezeleParDefaut() {
        var texte = ""
        let champ = EditableTextField(placeholder: "Clé", text: Binding(get: { texte },
                                                                       set: { texte = $0 }))
        let vue = champ.makeNSView(context: Self.contexte(for: champ))
        #expect(vue.isBezeled)
        #expect(vue.bezelStyle == .roundedBezel)
        #expect(vue.font == .systemFont(ofSize: NSFont.systemFontSize))
    }

    @Test("le champ tronque avec une ellipsis, quel que soit son style")
    func ellipsisEnFinDeLigne() {
        for style in [EditableTextField.Style.bezeled, .plain] {
            var texte = String(repeating: "libellé très long ", count: 12)
            let champ = EditableTextField(placeholder: "", text: Binding(get: { texte },
                                                                        set: { texte = $0 }),
                                          style: style)
            let vue = champ.makeNSView(context: Self.contexte(for: champ))
            #expect(vue.usesSingleLineMode, "sans usesSingleLineMode, lineBreakMode est ignoré")
            #expect(vue.lineBreakMode == .byTruncatingTail)
            #expect(vue.cell?.truncatesLastVisibleLine == true)
        }
    }

    @Test("la barre du haut monte son titre en Plex Sans, sans bezel")
    func titreDeLaBarreEnPlain() {
        let source = RefonteSource.lire("OneToOne/Views/Meeting/MeetingTopChromeBar.swift")
        #expect(source.contains("style: .plain"))
        #expect(source.contains("font: .plexSans(13, .semibold)"))
        // Le modifieur SwiftUI qui n'avait aucun effet est parti.
        #expect(!source.contains("EditableTextField(placeholder: Self.titlePlaceholder(for: meeting), text: $meeting.title)\n            .font("))
    }

    @Test("NSFont.plexSans résout la même fonte que Font.plexSans")
    func nsFontPlex() {
        let fonte = NSFont.plexSans(13, .semibold)
        #expect(fonte.pointSize == 13)
        if PlexFont.isInstalled(PlexWeight.semibold.sansPostScriptName) {
            #expect(fonte.fontName == PlexWeight.semibold.sansPostScriptName)
        }
    }

    private static func contexte<V: NSViewRepresentable>(for vue: V) -> V.Context {
        // `makeNSView` n'utilise que `context.coordinator` pour le délégué :
        // un contexte fabriqué par SwiftUI n'est pas nécessaire ici. On passe
        // par la fabrique publique de la représentation.
        fatalError("remplacé à l'étape 3 par l'assemblage réel")
    }
}

/// Lecture des sources du dépôt depuis un test, motif déjà employé par
/// `Tests/ReviewStateTests.swift`.
enum RefonteSource {
    static var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func lire(_ chemin: String) -> String {
        (try? String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8)) ?? ""
    }
}
```

> **Note d'exécution :** SwiftUI n'expose pas de fabrique publique de
> `NSViewRepresentableContext`. À l'étape 3, extraire la configuration du `NSTextField` dans
> une **fonction pure** `EditableTextField.configure(_ field: NSTextField)` que `makeNSView`
> appelle, et faire porter les tests sur `configure` — ce qui supprime le besoin de contexte
> et respecte « toute règle métier est une fonction pure testée avant sa vue » (programme §7).
> Remplacer alors `champ.makeNSView(context:)` par :
> ```swift
> let vue = NSTextField()
> champ.configure(vue)
> ```
> et supprimer l'aide `contexte(for:)`.

- [ ] **Étape 2 : lancer, constater l'échec**

`swift test --filter ChampDeTitreTests` → échec de compilation (paramètres `style` / `font`,
`configure`, `NSFont.plexSans` absents).

- [ ] **Étape 3 : implémenter**

`One2OneTypography.swift`, après l'extension `Font` :

```swift
extension NSFont {
    /// Pendant AppKit de `Font.plexSans`, pour les `NSViewRepresentable` —
    /// un `NSTextField` ne lit pas le `.font()` de l'environnement SwiftUI.
    static func plexSans(_ size: CGFloat, _ weight: PlexWeight = .regular) -> NSFont {
        PlexFont.isInstalled(weight.sansPostScriptName)
            ? (NSFont(name: weight.sansPostScriptName, size: size)
               ?? .systemFont(ofSize: size, weight: weight.appKitWeight))
            : .systemFont(ofSize: size, weight: weight.appKitWeight)
    }

    static func plexMono(_ size: CGFloat, _ weight: PlexWeight = .medium) -> NSFont {
        PlexFont.isInstalled(weight.monoPostScriptName)
            ? (NSFont(name: weight.monoPostScriptName, size: size)
               ?? .monospacedSystemFont(ofSize: size, weight: weight.appKitWeight))
            : .monospacedSystemFont(ofSize: size, weight: weight.appKitWeight)
    }
}
```

Ajouter à `PlexWeight` la traduction AppKit qui manque (à côté de `systemWeight`) :

```swift
    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        }
    }
```

> Vérifier les cas réels de `PlexWeight` avant d'écrire ce `switch`
> (`One2OneTypography.swift:6-42`) et n'employer que ceux qui existent.

`EditableTextField.swift` :

```swift
struct EditableTextField: NSViewRepresentable {
    /// Apparence du champ. `bezeled` est le champ historique des écrans de
    /// réglages ; `plain` est le texte plat qu'un titre exige (spec §2.1,
    /// écart (c) n° 3 de la recette des vagues 1–4).
    enum Style: Sendable { case bezeled, plain }

    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var style: Style = .bezeled
    /// Fonte imposée au champ. `nil` = fonte système, comme avant.
    var font: NSFont? = nil

    /// Toute la configuration, hors liaison au délégué : une fonction pure sur
    /// un `NSTextField`, donc testable sans contexte SwiftUI.
    func configure(_ field: NSTextField) {
        field.placeholderString = placeholder
        field.stringValue = text
        switch style {
        case .bezeled:
            field.isBordered = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.drawsBackground = true
        case .plain:
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.focusRingType = .none
        }
        field.font = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        // `lineBreakMode` seul ne suffit pas : sans `usesSingleLineMode`,
        // AppKit l'ignore et coupe le texte sans ellipsis (écart (c) n° 11).
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? NSSecureTextField() : NSTextField()
        configure(field)
        field.delegate = context.coordinator
        return field
    }
    // `updateNSView`, `makeCoordinator`, `Coordinator` : inchangés.
}
```

`MeetingTopChromeBar.swift:531-535` :

```swift
    private var titleField: some View {
        // Écart (c) n° 3 : un titre, pas un champ. `EditableTextField` en
        // style `plain` porte la fonte de la spec §2.1 (Plex Sans 600, 13 pt)
        // et reste éditable en place, sans bezel permanent.
        EditableTextField(placeholder: Self.titlePlaceholder(for: meeting),
                          text: $meeting.title,
                          style: .plain,
                          font: .plexSans(13, .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
    }
```

- [ ] **Étape 4 : `swift build` puis les tests**

`swift test --filter ChampDeTitreTests` → vert. Puis `swift test --filter AISettings` et
`swift test --filter Markdown` pour confirmer que les 25 autres usages n'ont pas bougé.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/EditableTextField.swift \
        OneToOne/Views/DesignSystem/One2OneTypography.swift \
        OneToOne/Views/Meeting/MeetingTopChromeBar.swift \
        Tests/RefonteFinitionsTests.swift
git commit -m "fix(refonte): titre de réunion en texte plat Plex, ellipsis fiable (lot 19c)"
```

---

## Tâche 3 : la palette des niveaux de risque (écart (c) n° 6)

**Fichiers**
- Créer : `OneToOne/Views/DesignSystem/RiskLevelTint.swift`
- Modifier : `OneToOne/Views/Meeting/Spaces/MeetingKPIBand.swift:143-154`
- Modifier : `OneToOne/Views/Project/ProjectCardPanel.swift:64-71`
- Modifier : `Tests/RefonteFinitionsTests.swift`

**Interfaces**
- Produit : `extension MeetingKPI.Level { var teinte: Color }` — `report` pour
  `.critique` et `.eleve`, `warn` pour `.modere`, `ink4` (neutre) pour `.faible`.
- `MeetingKPIBand.teinte(_:)` et `ProjectCardPanel.color(for:)` deviennent des façades d'une
  ligne, pour ne pas casser leurs appelants (`ActionsRailRisks.swift:57`,
  `ReviewSidebarNav.swift:415`, `ProjectCardPanel.swift:700`, `:731`).

**Pourquoi** : deux tables divergentes. `MeetingKPIBand.teinte` donnait `warn` à `.eleve`,
`action` (bleu) à `.modere` et `ink4` à `.faible` ; `ProjectCardPanel.color(for:)` donnait
déjà la palette de la maquette. Le bandeau, le bloc `ALERTES` et la nav Relire héritaient donc
du bleu. La maquette n'emploie que rouge et orange, plus un neutre pour le faible.

- [ ] **Étape 1 : écrire le test qui échoue** — ajouter à `Tests/RefonteFinitionsTests.swift` :

```swift
/// Écart (c) n° 6 : « les niveaux de risque bas sortent en bleu et gris ».
@Suite("Finitions du lot 19c — teinte d'un niveau de risque")
struct TeinteDesRisquesTests {

    @Test("critique et élevé sont report, modéré est warn, faible est neutre")
    func palette() {
        #expect(MeetingKPI.Level.critique.teinte == One2OneToken.report)
        #expect(MeetingKPI.Level.eleve.teinte == One2OneToken.report)
        #expect(MeetingKPI.Level.modere.teinte == One2OneToken.warn)
        #expect(MeetingKPI.Level.faible.teinte == One2OneToken.ink4)
    }

    @Test("aucun niveau ne sort en bleu : accent/action est la couleur des actions")
    func aucunBleu() {
        for niveau in [MeetingKPI.Level.critique, .eleve, .modere, .faible] {
            #expect(niveau.teinte != One2OneToken.action)
        }
    }

    @Test("les quatre écrans lisent la même table")
    func uneSeuleTable() {
        for niveau in [MeetingKPI.Level.critique, .eleve, .modere, .faible] {
            #expect(MeetingKPIBand.teinte(niveau) == niveau.teinte)
            #expect(ActionsRailRisks.teinte(niveau) == niveau.teinte)
            #expect(ProjectCardPanel.color(for: niveau) == niveau.teinte)
        }
    }
}
```

- [ ] **Étape 2 : lancer** → `swift test --filter TeinteDesRisquesTests`, échec
(`teinte` inconnue sur `Level`).

- [ ] **Étape 3 : implémenter** — `OneToOne/Views/DesignSystem/RiskLevelTint.swift` :

```swift
import SwiftUI

extension MeetingKPI.Level {
    /// Teinte canonique d'un niveau de risque, pour les quatre écrans qui en
    /// dessinent un point : bandeau d'indicateurs, onglet Risques du rail,
    /// fiche projet, nav du mode Relire.
    ///
    /// La maquette n'emploie que deux accents : `report` pour ce qui alerte,
    /// `warn` pour ce qui surveille. Le faible n'est pas un accent, c'est un
    /// neutre — `ink/4`. Le bleu `action` est réservé aux actions ; l'employer
    /// pour un risque modéré, comme le faisait `MeetingKPIBand.teinte`, faisait
    /// lire un risque comme une action (écart (c) n° 6, recette des vagues 1–4).
    var teinte: Color {
        switch self {
        case .critique, .eleve: return One2OneToken.report
        case .modere:           return One2OneToken.warn
        case .faible:           return One2OneToken.ink4
        }
    }
}
```

Puis remplacer les deux tables par des façades :

```swift
    // MeetingKPIBand
    /// Teinte d'un point de risque. Table unique : `MeetingKPI.Level.teinte`.
    static func teinte(_ niveau: MeetingKPI.Level) -> Color { niveau.teinte }
```

```swift
    // ProjectCardPanel
    static func color(for level: MeetingKPI.Level) -> Color { level.teinte }
```

- [ ] **Étape 4 : lancer** `swift test --filter TeinteDesRisquesTests` puis
`swift test --filter KPI` et `swift test --filter ProjectCard` (une assertion existante peut
attendre l'ancienne teinte : la corriger en citant l'écart n° 6 dans le commentaire du test).

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/DesignSystem/RiskLevelTint.swift \
        OneToOne/Views/Meeting/Spaces/MeetingKPIBand.swift \
        OneToOne/Views/Project/ProjectCardPanel.swift \
        Tests/RefonteFinitionsTests.swift
git commit -m "fix(refonte): une seule palette pour les niveaux de risque (lot 19c)"
```

---

## Tâche 4 : bascule `Speakers`, `Citer`/`Envoyer`, `STATUT`, pied de fiche

**Fichiers**
- Modifier : `OneToOne/Views/MeetingView.swift:647-648` (**retrait** d'une condition)
- Modifier : `OneToOne/Views/Meeting/Resources/ResourceTile.swift:90-107`
- Modifier : `OneToOne/Views/Project/ProjectCardPanel.swift:258-296` et `:139-141`
- Modifier : `Tests/RefonteFinitionsTests.swift`

**Interfaces** — aucune signature nouvelle ; quatre corrections de vue.

**Ce qui change, et pourquoi**

1. **`Speakers` (écart n° 5)** : `showsSpeakerToggle: settings.transcriptionMode ==
   .diarizeFirst && !meeting.transcriptSegments.isEmpty`. La seconde condition masque la
   bascule tant qu'aucun segment n'est diarisé — donc toujours, sur le jeu de recette. La
   spec §2.4 la rattache au **mode de transcription**, pas au contenu. Retirer
   `&& !meeting.transcriptSegments.isEmpty` (un retrait : `MeetingView.swift` le permet).
2. **`Citer` / `Envoyer` (écart n° 8)** : la chaîne `if / else if` de `ResourceTile.boutons`
   réserve les deux boutons à `isPresented`. §4.1 les liste par vignette. Les offrir sur toute
   pièce **citable** — le menu contextuel emploie déjà le bon prédicat,
   `item.isPinnable && !item.isOrphan` (`ResourceTile.swift:143`).
3. **Point de statut (écart n° 9)** : en édition, le point est un `Circle()` dans le `label:`
   d'un `Menu` en `.borderlessButton` — AppKit ne rend d'un label de menu que du texte et des
   `Image`. Remplacer par `Image(systemName: "circle.fill")` teinté, ce que le rendu accepte.
4. **Pied de fiche (écart n° 10)** : §4.3 ne conditionne pas la mention de visibilité.
   Scinder : la mention est toujours rendue, les boutons `Annuler` / `Enregistrer` seulement
   en édition.

- [ ] **Étape 1 : écrire les tests qui échouent** — ajouter à `Tests/RefonteFinitionsTests.swift` :

```swift
/// Écarts (c) n° 5, 8, 9 et 10 de la recette des vagues 1–4.
@Suite("Finitions du lot 19c — quatre écarts de vue")
struct EcartsDeVueTests {

    @Test("la bascule Speakers ne dépend que du mode de transcription (n° 5)")
    func basculeSpeakers() {
        let source = RefonteSource.lire("OneToOne/Views/MeetingView.swift")
        #expect(source.contains("showsSpeakerToggle: settings.transcriptionMode == .diarizeFirst"))
        #expect(!source.contains("&& !meeting.transcriptSegments.isEmpty"),
                "la bascule ne doit plus attendre un segment diarisé")
    }

    @Test("Citer et Envoyer sont offerts par vignette, pas seulement à l'écran (n° 8)")
    func citerEtEnvoyerParVignette() {
        let source = RefonteSource.lire("OneToOne/Views/Meeting/Resources/ResourceTile.swift")
        // Les deux boutons vivent désormais hors de la branche `isPresented`.
        #expect(source.contains("if item.isPinnable && !item.isOrphan {"))
        let boutons = source.components(separatedBy: "bouton(\"Citer\"").count - 1
        #expect(boutons == 1, "un seul site de déclaration pour Citer")
    }

    @Test("le point de statut est une Image, rendue dans un label de menu (n° 9)")
    func pointDeStatutEnEdition() {
        let source = RefonteSource.lire("OneToOne/Views/Project/ProjectCardPanel.swift")
        #expect(source.contains("Image(systemName: \"circle.fill\")"),
                "un Circle() dans un label de Menu n'est pas rendu par AppKit")
    }

    @Test("la mention de visibilité du pied n'est plus conditionnée à l'édition (n° 10)")
    func mentionDeVisibiliteToujoursVisible() {
        let source = RefonteSource.lire("OneToOne/Views/Project/ProjectCardPanel.swift")
        #expect(source.contains("footerNotice"))
        #expect(source.contains("private var footerActions"),
                "les boutons sont séparés de la mention")
        #expect(!source.contains("if isEditing {\n                Divider().overlay(One2OneToken.hair)\n                footer\n            }"),
                "le pied entier ne doit plus dépendre de l'édition")
    }
}
```

- [ ] **Étape 2 : lancer** `swift test --filter EcartsDeVueTests` → quatre échecs.

- [ ] **Étape 3 : `Speakers`** — `MeetingView.swift`, retirer la seconde condition :

```swift
                // Spec §2.4 : la bascule suit le **mode de transcription**,
                // pas la présence de segments — sinon elle n'apparaît jamais
                // avant la fin d'une diarisation (écart (c) n° 5).
                showsSpeakerToggle: settings.transcriptionMode == .diarizeFirst,
```

- [ ] **Étape 4 : `Citer` / `Envoyer`** — `ResourceTile.boutons` :

```swift
    @ViewBuilder
    private var boutons: some View {
        HStack(spacing: 5) {
            if item.nature == .lien {
                bouton("Ouvrir", plein: false) { actions.open(item) }
            } else if item.isOrphan {
                bouton("Relier…", plein: false) { actions.relink(item) }
            } else {
                if isPresented {
                    bouton("À l'écran", plein: true) { }
                } else if item.isPresentable {
                    bouton("Présenter", plein: false) { actions.present(item) }
                }
                // Spec §4.1 : `Citer` et `Envoyer` sont listés **par
                // vignette**, pas réservés à la pièce présentée (écart (c)
                // n° 8). Même prédicat que le menu contextuel.
                if item.isPinnable && !item.isOrphan {
                    bouton("Citer", plein: false) { actions.cite(item) }
                    bouton("Envoyer", plein: false) { actions.send(item) }
                }
            }
        }
        .padding(.top, 1)
    }
```

Retirer alors les deux entrées devenues redondantes du menu contextuel
(`ResourceTile.swift:143-144`) **seulement si** la vignette les offre dans tous les cas où le
menu les offrait ; sinon les laisser (un clic droit reste plus rapide qu'une lecture de
vignette). Vérifier le prédicat avant de décider.

- [ ] **Étape 5 : point de statut** — `ProjectCardPanel.statusControl`, branche `isEditing` :

```swift
                HStack(spacing: 6) {
                    // Un `Circle()` dans le `label:` d'un `Menu` n'est pas
                    // rendu par AppKit : seuls le texte et les `Image` le sont
                    // (écart (c) n° 9). Le point survit donc en symbole.
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Self.color(for: draft.status))
                    Text(draft.status.label)
```

- [ ] **Étape 6 : pied de fiche** — scinder `footer` en `footerNoticeRow` (la mention) et
`footerActions` (les deux boutons), puis :

```swift
            // Spec §4.3 : la mention de visibilité fait partie de la fiche,
            // pas de son mode édition (écart (c) n° 10). Seuls les boutons
            // dépendent de l'édition.
            Divider().overlay(One2OneToken.hair)
            VStack(alignment: .leading, spacing: 8) {
                footerNoticeRow
                if isEditing { footerActions }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
```

En reprenant les paddings que `footer` portait, pour ne pas déplacer la mise en page en
édition.

- [ ] **Étape 7 : `swift build`, tests ciblés**

`swift test --filter EcartsDeVueTests`, puis `swift test --filter Resource`,
`swift test --filter ProjectCard`, `swift test --filter Speaker`.

- [ ] **Étape 8 : commit**

```bash
git add OneToOne/Views/MeetingView.swift \
        OneToOne/Views/Meeting/Resources/ResourceTile.swift \
        OneToOne/Views/Project/ProjectCardPanel.swift \
        Tests/RefonteFinitionsTests.swift
git commit -m "fix(refonte): bascule Speakers, Citer/Envoyer, point de statut, pied de fiche (lot 19c)"
```

---

## Tâche 5 : ellipsis sur les titres et noms qui tronquaient

**Fichiers** — ajouter `.lineLimit(1)` et `.truncationMode(.tail)` dans, exactement :
- `OneToOne/Views/Meeting/Spaces/MeetingSpacesBar.swift:125` (onglet d'espace)
- `OneToOne/Views/Meeting/Spaces/Review/ReviewSidebarNav.swift:342`, `:418` (nav 190 px —
  les deux libellés cités par la recette)
- `OneToOne/Views/Meeting/Spaces/Rail/ActionsRail.swift:92` (onglets du rail 330 px)
- `OneToOne/Views/Meeting/Spaces/Transcript/TranscriptSpeakerTools.swift:148`, `:167`, `:310`
- `OneToOne/Views/Meeting/OneOnOne/Manager/CommitmentsRail.swift:57`
- `OneToOne/Views/Meeting/Capture/CapturesStrip.swift:212`, `:217`, `:225`
- `OneToOne/Views/Meeting/Spaces/Notes/TimedNotesColumn.swift:195`
- `OneToOne/Views/Meeting/ManageParticipantsSheet.swift:64`, `:136`, `:151`
- `OneToOne/Views/Meeting/MeetingTagEditor.swift:55`, `:162`
- Modifier : `Tests/RefonteFinitionsTests.swift`

**Hors périmètre, explicitement** : `Views/Meeting/Session/**` (correctif #42),
`Views/Meeting/Workshop/**` (lot 18), `OneOnOne/CollaboratorPrep/**` (lot 14) — quatre
candidats y attendent leur lot. Les cellules de la fiche projet sont traitées par la tâche 2
(cause racine `usesSingleLineMode`).

- [ ] **Étape 1 : écrire le test qui échoue**

```swift
/// Écart (a) « troncatures sans ellipsis » : un libellé qui se coupe doit dire
/// qu'il est coupé (spec §1.2). Le test lit les sources : c'est le seul moyen
/// de vérifier un modifieur de mise en page sans monter la vue.
@Suite("Finitions du lot 19c — ellipsis")
struct EllipsisTests {

    /// Les fichiers dont chaque `Text` de libellé contraint porte une ellipsis.
    private static let fichiers = [
        "OneToOne/Views/Meeting/Spaces/MeetingSpacesBar.swift",
        "OneToOne/Views/Meeting/Spaces/Review/ReviewSidebarNav.swift",
        "OneToOne/Views/Meeting/Spaces/Rail/ActionsRail.swift",
        "OneToOne/Views/Meeting/Spaces/Transcript/TranscriptSpeakerTools.swift",
        "OneToOne/Views/Meeting/OneOnOne/Manager/CommitmentsRail.swift",
        "OneToOne/Views/Meeting/Capture/CapturesStrip.swift",
        "OneToOne/Views/Meeting/Spaces/Notes/TimedNotesColumn.swift",
        "OneToOne/Views/Meeting/ManageParticipantsSheet.swift",
        "OneToOne/Views/Meeting/MeetingTagEditor.swift",
    ]

    @Test("chaque vue corrigée pose truncationMode(.tail) autant de fois que lineLimit(1)")
    func ellipsisPartoutOuUneLigne() {
        for chemin in Self.fichiers {
            let source = RefonteSource.lire(chemin)
            #expect(!source.isEmpty, "source introuvable : \(chemin)")
            let uneLigne = source.components(separatedBy: ".lineLimit(1)").count - 1
            let ellipsis = source.components(separatedBy: ".truncationMode(.tail)").count - 1
            #expect(uneLigne > 0, "\(chemin) : aucun lineLimit(1)")
            #expect(ellipsis >= uneLigne,
                    "\(chemin) : \(uneLigne) lineLimit(1) pour \(ellipsis) truncationMode(.tail)")
        }
    }
}
```

- [ ] **Étape 2 : lancer** → échec sur les fichiers sans `truncationMode`.

- [ ] **Étape 3 : appliquer**, ligne par ligne. Forme :

```swift
                Text(projet.name)
                    .font(.plexSans(11.5, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
```

Sur `ReviewSidebarNav.swift:342` et `:418`, retirer le `fixedSize(horizontal: false,
vertical: true)` s'il est présent : il autorise le retour à la ligne infini que la nav de
190 px ne peut pas absorber.

- [ ] **Étape 4 : lancer** `swift test --filter EllipsisTests`, puis
`swift test --filter Review` et `swift test --filter SpacesBar`.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/Meeting Tests/RefonteFinitionsTests.swift
git commit -m "fix(refonte): ellipsis sur les libellés contraints des vues de réunion (lot 19c)"
```

---

## Tâche 6 : retrait de `newTaskPomodoros`

**Fichiers**
- Modifier : `OneToOne/Views/Meeting/MeetingScreenModel.swift:111` (déclaration) et `:278`
  (remise à zéro dans `resetActionDraft()`), plus le commentaire de `:112-115` qui le cite
- Modifier : `Tests/MeetingScreenModelTests.swift:102`, `:109`, `:137`, `:147`, `:217`, `:224`

**Établi** : aucune vue ne lit ni n'écrit `newTaskPomodoros` — zéro occurrence hors
`MeetingScreenModel` et ses tests. Le lot 19a l'avait daté « à retirer au 19b ». Son
remplaçant est `newTaskEffortMinutes` (`:116`).

- [ ] **Étape 1 : retirer les assertions**, dans `Tests/MeetingScreenModelTests.swift`, aux six
lignes citées : supprimer les `#expect` / `XCTAssert` portant sur `newTaskPomodoros` sans
toucher aux autres assertions du même test (elles vérifient le reste du brouillon).

- [ ] **Étape 2 : lancer** `swift test --filter MeetingScreenModelTests` → vert (le champ
existe encore, il n'est plus vérifié).

- [ ] **Étape 3 : retirer le champ** — la déclaration `:111`, la remise à zéro `:278`, et
reformuler le commentaire de `newTaskEffortMinutes`, qui ne peut plus opposer le champ à
« celui que l'ancien panneau continue d'employer » :

```swift
    /// Charge par défaut du composeur du rail, en minutes (`30min` de la
    /// capture 1a) : le champ du modèle cible, `ActionTask.effortMinutes`.
    var newTaskEffortMinutes: Int? = 30
```

- [ ] **Étape 4 : lancer** `swift build` puis `swift test --filter MeetingScreenModel` et
`swift test --filter ActionComposer`.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Views/Meeting/MeetingScreenModel.swift Tests/MeetingScreenModelTests.swift
git commit -m "refactor(refonte): retirer newTaskPomodoros, sans lecteur depuis le lot 3 (lot 19c)"
```

---

## Tâche 7 : `Scripts/recette-app.sh` ne peut plus empaqueter un binaire périmé

**Fichiers** — Modifier : `Scripts/recette-app.sh`

**Pourquoi (écart (c) n° 12)** : le premier bundle de la recette des vagues 1–4 venait d'un
`.build/release/OneToOne` antérieur au build en cours ; il manquait trois lots, et deux heures
d'observations ont été fausses. Le script doit refuser, ou au moins le dire.

**Contrat**
1. Après la copie, afficher `md5`, taille et `mtime` du binaire **source** et du binaire
   **empaqueté**, et vérifier que les deux `md5` sont identiques (sinon échec : la copie a
   échoué en silence).
2. Refuser si un `.swift` sous `OneToOne/` est plus récent que le binaire, sauf `--force`.
3. `CFBundleIdentifier` = `<identifiant actuel>.recette` et `CFBundleName` =
   `OneToOne (recette)` dans l'`Info.plist` du bundle produit, pour qu'aucun outil ne puisse
   confondre l'instance de recette avec celle de l'utilisateur (écart (c) n° 7).

- [ ] **Étape 1 : lire l'identifiant actuel**

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist
```

Noter la valeur ; le script la lira au lieu de la coder en dur.

- [ ] **Étape 2 : garde de fraîcheur**, juste après le contrôle `-x "${BINARY}"` :

```bash
# ----------------------------------------------------------------------
# Fraîcheur du binaire. Écart (c) n° 12 de la recette des vagues 1-4 : un
# bundle empaqueté depuis un `.build/release/OneToOne` antérieur au build
# en cours a produit deux heures d'observations fausses (mode Relire rendu
# comme au lot 1, ressources absentes) avant que la comparaison des chaînes
# du binaire ne le révèle. Le script refuse maintenant de le faire en
# silence.
# ----------------------------------------------------------------------
PLUS_RECENT="$(find OneToOne -name '*.swift' -newer "${BINARY}" 2>/dev/null | head -1)"
if [ -n "${PLUS_RECENT}" ]; then
    NB="$(find OneToOne -name '*.swift' -newer "${BINARY}" 2>/dev/null | wc -l | tr -d ' ')"
    if [ -n "${FORCE}" ]; then
        echo "⚠️  Binaire périmé (${NB} source(s) plus récente(s), dont ${PLUS_RECENT})"
        echo "    — empaquetage forcé par --force."
    else
        echo "✗ Binaire périmé : ${NB} fichier(s) source plus récent(s) que"
        echo "  ${BINARY}"
        echo "  Le premier : ${PLUS_RECENT}"
        echo ""
        echo "  Reconstruis d'abord :"
        echo "      swift build$( [ "${CONFIGURATION}" = release ] && echo ' -c release' )"
        echo "  ou passe --force si tu empaquettes sciemment un binaire ancien."
        exit 1
    fi
fi
```

Ajouter `--force` à la boucle d'arguments (`FORCE=""` en tête, `--force) FORCE=1; shift ;;`)
et à l'en-tête d'usage.

- [ ] **Étape 3 : empreinte et identité du bundle**, après `cp "${BINARY}" …` :

```bash
MD5_SOURCE="$(md5 -q "${BINARY}")"
MD5_BUNDLE="$(md5 -q "${APP}/Contents/MacOS/${APP_NAME}")"
if [ "${MD5_SOURCE}" != "${MD5_BUNDLE}" ]; then
    echo "✗ La copie du binaire ne correspond pas à la source (md5 différents)."
    exit 1
fi
echo "→ Binaire : md5 ${MD5_SOURCE}"
echo "            $(du -h "${BINARY}" | cut -f1), modifié le $(date -r "${BINARY}" '+%Y-%m-%d %H:%M:%S')"
```

Puis, après la copie de l'`Info.plist` :

```bash
# Identité distincte du bundle de recette (écart (c) n° 7) : deux instances
# qui partagent le même CFBundleIdentifier se confondent dans les outils
# système, et c'est ainsi qu'une fenêtre de production a été redimensionnée
# pendant la recette des vagues 1-4.
BASE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist" 2>/dev/null)"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BASE_ID}.recette" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName OneToOne (recette)" "${APP}/Contents/Info.plist" \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleName string OneToOne (recette)" "${APP}/Contents/Info.plist"
echo "→ Identité de recette : ${BASE_ID}.recette"
```

- [ ] **Étape 4 : vérification manuelle**, à documenter dans l'en-tête du script (SwiftPM
n'exécute pas de test shell — il n'y a pas de cible pour cela dans `Package.swift`) :

```
# Vérification (manuelle, une minute — aucun test SwiftPM ne couvre un script)
#   1. swift build -c release && Scripts/recette-app.sh /tmp/rec
#      → « md5 … », « Identité de recette : ….recette », « ✓ … »
#   2. touch OneToOne/OneToOneApp.swift && Scripts/recette-app.sh /tmp/rec
#      → « ✗ Binaire périmé : 1 fichier(s) source plus récent(s) » et code 1
#   3. Scripts/recette-app.sh /tmp/rec --force
#      → « ⚠️  Binaire périmé … forcé par --force » et code 0
#   4. /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
#        /tmp/rec/OneToOne.app/Contents/Info.plist   → …recette
```

- [ ] **Étape 5 : `bash -n`** (syntaxe) et relecture

```bash
bash -n Scripts/recette-app.sh && echo "syntaxe ok"
```

- [ ] **Étape 6 : commit**

```bash
git add Scripts/recette-app.sh
git commit -m "fix(recette): refuser un binaire périmé, isoler le bundle de recette (lot 19c)"
```

---

## Tâche 8 : `Scripts/recette-run.sh` — verrou d'écran, Teams, codes d'écran

**Fichiers** — Modifier : `Scripts/recette-run.sh`

**Pourquoi** : le script ne détecte ni le verrou d'écran (qui rend toute capture noire) ni une
réunion Teams en cours (une recette qui redimensionne des fenêtres pendant un appel est
inacceptable), et sa liste de codes d'écran est **recopiée** de `RecetteScreen.swift` — elle
en a déjà divergé (9 codes contre 10 dans la table, `5b` manquant).

**Contrat**
1. `SCREENS` est **dérivée** de `OneToOne/Services/Debug/RecetteScreen.swift` (repli codé en
   dur si le fichier est introuvable). La liste ne peut donc plus divergerv.
2. Verrou d'écran : `ioreg -n Root -d1 -r | grep -q 'CGSSessionScreenIsLocked"=Yes'` —
   **sans espaces** autour du `=`, c'est la forme réellement rendue par `ioreg` (les
   `grep CGSSession` des STATUS antérieurs affichaient la forme espacée d'un autre outil).
   Refus, avec `--ignore-lock` pour passer outre.
3. Teams : refus si une fenêtre du processus `MSTeams` porte un titre de réunion ou d'appel.
   Énumération par `CGWindowListCopyWindowInfo` depuis un court script Python
   (`pyobjc`/`Quartz` est présent sur macOS) — **jamais AppleScript par nom de processus**,
   qui résout mal le processus quand deux instances partagent le `CFBundleIdentifier`
   (écart (c) n° 7).

- [ ] **Étape 1 : codes d'écran dérivés** — remplacer la ligne `SCREENS="1a 1b …"` par :

```bash
# Les codes acceptés par `RecetteScreen`, **lus dans la table** : recopier la
# liste l'a déjà fait diverger (le code `5b` du lot 13 manquait ici alors que
# `RecetteScreen.swift` le déclarait).
RECETTE_SCREEN_SWIFT="OneToOne/Services/Debug/RecetteScreen.swift"
if [ -f "${RECETTE_SCREEN_SWIFT}" ]; then
    SCREENS="$(sed -n 's/^ *case [a-zA-Z]* = "\([0-9a-z]*\)"/\1/p' "${RECETTE_SCREEN_SWIFT}" | tr '\n' ' ')"
fi
if [ -z "${SCREENS}" ]; then
    # Repli : le script s'utilise aussi hors du dépôt, à côté du bundle seul.
    SCREENS="1a 1b 1c 2a 2b 3a 3b 4a 5a 5b 6a 6b"
fi
```

- [ ] **Étape 2 : garde du verrou d'écran**, avant le lancement :

```bash
# ----------------------------------------------------------------------
# Verrou d'écran. Une capture sur session verrouillée est noire, et le
# redimensionnement par l'API Accessibility échoue sans le dire : cinq
# recettes de la refonte ont été perdues ainsi. La clé est rendue **sans
# espaces** autour du `=` par `ioreg -r` ; l'ancienne consigne cherchait
# `"CGSSessionScreenIsLocked" = Yes`, qui ne correspond jamais.
# ----------------------------------------------------------------------
if [ -z "${IGNORE_LOCK}" ] \
   && ioreg -n Root -d1 -r | grep -q 'CGSSessionScreenIsLocked"=Yes'; then
    echo "✗ Session graphique verrouillée : une capture serait noire."
    echo "  Déverrouille l'écran, puis relance. (--ignore-lock pour forcer.)"
    exit 1
fi
```

Ajouter `IGNORE_LOCK=""` et `--ignore-lock) IGNORE_LOCK=1; shift ;;`.

- [ ] **Étape 3 : garde Teams**, juste après :

```bash
# ----------------------------------------------------------------------
# Réunion Teams en cours. La recette redimensionne des fenêtres et prend des
# captures d'écran : le faire pendant un appel est exclu. On lit les titres
# des fenêtres du processus `MSTeams` par `CGWindowListCopyWindowInfo`, et
# **jamais** par AppleScript : `first application process whose unix id is …`
# résout mal le processus quand deux instances partagent le
# `CFBundleIdentifier`, et c'est ce qui a redimensionné une fenêtre de
# production le 7 septembre 2026 (écart (c) n° 7).
# ----------------------------------------------------------------------
titres_teams() {
    /usr/bin/python3 - <<'PY' 2>/dev/null
try:
    from Quartz import CGWindowListCopyWindowInfo, kCGWindowListOptionOnScreenOnly, kCGNullWindowID
except ImportError:
    raise SystemExit(0)
for f in CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID) or []:
    if (f.get("kCGWindowOwnerName") or "").replace(" ", "") in ("MSTeams", "MicrosoftTeams"):
        titre = f.get("kCGWindowName") or ""
        if titre:
            print(titre)
PY
}

if [ -z "${IGNORE_TEAMS}" ]; then
    EN_REUNION="$(titres_teams | grep -iE 'réunion|reunion|meeting|appel|call|en cours' | head -1)"
    if [ -n "${EN_REUNION}" ]; then
        echo "✗ Teams semble en réunion ou en appel : « ${EN_REUNION} »"
        echo "  La recette redimensionne des fenêtres et capture l'écran."
        echo "  Attends la fin de l'appel. (--ignore-teams pour forcer.)"
        exit 1
    fi
fi
```

Ajouter `IGNORE_TEAMS=""` et `--ignore-teams) IGNORE_TEAMS=1; shift ;;`.

> Le filtre est volontairement littéral : le 7 septembre, la seule fenêtre `MSTeams` portait
> « Calendar | APRIL | … », qui ne correspond à aucun de ces mots — donc pas de faux positif
> observé sur le poste. Si un faux positif apparaît, `--ignore-teams` débloque et le motif
> est à resserrer, pas à supprimer.

- [ ] **Étape 4 : en-tête d'usage à jour** — remplacer le tableau des codes par les douze,
et documenter les deux nouveaux drapeaux et la vérification manuelle :

```
#     1a  cockpit de réunion (En séance)        1c  poste de pilotage (Relire)
#     1b  espaces et indicateurs (En séance)    2a  1:1 mené, En séance
#     3a  tiroir Ressources (En séance)         2b  1:1 mené, Préparer
#     3b  fiche projet en panneau               4a  sélecteur de capture
#     5a  1:1 subi, En séance                   5b  1:1 subi, Préparer
#     6a  atelier, planche plein cadre          6b  atelier, planche de séance
#
#   La liste fait foi dans `OneToOne/Services/Debug/RecetteScreen.swift` : ce
#   script l'y lit, il ne la recopie pas.
#
#   --ignore-lock    lance malgré une session verrouillée (captures noires)
#   --ignore-teams   lance malgré une réunion Teams détectée
#
# Vérification (manuelle — aucun test SwiftPM n'exécute un script shell)
#   1. Scripts/recette-run.sh --help            → 12 codes listés
#   2. ioreg -n Root -d1 -r | grep -c 'CGSSessionScreenIsLocked"=Yes'
#      → 1 écran verrouillé, 0 déverrouillé ; le script doit refuser dans le
#        premier cas et passer dans le second
#   3. Scripts/recette-run.sh --screen 5b --app …  → accepté (table à jour)
#   4. Scripts/recette-run.sh --screen 9z --app …  → « Code d'écran inconnu »
```

- [ ] **Étape 5 : vérifier** `bash -n Scripts/recette-run.sh`, puis, sans lancer
d'application :

```bash
bash -n Scripts/recette-run.sh && echo "syntaxe ok"
sed -n 's/^ *case [a-zA-Z]* = "\([0-9a-z]*\)"/\1/p' OneToOne/Services/Debug/RecetteScreen.swift | tr '\n' ' '
ioreg -n Root -d1 -r | grep -c 'CGSSessionScreenIsLocked"=Yes' || true
```

- [ ] **Étape 6 : commit**

```bash
git add Scripts/recette-run.sh
git commit -m "fix(recette): verrou d'écran, garde Teams, codes d'écran dérivés de la table (lot 19c)"
```

---

## Tâche 9 : `BackupService` exporte les tables du lot 0B

**Fichiers**
- Modifier : `OneToOne/Services/BackupService.swift`
- Créer : `Tests/OneOnOneBackupTests.swift`

**Établi** : sur les neuf tables de `SchemaV3`, seule `Board` a un DTO (lot 16). Manquent
`MeetingNote`, `ProjectMilestone`, `ProjectContact`, `OneOnOneThread`, `Commitment`,
`OneOnOneAgendaItem`, `MoodEntry`, `OneOnOneObjective` — huit.

**Où les nicher** — aucune signature de `backup(...)` / `restore(...)` ne change :
- `MeetingNote` → `MeetingDTO.notes: [MeetingNoteDTO]?`
- `ProjectMilestone`, `ProjectContact` → `ProjectDTO.milestones`, `.contacts` (optionnels)
- `OneOnOneThread` (+ ses quatre enfants en cascade) → `CollaboratorDTO.threads: [OneOnOneThreadDTO]?`

Tous les champs ajoutés sont **optionnels** : un backup antérieur reste restaurable, comme
`BoardDTO` l'a fait au lot 16.

**Relations à recoudre à la restauration** : `Commitment.promisedInMeeting`,
`Commitment.linkedAction`, `OneOnOneAgendaItem.meeting`,
`OneOnOneAgendaItem.deferredToMeeting`, `MoodEntry.meeting`. Les porter en `UUID?`
(`stableID` de la cible) et les relier après avoir restauré les réunions, par un index
`[UUID: Meeting]` — le même motif que `MeetingDTO.projectCode`. `Commitment.linkedAction`
n'a pas d'identité stable exposée sur `ActionTask` : porter à sa place
`linkedActionTitle: String?` et relier par titre **dans la même réunion**, ou laisser nul si
l'ambiguïté est réelle ; le documenter en commentaire.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/OneOnOneBackupTests.swift`, sur le modèle de
`Tests/BoardBackupAndStorageTests.swift` (conteneur en mémoire, `CurrentSchema.models`) :

```swift
import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Point 6 des points durs (§2.4) : « chaque nouveau dossier de fichiers s'y
/// enregistre » — et chaque nouvelle table. Les neuf tables du lot 0B
/// n'étaient exportées qu'à une près (`Board`, lot 16).
@Suite("Sauvegarde : notes horodatées, fiche projet, domaine 1:1")
@MainActor
struct OneOnOneBackupTests {

    private func contexte() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    @Test("une note horodatée fait l'aller-retour, confidentialité et citation comprises")
    func noteSurvit() throws {
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let reunion = Meeting(title: "Comité de suivi",
                              date: Date(timeIntervalSince1970: 1_788_523_200), notes: "")
        source.insert(reunion)
        let note = MeetingNote(t: 252, text: "Le partenaire décide seul du chiffrage",
                               kind: .decision, visibility: .private, orderIndex: 3)
        source.insert(note)
        note.meeting = reunion
        note.sourceKindRaw = "transcript"
        note.sourceT = 250
        try source.save()

        let data = try BackupService().backup(settings: reglages, entities: [], projects: [],
                                              collaborators: [], meetings: [reunion])
        let cible = try contexte()
        try BackupService().restore(from: data, into: cible)

        let notes = try cible.fetch(FetchDescriptor<MeetingNote>())
        #expect(notes.count == 1)
        let restauree = try #require(notes.first)
        #expect(restauree.t == 252)
        #expect(restauree.kind == .decision)
        #expect(restauree.visibility == .private)
        #expect(restauree.orderIndex == 3)
        #expect(restauree.sourceT == 250)
        #expect(restauree.stableID == note.stableID)
        #expect(restauree.meeting?.title == "Comité de suivi")
    }

    @Test("jalons et interlocuteurs suivent leur projet")
    func ficheProjetSurvit() throws {
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let projet = Project(code: "P25_110", name: "Modernisation CI/CD")
        source.insert(projet)
        let jalon = ProjectMilestone(label: "Fin de conception", order: 1)
        source.insert(jalon)
        jalon.project = projet
        jalon.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        let contact = ProjectContact(name: "Claire-Amélie F.", role: "Sponsor", order: 0)
        source.insert(contact)
        contact.project = projet
        try source.save()

        let data = try BackupService().backup(settings: reglages, entities: [],
                                              projects: [projet], collaborators: [], meetings: [])
        let cible = try contexte()
        try BackupService().restore(from: data, into: cible)

        #expect(try cible.fetch(FetchDescriptor<ProjectMilestone>()).count == 1)
        let contacts = try cible.fetch(FetchDescriptor<ProjectContact>())
        #expect(contacts.first?.name == "Claire-Amélie F.")
        #expect(contacts.first?.project?.code == "P25_110")
    }

    @Test("un fil 1:1 emporte engagements, ordre du jour, humeurs et objectifs")
    func filSurvit() throws {
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let collaborateur = Collaborator(name: "Yann PENVEN")
        source.insert(collaborateur)
        let fil = OneOnOneThread(collaborator: collaborateur, myRole: .manager, cadenceDays: 14)
        source.insert(fil)
        let engagement = Commitment(text: "Chiffrer le reste à faire")
        source.insert(engagement)
        engagement.thread = fil
        engagement.visibility = .managerOnly
        engagement.deferralCount = 2
        let sujet = OneOnOneAgendaItem(text: "Charge de l'équipe")
        source.insert(sujet)
        sujet.thread = fil
        let humeur = MoodEntry(value: 4)
        source.insert(humeur)
        humeur.thread = fil
        let objectif = OneOnOneObjective(label: "Passer la certification", progress: 40)
        source.insert(objectif)
        objectif.thread = fil
        try source.save()

        let data = try BackupService().backup(settings: reglages, entities: [], projects: [],
                                              collaborators: [collaborateur], meetings: [])
        let cible = try contexte()
        try BackupService().restore(from: data, into: cible)

        let fils = try cible.fetch(FetchDescriptor<OneOnOneThread>())
        #expect(fils.count == 1)
        let restaure = try #require(fils.first)
        #expect(restaure.cadenceDays == 14)
        #expect(restaure.myRole == .manager)
        #expect(restaure.collaborator?.name == "Yann PENVEN")
        #expect(restaure.commitments.count == 1)
        #expect(restaure.commitments.first?.visibility == .managerOnly)
        #expect(restaure.commitments.first?.deferralCount == 2)
        #expect(restaure.agendaItems.count == 1)
        #expect(restaure.moodEntries.first?.value == 4)
        #expect(restaure.objectives.first?.progress == 40)
    }

    @Test("une sauvegarde antérieure au lot 19c, sans les nouvelles clés, se restaure")
    func backupAncienSeRestaure() throws {
        // Un payload minimal, sans `notes`, `milestones`, `contacts`, `threads`.
        let json = """
        {"version":1,"settings":{},"entities":[],"projects":[],"collaborators":[],"meetings":[]}
        """
        let cible = try contexte()
        // Ne doit pas jeter : tous les champs ajoutés sont optionnels.
        try BackupService().restore(from: Data(json.utf8), into: cible)
    }
}
```

> Vérifier les initialiseurs réels (`Project(code:name:)`, `Collaborator(name:)`,
> `MoodEntry(value:)`, `Commitment(text:)`, la clé `version` et la forme exacte de
> `SettingsDTO` dans `BackupService.swift:47-66`) et ajuster les appels et le payload minimal
> avant de lancer : le test doit échouer sur les **DTO manquants**, pas sur une signature.

- [ ] **Étape 2 : lancer** `swift test --filter OneOnOneBackupTests` → échec (les entités
restaurées sont absentes).

- [ ] **Étape 3 : ajouter les huit DTO**, à côté de `BoardDTO` :

```swift
    /// Note horodatée (lot 0B, spec §1.3). Les trois colonnes de citation sont
    /// plates, comme dans le modèle.
    struct MeetingNoteDTO: Codable {
        var stableID: UUID?
        var t: Double
        var text: String
        var kindRaw: String
        var visibilityRaw: String
        var authorSideRaw: String
        var sourceKindRaw: String?
        var sourceStableID: UUID?
        var sourceT: Double?
        var orderIndex: Int
        var createdAt: Date
    }

    struct ProjectMilestoneDTO: Codable {
        var stableID: UUID?
        var label: String
        var dueAt: Date?
        var stateRaw: String
        var order: Int
        var createdAt: Date
    }

    struct ProjectContactDTO: Codable {
        var stableID: UUID?
        var name: String
        var role: String
        var order: Int
        var createdAt: Date
    }

    struct CommitmentDTO: Codable {
        var stableID: UUID?
        var text: String
        var ownerSideRaw: String
        var dueAt: Date?
        var stateRaw: String
        var promisedAt: Date
        var settledAt: Date?
        var deferralCount: Int
        var visibilityRaw: String
        var blocksOther: Bool
        var linkedDecisionIndex: Int?
        /// `stableID` de la réunion où l'engagement a été pris.
        var promisedInMeetingID: UUID?
    }

    struct OneOnOneAgendaItemDTO: Codable {
        var stableID: UUID?
        var text: String
        var addedBySideRaw: String
        var order: Int
        var stateRaw: String
        var visibilityRaw: String
        var kindRaw: String
        var requestStatusRaw: String
        var requestedAt: Date?
        var remindedCount: Int
        var createdAt: Date
        var meetingID: UUID?
        var deferredToMeetingID: UUID?
    }

    struct MoodEntryDTO: Codable {
        var stableID: UUID?
        var value: Int
        var recordedAt: Date
        var meetingID: UUID?
    }

    struct OneOnOneObjectiveDTO: Codable {
        var stableID: UUID?
        var label: String
        var progress: Int
        var reviewAt: Date?
        var order: Int
        var createdAt: Date
    }

    struct OneOnOneThreadDTO: Codable {
        var stableID: UUID?
        var myRoleRaw: String
        var cadenceDays: Int
        var createdAt: Date
        var commitments: [CommitmentDTO]
        var agendaItems: [OneOnOneAgendaItemDTO]
        var moodEntries: [MoodEntryDTO]
        var objectives: [OneOnOneObjectiveDTO]
    }
```

et les trois champs porteurs, tous optionnels :

```swift
    // MeetingDTO
    /// Optionnel pour rester lisible par les backups antérieurs au lot 19c.
    var notes2: [MeetingNoteDTO]?   // ⚠ voir la note de nommage ci-dessous
    // ProjectDTO
    var milestones: [ProjectMilestoneDTO]?
    var contacts: [ProjectContactDTO]?
    // CollaboratorDTO
    var threads: [OneOnOneThreadDTO]?
```

> **Nommage :** `MeetingDTO` a déjà un champ `notes: String` (le markdown historique de la
> réunion). Le nouveau champ ne peut donc pas s'appeler `notes`. Employer
> `timedNotes: [MeetingNoteDTO]?` — explicite, et sans collision de clé JSON.

- [ ] **Étape 4 : sérialiser** dans `backup(...)` : peupler `timedNotes` depuis
`meeting.meetingNotes` (vérifier le nom réel de la relation inverse sur `Meeting`),
`milestones` / `contacts` depuis les relations de `Project`, et `threads` depuis les fils du
collaborateur — la relation inverse n'existe pas sur `Collaborator`, donc requêter :
`FetchDescriptor<OneOnOneThread>()` filtré sur le collaborateur, ou passer les fils en
paramètre. **Préférer la requête** dans `backup(...)`, via un `ModelContext` obtenu depuis
`collaborator.modelContext` ; si ce n'est pas disponible, ajouter un paramètre
`threads: [OneOnOneThread] = []` avec valeur par défaut, ce qui ne casse aucun appelant.

- [ ] **Étape 5 : désérialiser** dans `restore(...)` : insérer les entités, rétablir
`stableID`, puis recoudre les références de réunion avec un index construit après la
restauration des réunions :

```swift
        var reunionsParID: [UUID: Meeting] = [:]
        for reunion in try context.fetch(FetchDescriptor<Meeting>()) {
            if let id = reunion.stableID { reunionsParID[id] = reunion }
        }
```

- [ ] **Étape 6 : lancer** `swift test --filter OneOnOneBackupTests`, puis
`swift test --filter Backup` (dont `BackupWithoutInterviewTests` et
`BoardBackupAndStorageTests`, qui doivent rester verts).

- [ ] **Étape 7 : mesurer et arbitrer** — si le diff de `BackupService.swift` dépasse
**400 lignes**, s'arrêter après `MeetingNote` + les quatre tables 1:1 (le cœur du lot 0B et
du lot 10), et inscrire `ProjectMilestone` / `ProjectContact` en dette dans l'ADR de la
tâche 12.

- [ ] **Étape 8 : commit**

```bash
git add OneToOne/Services/BackupService.swift Tests/OneOnOneBackupTests.swift
git commit -m "feat(sauvegarde): exporter les tables du lot 0B (notes, fiche projet, 1:1) (lot 19c)"
```

---

## Tâche 10 : `docs/architecture.md`

**Fichiers** — Modifier : `docs/architecture.md` (§5, §8, §9, §13, et l'en-tête de §12 pour
le compte de tests)

**Ce qui est faux aujourd'hui**, constaté : §5 annonce « `SchemaV1` … 28 types `@Model` » et
son diagramme cite `Interview` / `InterviewAttachment`, supprimés (ADR
`2026-08-11-suppression-du-modele-interview.md`) ; le schéma courant est `SchemaV3`
(`SchemaVersions.swift:85-100`), qui ajoute `ChatSession`, `ChatMessageEntity` (V2) puis les
neuf tables du lot 0B ; §8 décrit sept onglets et un dashboard configurable, retirés au lot
19a ; §9 ne connaît ni la chaîne de citation, ni les deux rôles du 1:1, ni les captures, ni
l'atelier ; §12 annonce 42 tests là où la base en compte 1 898 (Swift Testing) ; §13 ne dit
rien de la dette de la refonte.

- [ ] **Étape 1 : §5** — remplacer l'en-tête et l'inventaire :
  - `CurrentSchema` = `SchemaV3` (`Schema.Version(3, 0, 0)`), plan de migration
    `OneToOneMigrationPlan` avec `SchemaV1 → V2 → V3`, **lightweight migration** (aucun
    `MigrationStage` custom), test `Tests/SchemaV3MigrationTests.swift`.
  - Retirer `Interview` et `InterviewAttachment` du diagramme `erDiagram` et de l'inventaire.
  - Ajouter au diagramme : `Meeting ||--o{ MeetingNote`, `Meeting ||--o{ Board`,
    `Project ||--o{ ProjectMilestone`, `Project ||--o{ ProjectContact`,
    `Collaborator ||--o{ OneOnOneThread`, `OneOnOneThread ||--o{ Commitment`,
    `OneOnOneThread ||--o{ OneOnOneAgendaItem`, `OneOnOneThread ||--o{ MoodEntry`,
    `OneOnOneThread ||--o{ OneOnOneObjective`, `Meeting ||--o{ ChatSession` si la relation
    existe (vérifier `ChatSession.swift`).
  - Ajouter deux lignes à l'inventaire : « Réunion, modèle cible (lot 0B) : `MeetingNote`
    (notes horodatées, `visibility`, `sourceRef`), `Board` (planches d'atelier) » et
    « 1:1 (lot 10, D3) : `OneOnOneThread`, `Commitment`, `OneOnOneAgendaItem`, `MoodEntry`,
    `OneOnOneObjective` » ; « Fiche projet (lot 9) : `ProjectMilestone`, `ProjectContact` ».
  - Recompter les `@Model` : `grep -c '^final class' OneToOne/Models/*.swift` est trompeur,
    employer `grep -rn '@Model' OneToOne/Models/ | wc -l` et vérifier
    `CurrentSchema.models.count` dans un test existant s'il y en a un.

- [ ] **Étape 2 : §8** — réécrire la couche Views autour de l'écran de réunion :

```markdown
### L'écran de réunion (refonte 2026-09)

`MeetingView.swift` (~2 050 l.) n'est plus qu'un **routeur** : il monte la barre du haut, la
barre d'espaces et le contenu de l'espace actif, et fabrique `MeetingMenuActions`. Il ne
porte plus d'état d'écran — c'est `MeetingScreenModel` (`Views/Meeting/MeetingScreenModel.swift`),
`@Observable`, qui porte l'espace, le mode, la tête de lecture, le tiroir, la fiche projet, le
brouillon d'action et les filtres.

- **Trois espaces** (spec §1.1), `MeetingScreenModel.Space` : `Réunion`, `Rapport`,
  `Ressources`. Barre : `Views/Meeting/Spaces/MeetingSpacesBar.swift`, masquée dans l'espace
  Réunion en mode Relire (la nav de 190 px la remplace, décision D0).
- **Trois modes** temporels (spec §2.2), `MeetingScreenModel.Mode` : `Préparer`, `En séance`,
  `Relire`. Routage pur : `Services/Meeting/MeetingSpaceRouting.swift`.
- `Views/Meeting/Spaces/**` — bandeau d'indicateurs (`MeetingKPIBand`), colonne notes ↔
  transcription (`Notes/`, `Transcript/`), rail d'actions de 330 px (`Rail/`), poste de
  pilotage (`Review/`), barre d'assistant (`MeetingAssistantDock`).
- `Views/Meeting/Session/**` — mode séance plein écran (spec §2.6) : présentateur,
  substitution du contenu de fenêtre, colonne d'axe temps, panneau d'assistant.
- `Views/Meeting/Resources/**` — tiroir de 396 px, zone « À l'écran », épinglage,
  annotations (spec §4.1–4.2).
- `Views/Meeting/Rail/…` → `Views/Meeting/Spaces/Rail/**` (le rail vit dans l'espace).
- `Views/Meeting/OneOnOne/**` — `Manager/`, `ManagerPrep/`, `Collaborator/`,
  `CollaboratorPrep/`, `Shared/` : les deux rôles du 1:1 (D4), écrans 2a, 2b, 5a, 5b.
- `Views/Meeting/Capture/**` — sélecteur de source, état visible, bande de captures ;
  la pastille flottante est dans `Views/Capture/Pill/**`.
- `Views/Meeting/Workshop/**` — planches d'atelier (Excalidraw embarqué, D6), écrans 6a et 6b.
- `Views/Project/ProjectCardPanel.swift` — la fiche projet en panneau de 430 px (spec §4.3).

Retirés au lot 19a : `OverviewDashboard`, `PanelLayoutEntry`, `DashboardGridLayout`,
`MeetingTabsUnderline`, `CollaboratorDetailView` — les sept onglets et la barre latérale
configurable que la refonte a remplacés (D8).
```

- [ ] **Étape 3 : §9** — ajouter quatre flux, en gardant le style des flux existants :
  1. **Réunion → rapport, avec chaîne de citation** : `MeetingNote` (`kind`, `visibility`,
     `sourceRef`) → `ReportOptionalBlocks` / `ReportHTMLBuilder` → citations résolues par
     `SourceRef` vers le segment ou la capture d'origine.
  2. **1:1, deux rôles** : `OneOnOneThreadStore` crée le fil paresseusement au premier 1:1 ;
     `myRole` déduit du type (D4) ; `Commitment` / `OneOnOneAgendaItem` / `MoodEntry` /
     `OneOnOneObjective` ; trois niveaux de confidentialité (spec §3.2) ; le récap
     collaborateur exclut `escalated` (D9).
  3. **Captures + pastille** : `CaptureCoordinator` (`detectsAutomatically` /
     `periodicCapture`, D7) → `SlideCapture` portant son `t` d'axe audio → bande de captures
     et pastille flottante (⌘⇧S, ⌘⇧N en raccourcis système).
  4. **Atelier** : `Board` + `BoardStore` (scène et vignette sur disque sous
     `recordings/<uuid>/boards/`), trois modes de planche, planche de séance (6b), légendes
     dans le rapport.

- [ ] **Étape 4 : §12 et §13** — corriger le compte de tests (mesuré, avec la date) et
ajouter à la dette :

```markdown
- **`MeetingView.swift` ~2 050 lignes** — routeur d'espaces, fabrique de menu et six
  présentations. La règle du programme de refonte tient (§7 : « rien n'est ajouté dans
  `MeetingView.swift`, on en retire ») mais le fichier reste le plus gros de `Views/`.
- **Code mort hors périmètre de la refonte** — le lot 19a a listé ~3 000 lignes que sa
  seule intention ne pouvait pas retirer (`Services/Agent/`, `MailBrowserView`,
  `AnthropicOAuthClient`, `RAGChatView`, `ManagerCRGenerator`, `MickeyIntegration`,
  `ReportThemeCSS`, `MailSuggestionService`, `ManagerActionReviewSheet`,
  `CollaboratorEntity`/`StartOneToOneIntent`, `ExternalServices`, `SessionPillHost`,
  `CollaboratorTopBarModel`). Un lot dédié, à arbitrer.
- **`AppSettings.rightSidebarLayoutJSON`** — colonne sans lecteur depuis le lot 19a ; elle
  partira avec la prochaine version de schéma.
- **Doubles vérités résiduelles** — `EngagementLedger` (dérivé) et `Commitment` (table) ;
  `ReportOptionalBlocks.escape` duplique `ReportHTMLBuilder.escape`.
```

- [ ] **Étape 5 : relire** le fichier en entier une fois, à la recherche d'autres mentions
d'`Interview`, de `SchemaV1` ou des sept onglets :

```bash
grep -n 'Interview\|SchemaV1\|onglet\|OverviewDashboard\|42 tests' docs/architecture.md
```

- [ ] **Étape 6 : commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): remettre §5, §8, §9 et §13 en accord avec le code (lot 19c)"
```

---

## Tâche 11 : `cleanup-report.md`, `CLAUDE.md`

**Fichiers** — Modifier : `docs/cleanup-report.md`, `CLAUDE.md`

- [ ] **Étape 1 : `docs/cleanup-report.md`** — ajouter une section datée, sans réécrire la
revue de juin :

```markdown
## 8. Refonte de l'écran de réunion — retraits et dette (2026-09-08)

### Supprimé au lot 19a (PR #45), décision D8
`OverviewDashboard`, `PanelLayoutEntry`, `DashboardGridLayout`, `MeetingTabsUnderline`,
`CollaboratorDetailView` : le dashboard personnalisable et la barre latérale configurable de
l'écran de réunion, remplacés par trois espaces et un bandeau de quatre indicateurs.

### Retiré au lot 19c
`MeetingScreenModel.newTaskPomodoros` — sans lecteur depuis que le rail de 330 px a remplacé
l'ancien panneau d'action (lot 3) ; `CapturesStrip` cesse de redéclarer `⌘⇧S`, déjà porté par
le menu Réunion et par le raccourci système.

### Dette restante, mesurée
| Objet | Volume | Pourquoi elle reste |
| --- | --- | --- |
| `Services/Agent/`, `MailBrowserView`, `AnthropicOAuthClient`, `RAGChatView`, `ManagerCRGenerator`, `MickeyIntegration`, `ReportThemeCSS`, `MailSuggestionService`, `ManagerActionReviewSheet`, `CollaboratorEntity`/`StartOneToOneIntent`, `ExternalServices`, `SessionPillHost`, `CollaboratorTopBarModel` | ~3 000 l., 22 fichiers | hors intention de la refonte ; un lot dédié à arbitrer |
| `AppSettings.rightSidebarLayoutJSON` | 1 colonne | attend une version de schéma |
| `ActionsViewMode.kanban` / `.sticky` | 2 cas | encore atteignables depuis `ActionsListView`, hors écran de réunion |
| `MeetingSlidesPopover` | 1 vue | sans appelant depuis le lot 6 |
| `CaptureSource.region` | 1 cas | dans le modèle, jamais écrit (lot 7) |
```

- [ ] **Étape 2 : `CLAUDE.md`** — insérer une section après « Éditeur » :

```markdown
## Écran de réunion (refonte 2026-09)

Spec `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` (branche
`docs/refonte-reunion-programme`), plan directeur
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`, décisions D0–D11 de son §4,
bilan `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`, journal des lots
`docs/superpowers/specs/refonte-2026-09/journal-des-lots.md`.

**Structure.** Trois espaces (`Réunion`, `Rapport`, `Ressources`) × trois modes (`Préparer`,
`En séance`, `Relire`), routés par `Services/Meeting/MeetingSpaceRouting.swift`. Les vues
vivent sous `Views/Meeting/` : `Spaces/**` (bandeau, notes ↔ transcription, rail 330 px,
poste de pilotage), `Session/**` (séance plein écran), `Resources/**` (tiroir 396 px),
`Capture/**`, `OneOnOne/**` (deux rôles), `Workshop/**` (planches), plus
`Views/Project/ProjectCardPanel.swift` (fiche 430 px).

**Règles.**
- **Rien ne s'ajoute dans `MeetingView.swift`** — on en retire. C'est un routeur.
- Aucune couleur hors `One2OneToken`, aucune fonte hors `Font.plexSans` / `.plexMono` /
  `NSFont.plexSans` — un `NSViewRepresentable` ignore le `.font()` de l'environnement.
- L'état d'écran est dans `MeetingScreenModel` (`@Observable`), jamais en `@Binding`
  traversant plus d'un niveau.
- Toute règle métier est une **fonction pure testée** avant sa vue
  (`MeetingSpaceRouting`, `MeetingKPIBuilder`, `MeetingKPI.Level.teinte`, `ReminderRules`…).
- Les raccourcis de réunion sont déclarés **une fois**, dans `Views/Menus/MeetingShortcut.swift` ;
  `Tests/MeetingShortcutsTests.swift` refuse un second déclarant non nommé.
- Les semis de recette sont des extensions de `RefonteDemoSeed`, idempotentes ; la table des
  écrans est `Services/Debug/RecetteScreen.swift`.

**Protocole de recette visuelle, et ses pièges.**
```bash
swift build -c release
Scripts/recette-app.sh /tmp/recette              # refuse un binaire périmé (--force pour outrepasser)
Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --screen 1a
```
- **Isolation du store** : `HOME` ne suffit pas — `NSHomeDirectory()` l'ignore pour une
  application en bundle. C'est `CFFIXED_USER_HOME` qui compte ; `recette-run.sh` pose les
  deux et **tue le processus** si le store n'apparaît pas dans le home jetable. Un semis dans
  le store de production s'est déjà produit (2026-09-07).
- **Ciblage par pid, jamais par nom** : redimensionner avec
  `AXUIElementCreateApplication(<mon pid>)` et capturer avec
  `screencapture -l <kCGWindowNumber>`. **Jamais AppleScript** (`first process whose unix id
  is …` résout mal le processus quand deux instances partagent le `CFBundleIdentifier` — une
  fenêtre de production a été redimensionnée ainsi). Le bundle de recette porte pour cela un
  `CFBundleIdentifier` en `.recette`.
- **Verrou d'écran** : `ioreg -n Root -d1 -r | grep -q 'CGSSessionScreenIsLocked"=Yes'`
  (sans espaces). Verrouillé, toute capture est noire ; le script refuse.
- **Teams** : le script refuse si une fenêtre `MSTeams` porte un titre de réunion ou d'appel.
- **Binaire périmé** : l'erreur la plus coûteuse de la refonte (deux heures d'observations
  fausses). Le script compare le `md5` copié et l'horodatage des sources.
```

- [ ] **Étape 3 : commit**

```bash
git add docs/cleanup-report.md CLAUDE.md
git commit -m "docs: retraits et dette de la refonte, section écran de réunion (lot 19c)"
```

---

## Tâche 12 : ADR de bilan

**Fichiers**
- Créer : `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`
- Modifier : `docs/adr/README.md`

- [ ] **Étape 1 : écrire l'ADR** — structure imposée par `docs/adr/README.md` (contexte,
décision, alternatives, conséquences, statut et date) :

1. **Contexte** : 19 lots, du 0A au 19c, sur la base de treize captures et d'une spec ;
   D0–D11 arbitrées le 2026-09-07.
2. **Décisions D0–D11 telles qu'appliquées** : un tableau `# | décision | appliquée
   comment | où le vérifier`. Exemples : D0 = 1c est la disposition du mode Relire
   (`MeetingSpaceView` route `mode == .review` vers `posteDePilotage`,
   `MeetingSpacesBar.estMasquee`) ; D1 = `MeetingNote` en base, `liveNotes` importé une fois
   (`MeetingNoteStore.importLiveNotesIfNeeded`) ; D2 = Plex embarquées avec repli système
   (`PlexFont`) ; D6 = Excalidraw embarqué derrière `workshopEnabled` ; D8 = dashboard
   supprimé au lot 19a.
3. **Écarts assumés avec les captures**, consolidés depuis les `STATUS.md` des lots : ordre
   de la pile d'avatars ; titres du bloc `ALERTES` et nom de projet du semis ; format de date
   des jalons en édition ; icône de `Notes` ; ordre et métadonnée des pièces du tiroir ;
   marqueur de risque en rond ambre sur la frise ; ordre vertical de l'écran 4a ; badge
   `ATELIER` tronqué sous 1 616 px ; titre de la 14ᵉ séance de fil.
4. **Dettes** : celles de `docs/cleanup-report.md` §8, plus ce que le lot 19c laisse — la
   barre du haut en mode Relire (arbitrage D0, non tranché), le conflit `⌘⏎`, les trois
   doublons de raccourci de `Views/Meeting/Session/**`, le composeur `＋ Action` qui ne prend
   pas le clavier, le rail invisible sous 850 px, la recapture des neuf écrans, et les DTO de
   sauvegarde non faits si la tâche 9 s'est arrêtée à 400 lignes.
5. **Statut** : accepté le 2026-09-08 ; le programme s'achève sur la recette finale (lot 19b).

- [ ] **Étape 2 : index dans `docs/adr/README.md`** — le README n'a aucun index ; en ajouter
un, ordre chronologique inverse, avec les onze ADR existantes plus celle-ci.

- [ ] **Étape 3 : commit**

```bash
git add docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md docs/adr/README.md
git commit -m "docs(adr): bilan de la refonte de l'écran de réunion, D0-D11 appliquées (lot 19c)"
```

---

## Tâche 13 : `STATUS.md` redevient lisible

**Fichiers**
- Créer : `docs/superpowers/specs/refonte-2026-09/journal-des-lots.md`
- Modifier : `STATUS.md`

**Ce qui est à déplacer** : les sections de lot de la refonte, lignes 5 à 4062 de `STATUS.md`
(de « ## Lot 19a … » à la ligne qui précède « ## Chatbot — persistance de l'historique des
conversations (2026-09-06) »), soit ~4 050 lignes et 28 sections. Elles partent **verbatim**,
en ordre **chronologique** (donc inverse de l'ordre actuel).

- [ ] **Étape 1 : extraire**

```bash
sed -n '5,4062p' STATUS.md > /tmp/lot19c-sections.md
grep -c '^## ' /tmp/lot19c-sections.md   # attendu : 28
```

- [ ] **Étape 2 : écrire le journal** — un en-tête, puis les 28 sections réordonnées de la
plus ancienne à la plus récente (l'ordre d'un journal), texte inchangé :

```markdown
# Journal des lots — refonte de l'écran de réunion (2026-09)

Les comptes rendus de session des lots 0A à 19a, déplacés de `STATUS.md` par le lot 19c :
4 050 lignes qui rendaient `STATUS.md` illisible. **Texte inchangé**, ordre chronologique.
La synthèse et la pile de fusion vivent dans `STATUS.md`, section « Refonte de l'écran de
réunion — état au 2026-09-08 ».

Décisions D0–D11 : `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §4.
Bilan : `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`.

---
```

- [ ] **Étape 3 : la section de synthèse de `STATUS.md`**, en remplacement des 4 050 lignes :

```markdown
## Refonte de l'écran de réunion — état au 2026-09-08

Comptes rendus de session, lots 0A à 19a :
`docs/superpowers/specs/refonte-2026-09/journal-des-lots.md`.
Spec, plan directeur et décisions D0–D11 :
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §4 et §5.
Bilan : `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`.

### Pile et ordre de fusion
<numéros de PR de #19 à #45, plus celle du lot 19c, dans l'ordre où elles se fusionnent,
avec la base de chacune. À établir avec `gh pr list --state open --json number,title,baseRefName`
au moment d'écrire.>

### Tests
`swift test` complet vert : <compte Swift Testing> tests Swift Testing / <suites> suites,
<compte XCTest> XCTest, le <date, heure>. `--skip CalendarImportEventTests` n'est plus
nécessaire. Un seul échec connu, horaire : `MenuBarStatsTests` entre 0 h et 2 h
(heure de référence non injectée — corrigé par la PR #37 sur `master`, hors pile).

### Décisions en attente de Laurent
| Sujet | Question | Source |
| --- | --- | --- |
| Lignes de démonstration dans le store de production | 1 projet `P25_110_1`, 1 réunion, 12 actions, 5 risques, 4 segments, 3 jalons, 3 interlocuteurs, 6 collaborateurs : les supprimer ? | lot 9 |
| Teinte de la barre de budget à 65,6 % | règle chiffrée (vert) ou maquette (orange) ? | lot 9 |
| Ordre de la pile d'avatars | l'ordre de la capture ou celui du modèle ? | lot 1 |
| Contraste `ok/deep` sur `ok/bg` | 4,43:1, sous le seuil de 4,5 — assouplir ou changer le jeton ? | lot 0A |
| `Notes 6` / `EN ATTENTE 9` | compteurs de la maquette non reproduits par le semis | lots 1, 12 |
| Bouton `Capture` en 1:1 | le reléguer dans `⋯`, comme la maquette 2a ? | lot 11 |
| Barre du haut en mode Relire | la masquer prive du type, du template et du `⋯` (arbitrage D0) | recette (c) n° 4 |
| `⌘⏎` | « Générer le rapport » (menu) contre « valider le composeur » (spec §1.4) | lot 19c |
| Rail invisible sous 850 px | le composeur d'action devient injoignable | lot 3 |

### Dettes
<reprendre la table de `docs/cleanup-report.md` §8, en une ligne chacune.>

### Prochaine action
**Recette finale (lot 19b)** : recapturer les douze écrans à 1 280 et 1 920 px avec le binaire
de la pile complète, écran déverrouillé et sans réunion Teams, puis comparer aux références de
`docs/superpowers/specs/refonte-2026-09/`.
```

- [ ] **Étape 4 : la section de lot en tête de `STATUS.md`** — au-dessus de tout, dans la
forme des sections de lot du dépôt : ce qui a été fait (les six volets), ce qui est renvoyé et
pourquoi, les comptes de `swift test` avec l'heure, la commande de vérification, la prochaine
action.

- [ ] **Étape 5 : vérifier** qu'aucune ligne n'a été perdue

```bash
grep -c '' STATUS.md docs/superpowers/specs/refonte-2026-09/journal-des-lots.md
grep -c '^## ' docs/superpowers/specs/refonte-2026-09/journal-des-lots.md   # attendu : 28
```

- [ ] **Étape 6 : commit**

```bash
git add STATUS.md docs/superpowers/specs/refonte-2026-09/journal-des-lots.md
git commit -m "docs(status): déplacer le journal des lots, synthétiser l'état de la refonte (lot 19c)"
```

---

## Tâche 14 : `swift test` complet, rebase, PR

- [ ] **Étape 1 : test complet**

```bash
date '+%H:%M:%S'
swift test 2>&1 | tee /tmp/lot19c-test.log | tail -5
grep -E 'Test run with|Executed [0-9]+ tests|error:|failed' /tmp/lot19c-test.log | tail -20
```

Attendu : exit 0, aucun `failed`. Hors 0 h–2 h, aucun échec n'est toléré.

- [ ] **Étape 2 : la règle de rebase** (l'intégration de la vague 7 empile
`#36 → #43 → #42 → #44` et force-pousse)

```bash
git fetch origin
gh pr view 44 --json baseRefName --jq .baseRefName
```

- Si la réponse est `fix/refonte-session-fullscreen-content`, l'intégration est finie et le
  sommet est `origin/feat/refonte-lot-18-planche-de-seance`. Rebaser **d'abord le lot 19a** :

```bash
git checkout -b lot19a-int origin/feat/refonte-lot-19a-cloture
git rebase --onto origin/feat/refonte-lot-18-planche-de-seance origin/fix/refonte-recette-vagues-1-4
swift build && swift test
git push --force-with-lease origin lot19a-int:refs/heads/feat/refonte-lot-19a-cloture
gh pr edit 45 --base feat/refonte-lot-18-planche-de-seance
git checkout feat/refonte-lot-19c-cloture-suite
git rebase --onto lot19a-int "$(cat .lot19c-base-sha)"
swift test
```

- Sinon : sonder toutes les cinq minutes, au plus 45 minutes ; puis ouvrir la PR sur
  `feat/refonte-lot-19a-cloture` en notant dans le corps qu'un rebase suivra.

> Au rebase, deux tests de ce lot peuvent devenir rouges légitimement :
> `MeetingShortcutsTests.aucunSecondDeclarant` si le lot 18 déclare l'un des sept raccourcis
> (l'ajouter à `attendus` en le justifiant), et `EllipsisTests` si un fichier de la liste a
> bougé. C'est le but du test : le signaler.

- [ ] **Étape 3 : PR**

```bash
gh pr create --base feat/refonte-lot-19a-cloture \
  --title "feat(refonte): lot 19c — clôture : raccourcis, finitions, outillage, documentation" \
  --body "<fait / renvoyé / swift test / ordre de fusion complet>"
```

Corps : ce qui est fait (six volets), ce qui est renvoyé et pourquoi, les comptes exacts de
`swift test` avec l'heure, l'ordre de fusion complet, et
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`. **Ne pas merger.**

- [ ] **Étape 4 : supprimer le fichier de travail**

```bash
git rm --cached .lot19c-base-sha 2>/dev/null; rm -f .lot19c-base-sha
```

(Il ne doit pas être commité : c'est un repère de session.)

---

## Renvois — ce que ce lot ne tranche pas

| Sujet | Pourquoi il n'est pas traité ici | Où il est consigné |
| --- | --- | --- |
| **Barre du haut en mode Relire** (recette (c) n° 4) | `MeetingSpacesBar.estMasquee` est **correct** et testé (`Tests/ReviewStateTests.swift:106-117`) : il masque la barre d'**espaces** dans l'espace Réunion en Relire, et la laisse dans Rapport et Ressources, qui n'ont pas de nav latérale. Ce que la recette a vu est la barre du **haut**, dont la disparition priverait du type, du template et du `⋯` : arbitrage D0, décision produit. | STATUS « en attente », ADR de bilan |
| **Conflit `⌘⏎`** | Le menu Réunion l'emploie pour « Générer le rapport » et le menu natif l'emporte sur tout `keyboardShortcut` de vue ; la spec §1.4 le veut pour valider un composeur. Changer l'un des deux est une décision produit. La table le documente, la feuille l'annonce, `ActionComposer` continue de l'intercepter par `onKeyPress`. | table `MeetingShortcut.note`, feuille, STATUS |
| **Trois doublons de raccourci** (⌘K, ⌘M, ⌃⌘F dans `Views/Meeting/Session/**`) | Dossier tenu par le correctif #42 ; les trois portent déjà un commentaire justificatif. Inscrits comme exceptions nommées, donc toute nouvelle occurrence échoue. | `MeetingShortcutsTests.attendus`, ADR |
| **`＋ Action` ne prend pas le clavier** (lot 5) | Demande un jeton de focus dans `MeetingScreenModel` et une reprise du composeur : une intention à part. | ADR, STATUS |
| **Rail invisible sous 850 px** (lot 3) | Le composeur devient injoignable : c'est un arbitrage de disposition, à trancher avec la recette 1 280 px du lot 19b. | ADR, STATUS |
| **Semis de locuteurs pour la bascule `Speakers`** | La bascule est corrigée (elle ne dépend plus des segments), mais `RefonteDemoSeed` est gelé pour les lots livrés : poser des locuteurs sur ses quatre segments est une décision de semis. | STATUS |
| **Recapture des douze écrans** | Aucun lancement d'application graphique dans ce lot. | prochaine action = lot 19b |
| **~3 000 lignes de code mort hors refonte** | Hors intention (une PR = une intention). | `cleanup-report.md` §8 |

---

## Auto-revue

**Couverture du périmètre**

| Demande | Tâche |
| --- | --- |
| 8 raccourcis §1.4 déclarés une fois | 1 |
| `MeetingShortcutsTests` (spec → déclaration, pas de doublon) | 1 |
| Feuille « Raccourcis » depuis `⋯` | 1 |
| Titre en `plexSans(13, .semibold)` sans bezel | 2 |
| `MeetingSpacesBar` en Relire | renvoyé (vérifié correct et testé) |
| Bascule `Speakers` si `.diarizeFirst` | 4 |
| Niveaux de risque `report` / `warn` / neutre | 3 |
| `Citer` / `Envoyer` sur toute pièce | 4 |
| Point de statut en édition | 4 |
| Pied de fiche : mention toujours, boutons en édition | 4 |
| `lineLimit(1)` + `truncationMode(.tail)` | 5 (et 2 pour la cause racine des champs) |
| `newTaskPomodoros` retiré, tests adaptés | 6 |
| `recette-app.sh` : `md5`, fraîcheur, `--force`, identité `.recette` | 7 |
| `recette-run.sh` : verrou, Teams, 12 codes, en-tête | 8 |
| Vérification manuelle documentée dans les scripts | 7, 8 |
| `BackupService` : 8 DTO + aller-retour | 9 |
| `docs/architecture.md` §5, §8, §9, §13 | 10 |
| `docs/cleanup-report.md`, `CLAUDE.md` | 11 |
| ADR de bilan, `docs/adr/README.md` | 12 |
| `STATUS.md` + journal des lots | 13 |
| `swift test` complet, rebase, PR | 14 |

**Cohérence des types** — `MeetingShortcut.Surface.menu` porte un `MeetingMenuItem`, le type
réel de `MeetingMenuActions.swift:4`. `MeetingKPI.Level` a bien quatre cas
(`MeetingKPIBuilder.swift:42`). `MeetingKPIBand.teinte(_:)` et
`ProjectCardPanel.color(for:)` gardent leur signature : leurs quatre appelants ne changent
pas. `EditableTextField.configure(_:)` est le point de test des tâches 2 et 5.
