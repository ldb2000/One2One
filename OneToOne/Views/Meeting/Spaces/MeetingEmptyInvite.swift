import SwiftUI

/// L'invite qui remplace tout écran vide (spec §1.1, critère d'acceptation
/// n° 1 du chantier 1).
///
/// « Un espace sans contenu affiche une zone de dépôt active, jamais un écran
/// vide. » L'ancien écran opposait à un dossier vide un `ContentUnavailableView`
/// (« Aucun document ») qui nommait le manque sans dire quoi faire. Ici, le
/// texte est **toujours** une action : quelle commande taper, quel bouton
/// presser, où déposer.
///
/// La table `Catalogue` est exhaustive et vérifiée par un test : un espace ou
/// un mode ajouté plus tard fait échouer la suite tant qu'il n'a pas son
/// invite. C'est la seule façon de tenir un critère de cette forme (« aucune
/// zone vide ») autrement qu'à la vigilance.
struct MeetingEmptyInvite: View {

    /// Les textes d'invite, par espace et par mode.
    enum Catalogue {

        /// Les quatre cartes du bandeau d'indicateurs (spec §2.3).
        enum KPI: String, CaseIterable, Sendable {
            case presence, actions, decisions, risks
        }

        /// Invite d'un espace vide dans un mode donné.
        ///
        /// Table exhaustive, sans `default` : la seule manière que le
        /// compilateur signale un cas oublié.
        static func invite(for space: MeetingScreenModel.Space,
                           mode: MeetingScreenModel.Mode) -> (titre: String, invite: String) {
            switch (space, mode) {
            case (.meeting, .prepare):
                return ("Rien à reprendre de la dernière fois",
                        "Écrivez l'ordre du jour dans le composeur ci-dessous, ou reprenez une action reportée.")
            case (.meeting, .live):
                return ("La séance n'a encore rien retenu",
                        "Tapez dans les notes : /action, /décision ou /risque pour horodater ce qui compte.")
            case (.meeting, .review):
                return ("Rien à relire pour l'instant",
                        "Générez le rapport pour obtenir le résumé, les décisions et le tableau d'actions.")
            case (.report, .prepare):
                return ("Le rapport se génère après la séance",
                        "Passez en séance pour enregistrer, puis revenez générer le compte-rendu.")
            case (.report, .live), (.report, .review):
                return ("Aucun rapport généré",
                        "Le bouton Rapport de la barre du haut transcrit l'audio puis rédige le compte-rendu.")
            case (.resources, .prepare):
                return ("Aucun document pour préparer",
                        "Déposez ici l'ordre du jour, le support ou le compte-rendu précédent — ils seront indexés.")
            case (.resources, .live), (.resources, .review):
                return ("Aucun document dans cette séance",
                        "Déposez un fichier n'importe où sur l'écran, ou utilisez Importer pour l'ajouter.")
            }
        }

        /// Invite d'une carte d'indicateur dont le compteur vaut zéro
        /// (spec §2.3 : « jamais une carte vide »).
        static func kpiInvite(for kpi: KPI) -> String {
            switch kpi {
            case .presence:  return "Aucun participant — ＋ ajouter"
            case .actions:   return "Aucune action — /action dans les notes"
            case .decisions: return "Aucune décision — /décision dans les notes"
            case .risks:     return "Aucun risque — /risque dans les notes"
            }
        }
    }

    let titre: String
    let invite: String
    /// Libellé du bouton, `nil` si l'invite se suffit à elle-même (dépôt,
    /// commande à taper).
    var libelleAction: String?
    var action: (() -> Void)?

    init(titre: String,
         invite: String,
         libelleAction: String? = nil,
         action: (() -> Void)? = nil) {
        self.titre = titre
        self.invite = invite
        self.libelleAction = libelleAction
        self.action = action
    }

    /// Construit l'invite depuis la table, pour un espace et un mode.
    init(space: MeetingScreenModel.Space,
         mode: MeetingScreenModel.Mode,
         libelleAction: String? = nil,
         action: (() -> Void)? = nil) {
        let textes = Catalogue.invite(for: space, mode: mode)
        self.init(titre: textes.titre, invite: textes.invite,
                  libelleAction: libelleAction, action: action)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(titre)
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink2)
            Text(invite)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let libelleAction, let action {
                Button(action: action) {
                    Text(libelleAction)
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(One2OneToken.actionInk)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusPill)
                                .fill(One2OneToken.actionBg)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: 380)
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Invites d'état vide") {
    VStack(spacing: 12) {
        MeetingEmptyInvite(space: .meeting, mode: .live)
        MeetingEmptyInvite(space: .report, mode: .review,
                           libelleAction: "Générer le rapport") {}
        MeetingEmptyInvite(space: .resources, mode: .live,
                           libelleAction: "Importer…") {}
    }
    .padding(20)
    .frame(width: 640)
    .background(One2OneToken.bgCanvas)
}
