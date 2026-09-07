import SwiftUI

/// Le contenu du tiroir Ressources : en-tête, filtres, vignettes, zone de
/// dépôt permanente, pied `À L'ENVOI DU RAPPORT` (spec §4.1, capture
/// `3a-tiroir-ressources.png`).
///
/// **Un seul corps pour deux surfaces.** Le tiroir de 396 px superposé à la
/// séance et l'espace `Ressources` en pleine largeur montrent la même chose —
/// la spec l'exige (« Espace `Ressources` sans tiroir = même contenu en pleine
/// largeur »), et deux vues jumelles auraient divergé au premier ajustement.
/// Seule la largeur, l'ombre et le bouton de fermeture distinguent les deux
/// emballages.
struct ResourcesPanel: View {
    let items: [ResourceItem]
    let state: ResourcesState
    let actions: ResourceTileActions
    @Binding var reportOptions: AttachmentReportOptions
    let participantCount: Int
    let projectName: String?
    /// Ouvre le sélecteur de fichiers (`＋ Importer`).
    let onImport: () -> Void
    /// Colle le presse-papiers (`⌘⇧V`).
    let onPaste: () -> Void
    let onSaveOptions: () -> Void
    /// Ferme le tiroir. `nil` en pleine largeur : il n'y a rien à fermer.
    var onClose: (() -> Void)?
    /// Un glisser survole la fenêtre.
    var isDropTargeted: Bool = false

    private var visibles: [ResourceItem] {
        ResourceItem.filtered(items, by: state.filter)
    }

    private var compteurs: (seance: Int, projet: Int) {
        ResourceItem.counts(items)
    }

    private var pinnedCount: Int {
        items.filter { $0.pinnedAtT != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            filtres
            liste
            ReportAttachmentFooter(options: $reportOptions,
                                   pinnedCount: pinnedCount,
                                   participantCount: participantCount,
                                   projectName: projectName,
                                   onChange: onSaveOptions)
        }
        .background(One2OneToken.surface)
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 7) {
            Text("Ressources")
                .font(.plexSans(13, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Pill("\(compteurs.seance) séance")
            Pill("\(compteurs.projet) projet")
            Spacer(minLength: 6)
            if state.isImporting {
                ProgressView().controlSize(.small)
            }
            boutonImporter
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(One2OneToken.ink4)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Fermer le tiroir (Esc)")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// `＋ Importer`, **plein** `accent/action` : c'est la seule action
    /// primaire du tiroir, et la capture la montre pleine.
    private var boutonImporter: some View {
        Button(action: onImport) {
            Text("＋ Importer")
                .font(.plexSans(10.5, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.action)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isImporting)
        .help("Choisir un ou plusieurs fichiers ; ils sont copiés dans la séance")
    }

    // MARK: - Filtres

    private var filtres: some View {
        HStack(spacing: 2) {
            SegmentedMode(selection: Binding(get: { state.filter },
                                             set: { state.filter = $0 }),
                          options: ResourcesFilter.allCases,
                          libelle: \.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
    }

    // MARK: - Liste

    private var liste: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let erreur = state.importError, !erreur.isEmpty {
                    Text(erreur)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.reportInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if visibles.isEmpty {
                    invite
                }
                ForEach(visibles) { item in
                    ResourceTile(item: item,
                                 isPresented: state.presentedResourceID == item.id,
                                 actions: actions)
                }
                // Permanente, même quand la liste est pleine : c'est elle qui
                // rend le dépôt découvrable (spec §1.1, §4.1).
                ResourceDropZone(isTargeted: isDropTargeted,
                                 onImport: onImport,
                                 onPaste: onPaste)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
        }
        .frame(maxHeight: .infinity)
        .background(One2OneToken.bgCanvas)
    }

    /// Un filtre vide dit **quoi faire**, jamais « aucun élément » (spec §1.1).
    private var invite: some View {
        Text(Self.invite(for: state.filter))
            .font(.plexSans(11.5))
            .foregroundStyle(One2OneToken.ink4)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }

    /// Table exhaustive, sans `default` : un filtre ajouté plus tard ne compile
    /// pas tant qu'il n'a pas son invite.
    static func invite(for filtre: ResourcesFilter) -> String {
        switch filtre {
        case .seance:
            return "Aucune pièce dans cette séance. Glissez un fichier ci-dessous, ou pressez ＋ Importer."
        case .projet:
            return "Le projet n'a pas encore de document. Ceux de la fiche projet apparaîtront ici, en lecture."
        case .captures:
            return "Aucune capture. Le bouton Capture de la barre du haut en prend une de la fenêtre partagée."
        case .liens:
            return "Aucun lien. Copiez une adresse et pressez ⌘⇧V — le titre vient de l'URL, sans requête réseau."
        }
    }
}

/// Le tiroir de 396 px, **superposé** à la séance (spec §4.1 : « se superpose
/// sans démonter la séance ; la colonne principale reste interactive »).
///
/// Pas de voile sur la colonne de gauche, contrairement à la fiche projet du
/// lot 9 : on continue de prendre des notes pendant qu'on cherche un document,
/// et un voile dirait le contraire.
struct ResourcesDrawer: View {
    let items: [ResourceItem]
    let state: ResourcesState
    let actions: ResourceTileActions
    @Binding var reportOptions: AttachmentReportOptions
    let participantCount: Int
    let projectName: String?
    let onImport: () -> Void
    let onPaste: () -> Void
    let onSaveOptions: () -> Void
    var isDropTargeted: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ResourcesPanel(items: items,
                           state: state,
                           actions: actions,
                           reportOptions: $reportOptions,
                           participantCount: participantCount,
                           projectName: projectName,
                           onImport: onImport,
                           onPaste: onPaste,
                           onSaveOptions: onSaveOptions,
                           onClose: { state.close() },
                           isDropTargeted: isDropTargeted)
                .frame(width: One2OneToken.resourcesDrawerWidth)
                .overlay(alignment: .leading) {
                    Rectangle().fill(One2OneToken.cardBorder).frame(width: 1)
                }
                .shadow(color: .black.opacity(0.07), radius: 24, x: -8, y: 0)
                .transition(.move(edge: .trailing))
        }
        // La colonne principale reste cliquable : seul le tiroir capte les
        // événements, pas la bande vide à sa gauche.
        .allowsHitTesting(true)
    }
}
