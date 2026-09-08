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

// MARK: - Quatre écarts de vue (écarts (c) n° 5, 8, 9, 10)

/// Les quatre écarts que la recette des vagues 1–4 a renvoyés au lot 19 et qui
/// se corrigent dans une vue. Vérifiés en relisant la source : ce sont des
/// conditions d'affichage, pas des règles calculables.
@Suite("Finitions du lot 19c — quatre écarts de vue")
struct EcartsDeVueTests {

    @Test("la bascule Speakers ne dépend que du mode de transcription (n° 5)")
    func basculeSpeakers() {
        let source = RefonteSource.lire("OneToOne/Views/MeetingView.swift")
        #expect(source.contains("showsSpeakerToggle: settings.transcriptionMode == .diarizeFirst"))
        #expect(!source.contains("&& !meeting.transcriptSegments.isEmpty"),
                "la bascule ne doit plus attendre qu'un segment soit diarisé")
    }

    @Test("Citer et Envoyer sont offerts par vignette, pas seulement à l'écran (n° 8)")
    func citerEtEnvoyerParVignette() {
        let chemin = "OneToOne/Views/Meeting/Resources/ResourceTile.swift"
        let source = RefonteSource.lire(chemin)
        // Le prédicat de citabilité, celui que le menu contextuel employait déjà.
        #expect(source.contains("item.isPinnable && !item.isOrphan"))
        // Un seul site de déclaration pour chaque bouton.
        #expect(RefonteSource.occurrences("bouton(\"Citer\"", dans: chemin) == 1)
        #expect(RefonteSource.occurrences("bouton(\"Envoyer\"", dans: chemin) == 1)
        // Et la branche qui les réservait à la pièce présentée est partie.
        #expect(!source.contains("la seule à porter les trois actions"))
        #expect(source.contains("Spec §4.1"), "la raison du changement est dans le code")
    }

    @Test("le point de statut est une Image, rendue dans un label de menu (n° 9)")
    func pointDeStatutEnEdition() {
        let source = RefonteSource.lire("OneToOne/Views/Project/ProjectCardPanel.swift")
        #expect(source.contains("Image(systemName: \"circle.fill\")"),
                "un Circle() dans un label de Menu n'est pas rendu par AppKit")
    }

    @Test("la mention de visibilité du pied reste hors édition (n° 10)")
    func mentionDeVisibiliteToujoursVisible() {
        let chemin = "OneToOne/Views/Project/ProjectCardPanel.swift"
        let source = RefonteSource.lire(chemin)
        // Le pied est scindé : la mention d'un côté, les boutons de l'autre.
        #expect(source.contains("private var footerNoticeRow"))
        #expect(source.contains("private var footerActions"))
        // Seuls les boutons dépendent de l'édition.
        #expect(source.contains("if isEditing { footerActions }"))
        #expect(RefonteSource.occurrences("footerNoticeRow", dans: chemin) >= 2,
                "la mention est déclarée puis rendue")
    }
}

// MARK: - Ellipsis (écart (a) « troncatures sans ellipsis »)

/// Un libellé qui se coupe doit dire qu'il est coupé (spec §1.2). La recette
/// des vagues 1–4 a relevé « Chiffrage du reste à faire non », « Facturation de
/// 40k sans livra », « Claire-Amélie F.· » : des noms et des titres coupés net.
///
/// La cause racine était dans `EditableTextField` (cf. `ChampDeTitreTests`) ;
/// restaient les `Text` de noms propres et de titres variables rendus dans une
/// largeur contrainte, sans `lineLimit`. Ce test les tient.
///
/// **Ne sont pas dans la liste, à dessein** : les libellés que la maquette
/// laisse passer à la ligne (`ReviewSidebarNav`, où le nom de projet et les
/// titres d'alerte portent un `fixedSize(vertical: true)` délibéré dans la nav
/// de 190 px), les invites d'état de `CapturesStrip` (des phrases, mieux
/// servies par un retour à la ligne), et les vues des dossiers tenus par les
/// lots concurrents (`Session/**`, `Workshop/**`, `OneOnOne/CollaboratorPrep/**`).
@Suite("Finitions du lot 19c — ellipsis")
struct EllipsisTests {

    /// Chaque fichier corrigé, avec le nombre d'ellipsis qu'il doit porter.
    private static let attendus: [(String, Int)] = [
        ("OneToOne/Views/Meeting/Spaces/MeetingSpacesBar.swift", 1),
        ("OneToOne/Views/Meeting/Spaces/Rail/ActionsRail.swift", 1),
        ("OneToOne/Views/Meeting/Spaces/Transcript/TranscriptSpeakerTools.swift", 3),
        ("OneToOne/Views/Meeting/OneOnOne/Manager/CommitmentsRail.swift", 1),
        ("OneToOne/Views/Meeting/ManageParticipantsSheet.swift", 3),
        ("OneToOne/Views/Meeting/MeetingTagEditor.swift", 2),
    ]

    @Test("chaque libellé contraint corrigé porte lineLimit(1) et truncationMode(.tail)")
    func ellipsisPosees() {
        for (chemin, compte) in Self.attendus {
            #expect(!RefonteSource.lire(chemin).isEmpty, "source introuvable : \(chemin)")
            #expect(RefonteSource.occurrences(".truncationMode(.tail)", dans: chemin) == compte,
                    "\(chemin) : \(compte) ellipsis attendues")
        }
    }

    @Test("aucun lineLimit(1) sans ellipsis dans les fichiers corrigés")
    func pasDeCoupeMuette() {
        for (chemin, _) in Self.attendus {
            let uneLigne = RefonteSource.occurrences(".lineLimit(1)", dans: chemin)
            let ellipsis = RefonteSource.occurrences(".truncationMode(.tail)", dans: chemin)
            #expect(ellipsis >= uneLigne,
                    "\(chemin) : \(uneLigne) lineLimit(1) pour \(ellipsis) truncationMode")
        }
    }
}
