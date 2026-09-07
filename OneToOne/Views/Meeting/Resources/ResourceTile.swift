import SwiftUI

/// Ce qu'une vignette du tiroir sait faire. Un seul agrégat de closures plutôt
/// que six paramètres : la liste en passe la même valeur à toutes ses lignes,
/// et ajouter une action ne remanie pas trois signatures.
struct ResourceTileActions {
    /// `À l'écran` / `Présenter` — met la pièce sous les yeux des participants.
    var present: (ResourceItem) -> Void = { _ in }
    /// `Citer` — insère la puce `◫ <nom>` dans la note courante.
    var cite: (ResourceItem) -> Void = { _ in }
    /// `Envoyer` — le partage macOS (`NSSharingServicePicker`).
    var send: (ResourceItem) -> Void = { _ in }
    /// `Ouvrir` — le navigateur pour un lien, le Finder pour un fichier.
    var open: (ResourceItem) -> Void = { _ in }
    /// `Relier` — désigner le fichier d'une pièce orpheline.
    var relink: (ResourceItem) -> Void = { _ in }
    /// Retirer la pièce de la séance.
    var delete: (ResourceItem) -> Void = { _ in }
}

/// Une vignette du tiroir Ressources (spec §4.1, capture
/// `3a-tiroir-ressources.png`).
///
/// Icône typée 34 × 40, nom en ellipsis, `Ajouté par X · hh:mm · poids`, puis
/// les actions. **La pièce présentée porte une bordure `accent/action` et son
/// bouton `À l'écran` est plein** ; les autres n'affichent que leur action
/// principale — `Présenter` pour un fichier, `Ouvrir` pour un lien. C'est ce
/// que montre la capture, et c'est ce qui garde la colonne lisible : trois
/// boutons sur chacune des vingt vignettes noierait celle qui compte.
struct ResourceTile: View {
    let item: ResourceItem
    /// La pièce est à l'écran des participants.
    let isPresented: Bool
    let actions: ResourceTileActions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ResourceTypeIcon(badge: item.badge, tone: item.badgeTone, isOrphan: item.isOrphan)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                metadataLine
                boutons
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, One2OneToken.cardPaddingMin)
        .padding(.vertical, One2OneToken.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(isPresented ? One2OneToken.actionBg2 : One2OneToken.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(isPresented ? One2OneToken.action : One2OneToken.cardBorder,
                              lineWidth: isPresented ? 1.5 : 1)
        }
        .contextMenu { menuContextuel }
    }

    // MARK: - Métadonnées

    /// `Ajouté par Sylvain · 09:22 · 84 Ko`, ou l'invite de reliaison quand le
    /// fichier a disparu : une pièce orpheline dit **quoi faire**, elle ne
    /// nomme pas le manque (spec §1.1).
    @ViewBuilder
    private var metadataLine: some View {
        if item.isOrphan {
            Button { actions.relink(item) } label: {
                Text("Fichier introuvable — relier")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.reportInk)
                    .underline()
            }
            .buttonStyle(.plain)
            .help("Désigner le fichier ; il sera copié dans la séance")
        } else {
            let texte = item.metadata()
            if !texte.isEmpty { MonoMeta(texte) }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var boutons: some View {
        HStack(spacing: 5) {
            if item.nature == .lien {
                bouton("Ouvrir", plein: false) { actions.open(item) }
            } else if item.isOrphan {
                bouton("Relier…", plein: false) { actions.relink(item) }
            } else if isPresented {
                // La pièce à l'écran est la seule à porter les trois actions :
                // c'est d'elle qu'on parle, donc c'est elle qu'on cite et
                // qu'on envoie.
                bouton("À l'écran", plein: true) { }
                bouton("Citer", plein: false) { actions.cite(item) }
                bouton("Envoyer", plein: false) { actions.send(item) }
            } else if item.isPresentable {
                bouton("Présenter", plein: false) { actions.present(item) }
            }
        }
        .padding(.top, 1)
    }

    private func bouton(_ titre: String,
                        plein: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(plein ? One2OneToken.onFilledButton : One2OneToken.ink2)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(plein ? One2OneToken.action : One2OneToken.surface)
                )
                .overlay {
                    if !plein {
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Le clic droit porte ce que la vignette n'affiche pas : les actions
    /// secondaires d'une pièce non présentée, et le retrait.
    @ViewBuilder
    private var menuContextuel: some View {
        if item.isPresentable && !isPresented {
            Button("Mettre à l'écran") { actions.present(item) }
        }
        if item.isPinnable && !item.isOrphan {
            Button("Citer dans les notes") { actions.cite(item) }
            Button("Envoyer…") { actions.send(item) }
        }
        Button(item.nature == .lien ? "Ouvrir le lien" : "Ouvrir dans le Finder") {
            actions.open(item)
        }
        if item.scope == .meeting {
            Divider()
            Button("Retirer de la séance", role: .destructive) { actions.delete(item) }
        }
    }
}

#Preview("Vignettes") {
    let base = ResourceItem(id: UUID(), origin: .pieceDeSeance(UUID()),
                            name: "Chiffrage_Marine_v3.xlsx", kind: "xlsx", nature: .fichier,
                            scope: .meeting, addedByName: "Sylvain",
                            addedAt: Date(timeIntervalSince1970: 1_788_506_520),
                            byteCount: 86_016, path: "/tmp/a.xlsx",
                            pinnedAtT: 728, citationCount: 0, isOrphan: false)
    var pdf = base
    pdf.name = "Devis_partenaire_40k.pdf"; pdf.kind = "pdf"; pdf.addedByName = ""
    pdf.citationCount = 3; pdf.pinnedAtT = nil; pdf.byteCount = 0
    var lien = base
    lien.name = "Board GitLab — épiques migration"
    lien.kind = AttachmentCopyPolicy.linkKind; lien.nature = .lien
    lien.path = "https://gitlab.example.com/board"; lien.addedByName = "Yann"
    var perdu = base
    perdu.name = "Ancien_support.pptx"; perdu.kind = "pptx"; perdu.isOrphan = true

    return VStack(spacing: 8) {
        ResourceTile(item: base, isPresented: true, actions: ResourceTileActions())
        ResourceTile(item: pdf, isPresented: false, actions: ResourceTileActions())
        ResourceTile(item: lien, isPresented: false, actions: ResourceTileActions())
        ResourceTile(item: perdu, isPresented: false, actions: ResourceTileActions())
    }
    .padding(12)
    .frame(width: One2OneToken.resourcesDrawerWidth)
    .background(One2OneToken.bgApp)
}
