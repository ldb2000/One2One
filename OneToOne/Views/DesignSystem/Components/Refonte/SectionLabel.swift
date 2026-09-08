import SwiftUI

/// Libellé de section : « MES NOTES », « À ASSIGNER — 9 », « CAPTURÉ CETTE
/// SÉANCE ». Plex Mono 600 à 9,5 px, majuscules, interlettrage 0,07 em
/// (spec §1.2).
///
/// La couleur suit le thème : `ink/4` sur papier, `dark/ink4` en séance. Jamais
/// `ink/muted` — sous 12 px il faut 4,5:1, et `ink/muted` ne l'atteint pas.
struct SectionLabel: View {
    let texte: String
    @Environment(\.one2OneTheme) private var theme

    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.plexMono(9.5, .semibold))
            .tracking(9.5 * 0.07)
            .textCase(.uppercase)
            .foregroundStyle(theme.colors.ink4)
    }
}

#Preview("SectionLabel — papier") {
    VStack(alignment: .leading, spacing: 12) {
        SectionLabel("mes notes")
        SectionLabel("à assigner — 9")
        SectionLabel("capturé cette séance")
    }
    .padding(20)
    .background(One2OneToken.surface)
}

#Preview("SectionLabel — séance") {
    VStack(alignment: .leading, spacing: 12) {
        SectionLabel("temps")
        SectionLabel("transcription live")
        SectionLabel("assistant")
    }
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
