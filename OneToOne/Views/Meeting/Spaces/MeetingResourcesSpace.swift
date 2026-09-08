import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// L'espace `Ressources` (spec §1.1, §4.1).
///
/// **Le même contenu que le tiroir, en pleine largeur** : la spec l'exige
/// (« Espace `Ressources` sans tiroir = même contenu en pleine largeur »), et
/// c'est `ResourcesPanel` qui le porte, une fois. Le contenu provisoire du
/// lot 1 — l'ancien onglet Documents de `MeetingView`, une liste de lignes
/// avec un menu `⋯` — est retiré : ses vignettes, ses filtres et son pied
/// arrivent avec le lot 6.
///
/// Cette vue ne fait plus que trois choses : demander la migration paresseuse
/// des pièces (D5), assembler les `ResourceItem`, et brancher le coordinateur.
struct MeetingResourcesSpace: View {
    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    /// Ouvre le sélecteur de fichiers, porté par `MeetingView` (un seul
    /// `.fileImporter` par hiérarchie, cf. `MeetingView.FileImportTarget`).
    let onImport: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isDropTargeted = false

    private var coordinateur: ResourceCoordinator {
        ResourceCoordinator(meeting: meeting,
                            context: context,
                            state: screen.resources,
                            playhead: screen.playhead)
    }

    var body: some View {
        ResourcesPanel(items: ResourceItem.all(for: meeting),
                       state: screen.resources,
                       actions: coordinateur.tileActions(),
                       reportOptions: Binding(
                           get: { meeting.reportAttachmentOptions },
                           set: { meeting.reportAttachmentOptions = $0 }),
                       participantCount: MeetingSharingState.presentCount(for: meeting),
                       projectName: meeting.project?.name,
                       onImport: onImport,
                       onPaste: { coordinateur.pasteFromClipboard() },
                       onSaveOptions: { try? context.save() },
                       onClose: nil,
                       isDropTargeted: isDropTargeted)
            .background(One2OneToken.bgCanvas)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                coordinateur.handleDrop(providers)
            }
            .onAppear {
                // Migration paresseuse (D5) : c'est ici, à la première
                // ouverture de l'espace, et non au lancement de l'app.
                coordinateur.migrateIfNeeded()
            }
    }
}
