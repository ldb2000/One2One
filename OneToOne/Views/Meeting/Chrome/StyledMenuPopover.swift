import SwiftUI

/// Un menu de la barre du haut, **rendu en SwiftUI** et non par AppKit
/// (retour d'usage du 2026-09-08, défaut n° 3).
///
/// Pourquoi il existe. `Menu { … }` ouvre un `NSMenu` : ses lignes sont dessinées
/// par AppKit, avec la fonte système, ses tailles et son surlignage bleu. Aucun
/// `.font(.plexSans(…))` posé sur le contenu d'un `Menu` n'a d'effet — c'est le
/// même piège que `NSTextField` avec le titre de réunion, et il ne se voit pas
/// sur une capture d'écran tant que le menu est fermé. Les deux menus de la
/// barre — le type de réunion et le template de rapport — sortaient donc en
/// fonte système au milieu d'un écran entièrement en Plex.
///
/// Ce que ce composant est. Le même objet que le sélecteur de source de la
/// capture `4a` (`CaptureSourcePopover`) : un `popover` SwiftUI, surface
/// `surface`, bordure `border/card`, rayon de panneau flottant (§1.2 :
/// « 10 — panneau flottant »), lignes en `plexSans(12)`, ligne active sur
/// `accent/action bg`. `Esc` et un clic dehors le referment, comme tout
/// popover ; la sélection se fait au clic et referme.
///
/// Ce qu'il n'est pas. Le menu `⋯` **reste** un `Menu` natif : c'est un menu
/// contextuel système, avec des sous-menus, des rôles destructifs et des
/// raccourcis — là, la fonte système est le bon registre, et le refaire à la
/// main coûterait toute sa mécanique pour rien.
struct StyledMenuPopover: View {

    /// Largeur du panneau (§2.1 : les menus de la barre sont étroits ; 260 px
    /// laissent tenir `Architecture technique d'équipe` sans ellipsis).
    static let width: CGFloat = 260
    /// Taille des lignes : corps de §1.2.
    static let rowLabelSize: CGFloat = 12

    /// Une ligne du menu.
    struct Item: Identifiable {
        let id: String
        let libelle: String
        /// Symbole SF de tête. `nil` pour une ligne sans icône.
        var symbole: String?
        /// La ligne porte-t-elle la valeur courante ?
        var selectionnee: Bool = false
        /// Un filet `border/hair` la précède-t-elle ? C'est ce qui détache
        /// `Auto (selon type)` de la liste des templates.
        var separateurAvant: Bool = false
        let action: () -> Void
    }

    /// Libellé mono d'en-tête (§1.2 : Plex Mono 600 · 9,5, majuscules).
    /// `nil` pour un menu qui se passe de titre.
    let titre: String?
    let items: [Item]
    /// Referme le popover. Appelé après chaque sélection : un menu qui reste
    /// ouvert sur le choix qu'on vient de faire donne l'impression que le clic
    /// n'a pas pris.
    let fermer: () -> Void

    @State private var survolee: String?

    init(titre: String? = nil,
         items: [Item],
         fermer: @escaping () -> Void) {
        self.titre = titre
        self.items = items
        self.fermer = fermer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let titre {
                Text(titre)
                    .sectionLabel()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            ForEach(items) { item in
                if item.separateurAvant {
                    Rectangle()
                        .fill(One2OneToken.hair)
                        .frame(height: 1)
                        .padding(.vertical, 4)
                }
                ligne(item)
            }
        }
        .padding(.vertical, titre == nil ? 6 : 0)
        .padding(.bottom, titre == nil ? 0 : 6)
        .frame(width: Self.width, alignment: .leading)
        .background(One2OneToken.surface)
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPanel, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }

    /// Une ligne : icône optionnelle, libellé, coche de sélection. Le fond
    /// `accent/action bg` marque à la fois le survol et la sélection — deux
    /// teintes différentes se liraient comme deux états concurrents.
    private func ligne(_ item: Item) -> some View {
        let actif = item.selectionnee || survolee == item.id
        return Button {
            item.action()
            fermer()
        } label: {
            HStack(spacing: 8) {
                if let symbole = item.symbole {
                    Image(systemName: symbole)
                        .font(.system(size: 10))
                        .foregroundStyle(item.selectionnee ? One2OneToken.actionInk : One2OneToken.ink4)
                        .frame(width: 14, alignment: .center)
                }
                Text(item.libelle)
                    .font(.plexSans(Self.rowLabelSize))
                    .foregroundStyle(item.selectionnee ? One2OneToken.actionInk : One2OneToken.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if item.selectionnee {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(One2OneToken.action)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(actif ? One2OneToken.actionBg : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survolee = $0 ? item.id : (survolee == item.id ? nil : survolee) }
        .accessibilityAddTraits(item.selectionnee ? [.isSelected] : [])
    }
}

#Preview("Menu de type") {
    StyledMenuPopover(
        titre: "Type de réunion",
        items: [
            .init(id: "global", libelle: "Global", symbole: "square.grid.2x2", action: {}),
            .init(id: "archi", libelle: "Architecture technique d'équipe",
                  symbole: "cpu", selectionnee: true, action: {}),
            .init(id: "new", libelle: "Nouvelle réunion…", symbole: "plus",
                  separateurAvant: true, action: {}),
        ],
        fermer: {}
    )
    .padding(20)
    .background(One2OneToken.bgCanvas)
}
