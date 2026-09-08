import Testing
import Foundation
import SwiftUI
import AppKit
@testable import OneToOne

/// Lecture des sources du dépôt depuis un test : le seul moyen de vérifier un
/// modifieur de mise en page ou l'absence d'une condition sans monter la vue.
/// Motif déjà employé par `Tests/ReviewStateTests.swift`.
enum RefonteSource {
    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    static var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func lire(_ chemin: String) -> String {
        (try? String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8)) ?? ""
    }

    /// Nombre d'occurrences de `motif` dans le fichier.
    static func occurrences(_ motif: String, dans chemin: String) -> Int {
        lire(chemin).components(separatedBy: motif).count - 1
    }
}

// MARK: - Champ de titre (écarts (c) n° 3 et n° 11)

/// Écart (c) n° 3 de la recette des vagues 1–4 : « le titre de réunion n'est
/// pas un titre ». `EditableTextField` forçait `NSFont.systemFont` et
/// `bezelStyle = .roundedBezel`, et un `NSViewRepresentable` ignore le
/// `.font()` de l'environnement SwiftUI : le `.font(.plexSans(13, .semibold))`
/// de `MeetingTopChromeBar` n'avait aucun effet.
///
/// Écart n° 11 dans le même mouvement : sans `usesSingleLineMode`, AppKit
/// ignore `lineBreakMode` et coupe le texte **sans ellipsis** — c'est ce que la
/// recette a vu sur les cellules de la fiche projet en édition.
@Suite("Finitions du lot 19c — champ de titre")
struct ChampDeTitreTests {

    private func champ(style: EditableTextField.Style = .bezeled,
                       font: NSFont? = nil,
                       texte: String = "") -> NSTextField {
        var valeur = texte
        let vue = EditableTextField(placeholder: "Titre",
                                    text: Binding(get: { valeur }, set: { valeur = $0 }),
                                    style: style,
                                    font: font)
        let field = NSTextField()
        vue.configure(field)
        return field
    }

    @Test("le style plain ne dessine ni bezel ni bordure et prend la fonte demandée")
    func stylePlain() {
        let field = champ(style: .plain, font: .plexSans(13, .semibold),
                          texte: "Réunion de cadrage")
        #expect(field.isBezeled == false)
        #expect(field.isBordered == false)
        #expect(field.drawsBackground == false)
        #expect(field.focusRingType == .none)
        #expect(field.font?.pointSize == 13)
        #expect(field.stringValue == "Réunion de cadrage")
    }

    @Test("le style bezelé reste le défaut, inchangé pour les autres usages")
    func styleBezeleParDefaut() {
        let field = champ()
        #expect(field.isBezeled)
        #expect(field.bezelStyle == .roundedBezel)
        #expect(field.focusRingType != .none, "un champ de saisie garde son anneau de focus")
        #expect(field.font == .systemFont(ofSize: NSFont.systemFontSize))
    }

    @Test("les deux styles diffèrent bien à l'œil")
    func lesDeuxStylesDifferent() {
        let bezele = champ()
        let plat = champ(style: .plain)
        #expect(bezele.isBezeled && !plat.isBezeled)
        #expect(bezele.focusRingType != plat.focusRingType)
    }

    @Test("le champ tronque avec une ellipsis, quel que soit son style")
    func ellipsisEnFinDeLigne() {
        for style in [EditableTextField.Style.bezeled, .plain] {
            let field = champ(style: style,
                              texte: String(repeating: "libellé très long ", count: 12))
            #expect(field.usesSingleLineMode,
                    "sans usesSingleLineMode, AppKit ignore lineBreakMode")
            #expect(field.lineBreakMode == .byTruncatingTail)
            #expect(field.cell?.truncatesLastVisibleLine == true)
        }
    }

    @Test("la barre du haut monte son titre en Plex Sans, sans bezel")
    func titreDeLaBarreEnPlain() {
        let source = RefonteSource.lire("OneToOne/Views/Meeting/MeetingTopChromeBar.swift")
        #expect(source.contains("style: .plain"))
        #expect(source.contains("font: .plexSans(13, .semibold)"))
        // Le modifieur SwiftUI qui n'avait aucun effet sur un NSTextField est parti.
        #expect(!source.contains("text: $meeting.title)\n            .font("))
    }

    @Test("NSFont.plexSans résout la même fonte que Font.plexSans")
    func nsFontPlexSans() {
        let fonte = NSFont.plexSans(13, .semibold)
        #expect(fonte.pointSize == 13)
        if PlexFont.isInstalled(PlexWeight.semibold.sansPostScriptName) {
            #expect(fonte.fontName == PlexWeight.semibold.sansPostScriptName)
        }
    }

    @Test("NSFont.plexMono résout la variante monospace, ou retombe sans mentir")
    func nsFontPlexMono() {
        let fonte = NSFont.plexMono(11, .medium)
        #expect(fonte.pointSize == 11)
        if PlexFont.isInstalled(PlexWeight.medium.monoPostScriptName) {
            #expect(fonte.fontName == PlexWeight.medium.monoPostScriptName)
        }
    }
}

// MARK: - Teinte d'un niveau de risque (écart (c) n° 6)

/// Écart (c) n° 6 : « les niveaux de risque bas sortent en bleu (`action`) et
/// gris (`ink/4`) sur les points du bandeau, du bloc `ALERTES` et de la fiche
/// projet. La maquette n'emploie que `report` et `warn`. »
///
/// Deux tables divergeaient : `MeetingKPIBand.teinte` donnait `warn` à l'élevé
/// et le **bleu des actions** au modéré, tandis que `ProjectCardPanel` avait
/// déjà la palette de la maquette. Il n'en reste qu'une.
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
            #expect(ProjectCardPanel.color(for: niveau) == niveau.teinte)
        }
        // Le rail et la nav Relire passent par la sévérité brute d'un
        // `ProjectAlert` : la chaîne complète doit rendre la même couleur.
        for severite in ["critique", "eleve", "modere", "faible", "n'importe quoi"] {
            let niveau = MeetingKPIBuilder.level(fromSeverity: severite)
            #expect(ActionsRailRisks.teinte(severite) == niveau.teinte)
        }
    }

    @Test("la nav du mode Relire n'a pas sa propre table")
    func navRelireDelegue() {
        let source = RefonteSource.lire(
            "OneToOne/Views/Meeting/Spaces/Review/ReviewSidebarNav.swift")
        #expect(source.contains("teinte("), "la nav doit déléguer, pas colorier elle-même")
    }
}
