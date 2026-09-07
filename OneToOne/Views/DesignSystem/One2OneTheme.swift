import SwiftUI

/// Couleurs résolues d'un thème d'écran de la refonte.
///
/// Une vue refondue lit `\.one2OneTheme` et n'utilise que ces champs : elle
/// devient ainsi indifférente à la palette dans laquelle elle est affichée. Les
/// vues qui n'ont qu'une seule palette possible peuvent continuer à lire
/// `One2OneToken` directement.
struct One2OneColors: Sendable {
    /// Fond général de l'écran.
    let base: Color
    /// Fond de la zone de travail, ou de la colonne de transcription en séance.
    let canvas: Color
    /// Carte au repos.
    let card: Color
    /// Carte active : segment survolé ou sélectionné.
    let cardActive: Color
    /// Pilule et champ de saisie.
    let pill: Color
    let ink1: Color
    let ink2: Color
    let ink3: Color
    /// Libellé mono. Jamais remplacé par une encre plus claire : sous 12 px il
    /// faut 4,5:1 (spec §1.2).
    let ink4: Color
    let action: Color
    let report: Color
    let warn: Color
    let ok: Color
    let hair: Color
    let cardBorder: Color

    // MARK: - Champs ajoutés au lot 4
    //
    // Les composants des lots 2 et 3 lisaient encore `One2OneToken` en direct
    // pour ces sept rôles : la colonne de notes et la colonne de transcription
    // du mode séance en avaient besoin. Ajoutés ici, et non écrits dans les
    // vues, pour que la règle « seul `One2OneTokens.swift` nomme une couleur »
    // reste vraie — donc vérifiable.

    /// Sous-zone d'une carte, ligne de tableau alternée. Fond du bouton
    /// secondaire au repos.
    let surfaceAlt: Color
    /// Contour d'un bouton secondaire ou d'un champ.
    let strongBorder: Color
    /// Placeholder et métadonnée. Jamais sous 11,5 px.
    let inkMuted: Color
    /// Encre d'un texte posé sur `actionBg` (lien, pilule d'action active).
    let actionInk: Color
    /// Fond doux d'un élément d'action (segment survolé, pilule `Suivre`).
    let actionBg: Color
    /// Encre d'un texte de décision ou de rapport sur son fond doux.
    let reportInk: Color
    /// Encre d'un texte de risque sur son fond doux.
    let warnInk: Color
}

/// Thème d'écran de la refonte.
///
/// `.session` n'est **pas** le mode sombre du système : les `WindowGroup` de
/// `OneToOneApp` épinglent `.preferredColorScheme(.light)` et ce lot n'y touche
/// pas. C'est un thème local, choisi par l'écran qui s'affiche — le mode séance
/// plein écran de la capture 1b.
enum One2OneTheme: String, CaseIterable, Sendable {
    case paper
    case session

    var colors: One2OneColors {
        switch self {
        case .paper:
            One2OneColors(
                base: One2OneToken.bgApp,
                canvas: One2OneToken.bgCanvas,
                card: One2OneToken.surface,
                cardActive: One2OneToken.actionBg,
                pill: One2OneToken.surface,
                ink1: One2OneToken.ink1,
                ink2: One2OneToken.ink2,
                ink3: One2OneToken.ink3,
                ink4: One2OneToken.ink4,
                action: One2OneToken.action,
                report: One2OneToken.report,
                warn: One2OneToken.warn,
                ok: One2OneToken.ok,
                hair: One2OneToken.hair,
                cardBorder: One2OneToken.cardBorder,
                surfaceAlt: One2OneToken.surfaceAlt,
                strongBorder: One2OneToken.strongBorder,
                inkMuted: One2OneToken.inkMuted,
                actionInk: One2OneToken.actionInk,
                actionBg: One2OneToken.actionBg,
                reportInk: One2OneToken.reportInk,
                warnInk: One2OneToken.warnInk
            )
        case .session:
            One2OneColors(
                base: One2OneToken.darkBase,
                canvas: One2OneToken.darkTranscript,
                card: One2OneToken.darkCard,
                cardActive: One2OneToken.darkCardActive,
                pill: One2OneToken.darkPill,
                ink1: One2OneToken.darkInk1,
                ink2: One2OneToken.darkInk2,
                ink3: One2OneToken.darkInk3,
                ink4: One2OneToken.darkInk4,
                action: One2OneToken.darkAction,
                report: One2OneToken.darkReport,
                warn: One2OneToken.darkWarn,
                // La palette dark/* de la spec §1.2 ne publie pas d'encre
                // « tenu » : le vert de la palette claire n'est pas lisible sur
                // `#1c1a17`, et l'action bleu clair sert déjà de teinte
                // positive dans la capture 1b (bouton `＋ Action`).
                ok: One2OneToken.darkAction,
                // Filets sur fond sombre : les opacités de noir de la palette
                // claire y sont invisibles. Nommées ici, dans le système de
                // conception, et non dans une vue.
                hair: Color.white.opacity(0.07),
                cardBorder: Color.white.opacity(0.09),
                // Une « sous-zone » sur fond sombre est un cran **plus
                // claire** que la carte, alors qu'elle est plus sombre que la
                // surface en clair : c'est le rapport au fond qui compte, pas
                // le sens de la variation.
                surfaceAlt: One2OneToken.darkCard,
                strongBorder: Color.white.opacity(0.14),
                inkMuted: One2OneToken.darkInk4,
                // Sur fond sombre, l'encre d'action **est** l'accent : il n'y a
                // pas de version « profonde » à poser sur un fond doux, la
                // palette `dark/*` n'en publie pas.
                actionInk: One2OneToken.darkAction,
                actionBg: One2OneToken.darkPill,
                reportInk: One2OneToken.darkReport,
                warnInk: One2OneToken.darkWarn
            )
        }
    }
}

private struct One2OneThemeKey: EnvironmentKey {
    static let defaultValue: One2OneTheme = .paper
}

extension EnvironmentValues {
    /// Thème de la refonte pour la sous-arborescence. `.paper` par défaut : un
    /// écran qui ne dit rien est un écran clair.
    var one2OneTheme: One2OneTheme {
        get { self[One2OneThemeKey.self] }
        set { self[One2OneThemeKey.self] = newValue }
    }
}

extension View {
    /// Applique un thème de la refonte à la sous-arborescence.
    func one2OneTheme(_ theme: One2OneTheme) -> some View {
        environment(\.one2OneTheme, theme)
    }
}
