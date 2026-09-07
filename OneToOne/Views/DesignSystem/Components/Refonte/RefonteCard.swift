import SwiftUI

/// Carte de la refonte : rayon 7, contour `border/card`, padding 9–13
/// (spec §1.2). Suit le thème, donc utilisable telle quelle en mode séance.
///
/// Nommée `RefonteCard` et non `Card` : l'application porte déjà plusieurs
/// notions de carte (cartes de dashboard, `FicheTokens`), et ce lot ne les
/// remplace pas.
struct RefonteCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.one2OneTheme) private var theme

    init(padding: CGFloat = One2OneToken.cardPaddingMax, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(theme.colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(theme.colors.cardBorder, lineWidth: 1)
            )
    }
}

#Preview("RefonteCard — papier") {
    VStack(spacing: One2OneToken.cardGap) {
        RefonteCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("présence")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("100 %")
                        .font(.plexSans(22, .semibold))
                        .foregroundStyle(One2OneToken.ink1)
                    MonoMeta("6/6")
                }
            }
        }
        RefonteCard(padding: One2OneToken.cardPaddingMin) {
            Text("Padding minimal, 9 px")
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
        }
    }
    .frame(width: 240)
    .padding(20)
    .background(One2OneToken.bgCanvas)
}

#Preview("RefonteCard — séance") {
    RefonteCard {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("capturé cette séance")
            Text("4 actions")
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.darkInk2)
        }
    }
    .frame(width: 240)
    .padding(20)
    .background(One2OneToken.darkBase)
    .one2OneTheme(.session)
}
