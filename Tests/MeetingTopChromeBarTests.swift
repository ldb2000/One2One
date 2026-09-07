import Testing
import SwiftUI
@testable import OneToOne

/// Ce que la barre du haut promet, spec §2.1 : **une seule ligne**, 38 px,
/// fond `bg/app`, et une pilule audio dont le temps se saisit à la main.
///
/// Les tests portent sur ce qui est vérifiable sans écran : la géométrie
/// déclarée, la teinte selon le type, et la lecture d'un timecode tapé — le
/// seul endroit de la barre où une saisie libre entre dans le modèle.
@Suite("Barre du haut de la réunion")
struct MeetingTopChromeBarTests {

    // MARK: - L'arbitrage de largeur (lot 17 + recette vagues 1–4)

    /// Deux recettes ont relevé les deux faces du même défaut : le badge
    /// `ATELIER` tronqué à 1 616 px (lot 16), et `Rapport ✓ 6:20` réduit à
    /// « R », `Capture` à « C », `● Partage actif · 5 voient` à un carré bleu à
    /// 1 280 px (vague 1–4). Les deux correctifs sont conservés parce qu'ils
    /// vont dans le même sens ; ce test verrouille la règle **entière**, car
    /// n'en garder qu'une moitié ramène l'un des deux défauts — et aucune des
    /// deux moitiés ne se voit dans l'état d'un modèle.
    ///
    /// Lecture des sources, comme `SessionNoChromeTests` et
    /// `ActionsRailNoModalTests` : c'est de la mise en page SwiftUI, qu'aucune
    /// suite headless ne mesure.
    private func chromeBarSource() throws -> String {
        let fichier = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OneToOne/Views/Meeting/MeetingTopChromeBar.swift")
        return try String(contentsOf: fichier, encoding: .utf8)
    }

    @Test("Le titre est le perdant désigné de l'arbitrage de largeur")
    func titrePorteLaPrioriteDeCompression() throws {
        let source = try chromeBarSource()
        // `layoutPriority(-1)` : servi en dernier, donc comprimé le premier.
        // Un `layoutPriority(1)` sur le titre est précisément ce que la
        // recette du lot 16 a fait tomber.
        #expect(source.contains(".layoutPriority(-1)"))
        #expect(!source.contains(".layoutPriority(1)"))
    }

    @Test("Les contrôles de droite gardent leur largeur intrinsèque")
    func controlesHorsAtteinte() throws {
        let source = try chromeBarSource()
        // Le groupe extrait par la recette de la vague 1–4, et son `fixedSize`.
        #expect(source.contains("private var controlsGroup: some View"))
        #expect(source.contains("controlsGroup"))
        #expect(source.contains(".fixedSize(horizontal: true, vertical: false)"))
    }

    @Test("La pilule de partage est une capsule, pas un bouton")
    func piluleDePartageEnCapsule() throws {
        let source = try chromeBarSource()
        // Spec §4.2 : « pilule `accent/action` pleine ». Le rayon d'un bouton
        // (6) donnait un carré bleu — relevé par la recette de la vague 1–4.
        #expect(source.contains("Capsule(style: .continuous).fill(One2OneToken.action)"))
        #expect(source.contains(".contentShape(Capsule(style: .continuous))"))
    }

    @Test("Hauteur de 38 px et padding 9 × 14, comme la spec §2.1")
    func geometry() {
        #expect(MeetingTopChromeBar.height == 38)
        #expect(MeetingTopChromeBar.paddingVertical == 9)
        #expect(MeetingTopChromeBar.paddingHorizontal == 14)
    }

    @Test("Les deux types 1:1 teintent la barre, les autres non")
    func tintFollowsKind() {
        // Spec §1.2 : `accent/oneonone` bg `#f4f1f6` — « Type 1:1 : badge,
        // confidentialité, sections de notes ». La barre teintée est le signal
        // que la séance est privée.
        #expect(MeetingTopChromeBar.tint(for: .oneToOne) == One2OneToken.oneOnOneBg)
        #expect(MeetingTopChromeBar.tint(for: .manager) == One2OneToken.oneOnOneBg)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(MeetingTopChromeBar.tint(for: kind) == One2OneToken.bgApp,
                    "\(kind.label) ne doit pas être teinté")
        }
    }

    @Test("Un timecode tapé à la main est lu")
    func timecodeParsing() {
        #expect(MeetingTopChromeBar.TimecodeInput.parse("04:12") == 252)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("4:12") == 252)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("00:00") == 0)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("23:24") == 1404)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("1:02:03") == 3723)
        // Un nombre seul est un nombre de secondes : c'est ce que l'on tape
        // quand on relit un journal.
        #expect(MeetingTopChromeBar.TimecodeInput.parse("252") == 252)
        #expect(MeetingTopChromeBar.TimecodeInput.parse(" 04:12 ") == 252)
    }

    @Test("Une saisie qui n'est pas un timecode est refusée, pas devinée")
    func timecodeRejection() {
        // Refuser rend `nil`, ce qui laisse la tête de lecture où elle est.
        // Deviner déplacerait la lecture au hasard — le pire des deux.
        #expect(MeetingTopChromeBar.TimecodeInput.parse("") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("   ") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("abc") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("04:99") == nil)   // 99 secondes
        #expect(MeetingTopChromeBar.TimecodeInput.parse("1:99:00") == nil) // 99 minutes
        #expect(MeetingTopChromeBar.TimecodeInput.parse("-30") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("1:2:3:4") == nil)
        #expect(MeetingTopChromeBar.TimecodeInput.parse("04:1a") == nil)
    }

    @Test("Le temps affiché dans la pilule est celui de la tête de lecture")
    @MainActor func pillShowsPlayheadTime() {
        // La pilule lit `playhead.formatted` : c'est ce qui garantit qu'elle,
        // la frise et les notes parlent du même `t` (spec §1.1).
        let playhead = MeetingPlayhead(meetingStableID: UUID())
        playhead.duration = 1404
        playhead.seek(to: 252)
        #expect(playhead.formatted == "04:12")
        #expect(MeetingPlayhead.mmss(playhead.duration) == "23:24")
    }

    // MARK: - Segment projet du fil d'Ariane (lot 9)

    /// Le segment projet est le déclencheur de la fiche (spec §4.3). Le chevron
    /// `⌄` de la capture 3b dit qu'il ouvre quelque chose : sans lui, un cadre
    /// bleu ressemble à une sélection, pas à un bouton.
    @Test("Le segment projet annonce l'ouverture de la fiche")
    func projectSegmentAnnouncesTheCard() {
        #expect(MeetingTopChromeBar.projectSegmentChevron == "⌄")
        #expect(MeetingTopChromeBar.projectSegmentHelp == "Ouvrir la fiche du projet")
    }
}
