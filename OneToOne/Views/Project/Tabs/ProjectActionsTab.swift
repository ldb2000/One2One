import SwiftUI
import SwiftData

/// L'onglet « Actions » de l'écran projet : les actions du projet, ouvertes
/// d'abord, cochables sur place.
///
/// **Et non `ActionsListView` filtrée.** Cet écran-là porte ses filtres en
/// `@State` privés (portée, statut, projet, entité, collaborateur, échéance)
/// et n'expose aucun point d'entrée : le contraindre à un projet demanderait
/// soit un paramètre qui traverse quinze propriétés d'état, soit un réglage
/// posé depuis l'extérieur — deux hacks. La liste ci-dessous montre ce que la
/// capture montre, aux jetons, et « Tout voir » du Pilotage y mène.
struct ProjectActionsTab: View {

    static let vide = "Aucune action sur ce projet."
    static let titreOuvertes = "ACTIONS OUVERTES"
    static let titreTerminees = "TERMINÉES"

    static let tailleTitre: CGFloat = 13
    static let tailleSousLigne: CGFloat = 11.5
    static let tailleEcheance: CGFloat = 11

    let ouvertes: [ProjectPilotageState.ActionRow]
    let terminees: [ProjectPilotageState.ActionRow]
    let onBasculer: (ProjectPilotageState.ActionRow) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PilotageMetrics.ecartCartes) {
                if ouvertes.isEmpty && terminees.isEmpty {
                    Text(Self.vide)
                        .font(.plexSans(12.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .padding(.vertical, 12)
                }
                if !ouvertes.isEmpty {
                    carte(Self.titreOuvertes, lignes: ouvertes, cochees: false)
                }
                if !terminees.isEmpty {
                    carte(Self.titreTerminees, lignes: terminees, cochees: true)
                }
            }
            .padding(.horizontal, PilotageTab.margeH)
            .padding(.top, PilotageTab.margeHaute)
            .padding(.bottom, PilotageTab.margeBasse)
        }
    }

    private func carte(_ titre: String,
                       lignes: [ProjectPilotageState.ActionRow],
                       cochees: Bool) -> some View {
        PilotageCard(marges: nil) {
            PilotageCardHeader(titre: titre)
            ForEach(Array(lignes.enumerated()), id: \.element.id) { rang, ligne in
                row(ligne, cochee: cochees).pilotageRowSeparator(rang < lignes.count - 1)
            }
        }
    }

    private func row(_ ligne: ProjectPilotageState.ActionRow, cochee: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { onBasculer(ligne) } label: {
                Group {
                    if cochee {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: OpenActionsCard.cote))
                            .foregroundStyle(One2OneToken.ok)
                    } else {
                        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                         style: .continuous)
                            .strokeBorder(ligne.enRetard ? One2OneToken.report
                                                         : One2OneToken.dashedBorder,
                                          lineWidth: OpenActionsCard.epaisseurCase)
                            .frame(width: OpenActionsCard.cote, height: OpenActionsCard.cote)
                    }
                }
                .frame(width: OpenActionsCard.cote, height: OpenActionsCard.cote)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(ligne.title)
                    .font(.plexSans(Self.tailleTitre))
                    .foregroundStyle(cochee ? One2OneToken.ink4 : One2OneToken.ink1)
                    .strikethrough(cochee, color: One2OneToken.ink4)
                    .lineLimit(1)
                Text(ligne.sousLigne)
                    .font(.plexSans(Self.tailleSousLigne))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ligne.echeanceLabel)
                .font(.plexMono(Self.tailleEcheance, .medium))
                .foregroundStyle(cochee ? One2OneToken.inkMuted
                                        : OpenActionsCard.teinteDEcheance(ligne.echeance))
                .fixedSize()
        }
        .padding(.horizontal, PilotageMetrics.margeH)
        .padding(.vertical, 9)
    }
}
