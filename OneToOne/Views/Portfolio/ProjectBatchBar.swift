import SwiftUI

/// La barre d'actions en lot sur une sélection de projets (décision **D15**).
///
/// **Extraite de `Sidebar.multiSelectBar`**, dont elle reprend les six
/// commandes — phase, statut, entité, archiver, supprimer, tout désélectionner
/// — sur les jetons `One2OneToken` et avec des libellés accentués (l'original
/// écrivait « 3 projet(s) selectionne(s) » et « Tout deselect. »). La barre
/// latérale et le Portfolio l'affichent tous deux ; les actions passent par
/// `ProjectBatchActions`.
///
/// **La suppression demande confirmation.** L'original supprimait sans
/// question, et les relations de `Project` sont en `.cascade` : réunions
/// rattachées, jalons, actions, mails partent avec.
///
/// Le lot 6 n'aura rien à ajouter pour « Déplacer vers une entité » : c'est le
/// menu Entité qui est déjà là.
struct ProjectBatchBar: View {

    // MARK: - Libellés

    /// « 3 projets sélectionnés », au singulier près.
    static func titre(_ nombre: Int) -> String {
        "\(nombre) projet\(nombre <= 1 ? "" : "s") sélectionné\(nombre <= 1 ? "" : "s")"
    }

    static let toutDeselectionner = "Tout désélectionner"
    static let phaseLibelle = "Phase"
    static let statutLibelle = "Statut"
    static let entiteLibelle = "Entité"
    /// Le libellé que le lot 6 emploiera pour le glisser-déposer retiré : c'est
    /// le même menu.
    static let deplacerVersEntite = "Déplacer vers une entité"
    static let aucuneEntite = "Aucune entité"
    static let archiver = "Archiver"
    static let supprimer = "Supprimer"

    /// Le message de la confirmation de suppression.
    static func messageSuppression(_ nombre: Int) -> String {
        "Supprimer \(nombre) projet\(nombre <= 1 ? "" : "s") ?"
            + " Leurs réunions, jalons, actions et mails rattachés partent avec."
    }

    /// Corps des libellés : la mesure « méta » du handoff.
    static let taille: CGFloat = 12

    // MARK: - Entrées

    let nombre: Int
    let entites: [Entity]
    let deselectionner: () -> Void
    let changerPhase: (String) -> Void
    let changerStatut: (String) -> Void
    let changerEntite: (Entity?) -> Void
    let archiverAction: () -> Void
    let supprimerAction: () -> Void

    @State private var confirmationSuppression = false

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.titre(nombre))
                .font(.plexSans(Self.taille, .semibold))
                .foregroundStyle(One2OneToken.actionInk)

            Button(action: deselectionner) {
                Text(Self.toutDeselectionner)
                    .font(.plexSans(Self.taille))
                    .foregroundStyle(One2OneToken.action)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            menu(Self.phaseLibelle) {
                ForEach(ProjectPhase.allLabels, id: \.self) { phase in
                    Button(phase) { changerPhase(phase) }
                }
            }
            menu(Self.statutLibelle) {
                ForEach(ProjectStatus.allLabels, id: \.self) { statut in
                    Button(statut) { changerStatut(statut) }
                }
            }
            menu(Self.entiteLibelle) {
                Button(Self.aucuneEntite) { changerEntite(nil) }
                if !entites.isEmpty { Divider() }
                ForEach(entites) { entite in
                    Button(entite.name) { changerEntite(entite) }
                }
            }

            bouton(Self.archiver, teinte: One2OneToken.warnInk, fond: One2OneToken.warnBg,
                   action: archiverAction)
            bouton(Self.supprimer, teinte: One2OneToken.reportInk, fond: One2OneToken.reportBg) {
                confirmationSuppression = true
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(One2OneToken.actionBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
        .confirmationDialog(Self.messageSuppression(nombre),
                            isPresented: $confirmationSuppression,
                            titleVisibility: .visible) {
            Button(Self.supprimer, role: .destructive) { supprimerAction() }
            Button("Annuler", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func menu<Contenu: View>(_ libelle: String,
                                     @ViewBuilder contenu: () -> Contenu) -> some View {
        Menu {
            contenu()
        } label: {
            HStack(spacing: 3) {
                Text(libelle)
                    .font(.plexSans(Self.taille, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundStyle(One2OneToken.ink4)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(One2OneToken.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func bouton(_ libelle: String,
                        teinte: Color,
                        fond: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(libelle)
                .font(.plexSans(Self.taille, .medium))
                .foregroundStyle(teinte)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(fond)
                )
        }
        .buttonStyle(.plain)
    }
}
