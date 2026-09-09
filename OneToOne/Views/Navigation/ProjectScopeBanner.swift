import SwiftUI

/// Le bandeau qui dit qu'une liste est **restreinte aux projets**.
///
/// Les routes `MainRoute.projectMeetings` et `.projectActions` montent les
/// listes existantes avec un filtre initial (décision **D0**, §4 de la spec :
/// « listes existantes filtrées »). Sans marque à l'écran, une liste amputée
/// de la moitié de ses lignes se lit comme une liste vide : c'est le même
/// écran que « Réunions » ou « Actions », et rien ne dirait pourquoi il en
/// manque.
///
/// Une ligne, pas une chip : le filtre n'est **pas** effaçable — il vient de
/// la route, et on en sort en changeant d'entrée de barre latérale, ce que la
/// ligne dit.
struct ProjectScopeBanner: View {

    /// Le libellé de l'entrée de barre latérale qui a mené ici.
    static let reunions = "Réunions liées à un projet"
    /// Idem pour les actions.
    static let actions = "Actions portées par un projet"
    /// Comment en sortir — un filtre qu'on ne peut pas retirer doit le dire.
    static let sortie = "Choisir « Réunions » ou « Actions » dans la barre latérale pour tout voir"

    let libelle: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(One2OneToken.action)
            Text(libelle)
                .font(.plexSans(12, .medium))
                .foregroundStyle(One2OneToken.actionInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(One2OneToken.actionBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
        .help(Self.sortie)
    }
}
