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

    /// Portion **écoulée** de l'axe de la colonne temps du mode séance
    /// (spec §2.6). Ce n'est pas `accent/report` (`#b8544c`) : la spec nomme
    /// une valeur propre, plus saturée, et la capture le confirme — l'axe est
    /// nettement plus vif que le carré de la décision qu'il traverse.
    static let railElapsed = Color(hex: 0xE04B3F)

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

    /// Ombre d'un panneau qui glisse depuis la droite (fiche projet, tiroir de
    /// ressources) : `-8px 0 24px rgba(0,0,0,.07)` — spec §4.1 et §4.3. Trois
    /// jetons, parce qu'une ombre est une couleur *plus* une géométrie et que
    /// séparer les deux ferait réapparaître un littéral dans la vue.
    static let panelShadow = Color.black.opacity(0.07)
    static let panelShadowRadius: CGFloat = 24
    /// Décalage horizontal : négatif, l'ombre est portée vers la gauche, du
    /// côté de la colonne que le panneau recouvre.
    static let panelShadowOffsetX: CGFloat = -8

    /// Opacité de la colonne principale quand un panneau contextuel est ouvert
    /// (spec §4.3 : « la colonne principale passe à 55 % d'opacité et reste
    /// consultable »). C'est un dépoli, pas un blocage : la vue qui l'applique
    /// ne doit **jamais** l'accompagner d'un `allowsHitTesting(false)`.
    static let dimmedOpacity: Double = 0.55

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

    /// Sélecteur de source de capture (spec §5.1, capture `4a`).
    static let capturePopoverWidth: CGFloat = 346

    // MARK: - Pastille flottante (spec §5.4, capture `4b`)

    /// Fond de la pastille : `rgba(20,18,15,.94)` de la spec. Ce n'est **pas**
    /// `darkBase.opacity(0.94)` : la spec nomme une valeur propre, un cran plus
    /// sombre que le fond du mode séance, parce que la pastille se pose sur
    /// l'écran de quelqu'un d'autre et doit s'en détacher.
    static let pillBackground = Color(hex: 0x14120F).opacity(0.94)
    /// Ombre portée forte de la spec §5.4 : la pastille flotte au-dessus de
    /// Teams, sans ombre elle se confond avec le contenu partagé.
    static let pillShadow = Color.black.opacity(0.45)
    static let pillShadowRadius: CGFloat = 18

    static let pillWidth: CGFloat = 300
    static let pillHeight: CGFloat = 40
    /// Rayon de la pastille (spec §5.4). Supérieur à la moitié de la hauteur :
    /// la forme est une capsule, le nombre est ici pour être vérifiable.
    static let pillRadius: CGFloat = 22
    /// Marge entre la pastille et le bord de l'écran, à la magnétisation.
    static let pillInset: CGFloat = 16

    /// Mini-panneau de confirmation, `186 px` (spec §5.4).
    static let pillConfirmationWidth: CGFloat = 186
    /// Hauteur de la carte de confirmation : en-tête `CAPTURÉ · mm:ss` (12) +
    /// vignette (52) + ligne d'OCR (14) + bouton d'action (22), trois écarts de
    /// 6, deux marges internes de 10, et 6 d'écart au-dessus de la carte.
    /// Tenue ici et non dans la vue : `SessionPillPanelController` doit
    /// agrandir le panneau d'exactement autant.
    static let pillConfirmationHeight: CGFloat = 144
    /// Hauteur du bandeau du champ de note (`✎ Note`, `⌘⏎` pour créer).
    static let pillNoteHeight: CGFloat = 50
    /// Vignette de la carte de confirmation, comme dans une note (spec §5.3).
    static let pillThumbnailWidth: CGFloat = 166
    static let pillThumbnailHeight: CGFloat = 52
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
