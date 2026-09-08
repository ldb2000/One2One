import SwiftUI

/// Les jetons visuels de la refonte de l'écran de réunion, spec §1.2.
///
/// C'est le **seul** endroit du projet où une couleur de la refonte est écrite.
/// Une couleur qui n'est pas dans cette table n'a pas à apparaître sur un écran
/// refondu. Les palettes historiques (`AppTheme`, `MeetingTheme`, `FicheTokens`)
/// restent en place pour les écrans non refondus : elles ne sont ni fusionnées
/// ni supprimées ici.
///
/// Copié depuis `Teams-Capture/Sources/CaptureDesign/Tokens.swift` (règle du
/// programme de refonte : copier, jamais lier), puis complété de la palette
/// `dark/*` du mode séance et des largeurs fixes de la conception.
enum One2OneToken {

    // MARK: - Fonds

    static let bgApp = Color(hex: 0xF7F4EE)
    static let bgCanvas = Color(hex: 0xFAF8F4)
    static let surface = Color(hex: 0xFFFFFF)
    static let surfaceAlt = Color(hex: 0xFDFCFA)

    // MARK: - Bordures

    static let hair = Color.black.opacity(0.07)
    static let cardBorder = Color.black.opacity(0.09)
    static let strongBorder = Color.black.opacity(0.14)

    // MARK: - Encres

    static let ink1 = Color(hex: 0x1A1A1A)
    static let ink2 = Color(hex: 0x2A2723)
    static let ink3 = Color(hex: 0x4A453D)
    static let ink4 = Color(hex: 0x6B6659)
    /// Placeholder et métadonnée. **Jamais sous 11,5 px** : n'atteint pas 4,5:1
    /// sur `surface` (cf. `One2OneTokensTests`).
    static let inkMuted = Color(hex: 0x7D7768)

    // MARK: - Accents

    static let action = Color(hex: 0x2563D9)
    static let actionBg = Color(hex: 0xEEF2FD)
    static let actionBg2 = Color(hex: 0xF7FAFF)
    static let actionInk = Color(hex: 0x1B4DAD)

    static let report = Color(hex: 0xB8544C)
    static let reportBg = Color(hex: 0xFBECEB)
    static let reportInk = Color(hex: 0x8F3F38)

    static let ok = Color(hex: 0x2F9E5F)
    static let okDeep = Color(hex: 0x2F7D4E)
    static let okBg = Color(hex: 0xE8F3EC)

    static let warn = Color(hex: 0xD98324)
    static let warnInk = Color(hex: 0x8A5A12)
    static let warnBg = Color(hex: 0xF9EFE0)

    static let oneOnOne = Color(hex: 0x6B4D8F)
    static let oneOnOneInk = Color(hex: 0x5C4180)
    static let oneOnOneBg = Color(hex: 0xF4F1F6)

    static let workshop = Color(hex: 0x1F6B6B)
    static let workshopBg = Color(hex: 0xF2F8F7)

    // MARK: - Palette sombre du mode séance (capture 1b)

    /// Fond général du mode séance.
    static let darkBase = Color(hex: 0x1C1A17)
    /// Fond de la colonne de transcription, un cran plus sombre que la base.
    static let darkTranscript = Color(hex: 0x191714)
    /// Carte au repos.
    static let darkCard = Color(hex: 0x221F1B)
    /// Carte active — le segment de transcription survolé ou sélectionné.
    static let darkCardActive = Color(hex: 0x232019)
    /// Pilule et champ.
    static let darkPill = Color(hex: 0x2F2B26)

    static let darkInk1 = Color(hex: 0xF2EFE9)
    static let darkInk2 = Color(hex: 0xE6E1D8)
    static let darkInk3 = Color(hex: 0xC9C3B8)
    static let darkInk4 = Color(hex: 0x9A9285)

    static let darkAction = Color(hex: 0x9AB6F0)
    /// Décision et rapport sur fond sombre. Absent de `Teams-Capture`, qui
    /// n'affiche que la pastille : ajouté pour le mode séance.
    static let darkReport = Color(hex: 0xE8B0AA)
    static let darkWarn = Color(hex: 0xE8C48A)

    // MARK: - Cas particuliers

    /// Marqueur de capture sur la frise. Bleu profond, distinct de `action`, qui
    /// est réservé au marqueur de la **dernière** capture.
    static let captureMarker = Color(hex: 0x3D5180)

    /// Voile d'assombrissement sur la partie non retenue d'un aperçu. Pas dans
    /// la table du §1.2 : c'est un voile, pas une couleur de la charte, mais il
    /// n'a pas à être écrit en clair dans une vue — sinon la règle « seul ce
    /// fichier nomme une couleur » cesse d'être vraie et cesse donc d'être
    /// vérifiable.
    static let scrim = Color.black.opacity(0.45)

    /// Texte sur les boutons pleins, quelle que soit la teinte du fond. Même
    /// raison que `scrim` : blanc n'est pas une teinte de la charte, mais
    /// l'écrire en clair dans une vue romprait la règle.
    static let onFilledButton = Color.white

    // MARK: - Rayons (spec §1.2, Géométrie)

    static let radiusPreview: CGFloat = 4
    static let radiusButton: CGFloat = 6
    static let radiusCard: CGFloat = 7
    static let radiusPanel: CGFloat = 10
    static let radiusPill: CGFloat = 11
    static let radiusAudio: CGFloat = 16

    // MARK: - Densités (spec §1.2, Géométrie)

    static let cardPaddingMin: CGFloat = 9
    static let cardPaddingMax: CGFloat = 13
    static let cardGap: CGFloat = 12
    static let tableRowPaddingV: CGFloat = 8

    // MARK: - Largeurs fixes (spec §1.2, Géométrie)

    /// Rail d'actions des types multi-participants.
    static let actionsRailWidth: CGFloat = 330
    /// Rail 1:1 côté manager.
    static let oneOnOneRailNarrow: CGFloat = 320
    /// Rail 1:1 côté collaborateur.
    static let oneOnOneRailWide: CGFloat = 356
    /// Navigation latérale du poste de pilotage (mode Relire).
    static let sideNavWidth: CGFloat = 190
    /// Palette d'outils de l'atelier.
    static let toolPaletteWidth: CGFloat = 52
    /// Colonne temps du mode séance.
    static let timeColumnWidth: CGFloat = 78
    /// Panneau de fiche projet.
    static let projectPanelWidth: CGFloat = 430
    /// Tiroir de ressources.
    static let resourcesDrawerWidth: CGFloat = 396
    /// Colonne de transcription du mode séance.
    static let sessionTranscriptWidth: CGFloat = 400
}

private extension Color {
    /// Couleur depuis un littéral hexadécimal `0xRRGGBB`, pour transcrire la
    /// table des jetons telle quelle.
    ///
    /// Volontairement **privée au fichier** : c'est `One2OneTokens.swift` qui a
    /// le droit de nommer une couleur, pas le reste de l'application. Si un jour
    /// cette contrainte doit sauter, ce sera une décision explicite, pas un
    /// effet de bord.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
