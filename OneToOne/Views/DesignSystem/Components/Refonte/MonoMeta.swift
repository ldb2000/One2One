import SwiftUI

/// Métadonnée monospace : « Cohere MLX », « auto · 2 min », « Ajouté par ·
/// 09:41 · 1,2 Mo ». Plex Mono 10 px, encre `ink/4` — ou `ink/3` quand la
/// métadonnée porte une valeur qu'on lit vraiment (`emphase`).
struct MonoMeta: View {
    let texte: String
    let emphase: Bool
    @Environment(\.one2OneTheme) private var theme

    init(_ texte: String, emphase: Bool = false) {
        self.texte = texte
        self.emphase = emphase
    }

    var body: some View {
        Text(texte)
            .font(.plexMono(10, .medium))
            .foregroundStyle(emphase ? theme.colors.ink3 : theme.colors.ink4)
    }
}

#Preview("MonoMeta — papier") {
    VStack(alignment: .leading, spacing: 8) {
        MonoMeta("Cohere MLX")
        MonoMeta("auto · 2 min")
        MonoMeta("Ajouté par Laurent · 09:41 · 1,2 Mo")
        MonoMeta("4 sept. 2026 · 9:15", emphase: true)
    }
    .padding(20)
    .background(One2OneToken.surface)
}

#Preview("MonoMeta — séance") {
    VStack(alignment: .leading, spacing: 8) {
        MonoMeta("enregistrement auto · liées au temps")
        MonoMeta("18:42 / 23:24", emphase: true)
    }
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
