import SwiftUI

/// Conteneur commun d'une carte du dashboard réunion : en-tête (poignée en mode
/// édition + icône + titre + compteur/badge + actions) puis contenu.
struct DashboardCard<HeaderActions: View, Content: View>: View {
    let title: String
    let systemImage: String
    /// Petit compteur/badge affiché à droite du titre (ex. « 42 »), optionnel.
    var badge: String? = nil
    /// Mode édition (affiche la poignée de drag ⠿).
    var isEditing: Bool = false
    @ViewBuilder var headerActions: () -> HeaderActions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Glisser pour réordonner")
                }
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                if let badge {
                    Text(badge)
                        .font(MeetingTheme.meta)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                Spacer()
                headerActions()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            content()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(MeetingTheme.surfaceCream)
                .shadow(color: MeetingTheme.softShadow, radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(MeetingTheme.hairline, lineWidth: 0.5)
        )
    }
}
