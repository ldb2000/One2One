import SwiftUI

/// La barre d'onglets de l'écran projet (capture
/// `1d-ecran-projet-pilotage.png`) : six onglets de 13 pt, écart 22, filet
/// `cardBorder` en dessous, soulignement de 2 px `action` sur l'actif.
///
/// **L'onglet est dans la route**, pas dans un `@State` : ouvrir un projet
/// « sur l'onglet Actions » est une navigation, et c'est ce que
/// `MainRoute.project(_:_:)` porte depuis le lot 0. Changer d'onglet appelle
/// `MainRouter.switchTab(_:)`, qui remplace la route **sans** empiler
/// l'histoire : parcourir six onglets ne doit pas coûter six « retour ».
struct ProjectTabs: View {

    // MARK: - Mesures du handoff §1d

    static let ecart: CGFloat = 22
    static let taille: CGFloat = 13
    static let tailleBadge: CGFloat = 10.5
    static let epaisseurSoulignement: CGFloat = 2
    static let margeBasse: CGFloat = 9

    /// Le badge d'un onglet : le nombre d'actions ouvertes, le nombre de mails
    /// rattachés, et rien pour les quatre autres.
    ///
    /// Fonction pure et testée : c'est la seule règle de cette barre, et un
    /// badge faux se remarque moins qu'un onglet manquant.
    static func badge(_ onglet: ProjectTab, etat: ProjectPilotageState) -> Int? {
        switch onglet {
        case .actions: return etat.openActions > 0 ? etat.openActions : nil
        case .mails:   return etat.mailCount > 0 ? etat.mailCount : nil
        default:       return nil
        }
    }

    /// Le badge des actions est en `actionBg`/`actionInk` — il compte des
    /// engagements ; celui des mails est neutre.
    static func fondDeBadge(_ onglet: ProjectTab) -> Color {
        onglet == .actions ? One2OneToken.actionBg : One2OneToken.hair
    }

    static func encreDeBadge(_ onglet: ProjectTab) -> Color {
        onglet == .actions ? One2OneToken.actionInk : One2OneToken.ink4
    }

    // MARK: - Entrées

    let courant: ProjectTab
    let etat: ProjectPilotageState
    let onChoisir: (ProjectTab) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.ecart) {
            ForEach(ProjectTab.allCases, id: \.self) { onglet in
                bouton(onglet)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.cardBorder).frame(height: 1)
        }
    }

    private func bouton(_ onglet: ProjectTab) -> some View {
        let actif = onglet == courant
        return Button { onChoisir(onglet) } label: {
            HStack(spacing: 6) {
                Text(onglet.label)
                    .font(.plexSans(Self.taille, actif ? .medium : .regular))
                    .foregroundStyle(actif ? One2OneToken.ink1 : One2OneToken.ink4)
                if let compte = Self.badge(onglet, etat: etat) {
                    Text("\(compte)")
                        .font(.plexMono(Self.tailleBadge, .medium))
                        .foregroundStyle(Self.encreDeBadge(onglet))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Self.fondDeBadge(onglet)))
                }
            }
            .padding(.bottom, Self.margeBasse)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(actif ? One2OneToken.action : .clear)
                    .frame(height: Self.epaisseurSoulignement)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
