import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// L'espace `Ressources` (spec §1.1). Reprise de l'ancien onglet Documents de
/// `MeetingView`, avec deux changements que la spec impose :
///
/// 1. **La zone de dépôt est permanente**, pas seulement pendant un survol :
///    « Un espace sans contenu affiche une zone de dépôt active, jamais un
///    écran vide. » Elle reste visible même avec des documents — c'est ce qui
///    rend le dépôt découvrable.
/// 2. **Le vide porte une invite d'action** (`MeetingEmptyInvite`) et non un
///    `ContentUnavailableView` qui nommait le manque sans dire quoi faire.
///
/// Le tiroir superposé de 396 px, les filtres et les vignettes typées arrivent
/// au lot 6 ; cette vue est la version pleine largeur du même contenu, telle
/// que la spec §4.1 la prévoit (« Espace `Ressources` sans tiroir = même
/// contenu en pleine largeur »).
struct MeetingResourcesSpace: View {
    @Bindable var meeting: Meeting
    let mode: MeetingScreenModel.Mode
    /// Un import est en cours (copie + extraction + indexation).
    let isImporting: Bool
    /// Message d'erreur d'import, `nil` si tout va bien.
    let attachmentError: String?
    /// Ouvre le sélecteur de fichiers.
    let onImport: () -> Void
    /// Traite un dépôt de fichiers.
    let onDrop: ([NSItemProvider]) -> Void
    /// Ouvre la galerie de captures (pièce jointe de type `slides`).
    let onShowSlides: () -> Void
    /// Ré-indexe une pièce jointe.
    let onReindex: (MeetingAttachment) -> Void
    /// Supprime une pièce jointe.
    let onDelete: (MeetingAttachment) -> Void

    @State private var isDragging = false

    private var attachments: [MeetingAttachment] {
        meeting.attachments.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let attachmentError, !attachmentError.isEmpty {
                Text(attachmentError)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.report)
                    .padding(.horizontal, 14).padding(.bottom, 8)
            }
            if attachments.isEmpty {
                MeetingEmptyInvite(space: .resources, mode: mode,
                                   libelleAction: "Importer…", action: onImport)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(attachments) { att in
                            attachmentRow(att)
                            Rectangle().fill(One2OneToken.hair).frame(height: 1)
                        }
                    }
                }
            }
            dropZone
        }
        .background(One2OneToken.bgCanvas)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            onDrop(providers)
            return true
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 8) {
            Text("DOCUMENTS DE LA SÉANCE").sectionLabel()
            MonoMeta("\(attachments.count)")
            Spacer()
            if isImporting {
                ProgressView().controlSize(.small)
                Text("Import + indexation…")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink4)
            }
            Button(action: onImport) {
                Text("＋ Importer")
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
            .disabled(isImporting)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    // MARK: - Ligne de document

    private func attachmentRow(_ att: MeetingAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.icon(for: att.kind))
                .font(.system(size: 14))
                .foregroundStyle(One2OneToken.action)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(att.fileName)
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Chip(att.kind.uppercased(), ton: .neutre)
                    MonoMeta("\(att.chunks.count) chunks indexés")
                    if !att.extractedText.isEmpty {
                        MonoMeta("\(att.extractedText.count) car.")
                    }
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Re-indexer") { onReindex(att) }
                if att.kind == "slides" {
                    Button("Voir les captures") { onShowSlides() }
                }
                Button("Ouvrir") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: att.filePath))
                }
                Divider()
                Button("Supprimer", role: .destructive) { onDelete(att) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(One2OneToken.ink4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, One2OneToken.tableRowPaddingV)
    }

    /// Zone de dépôt **permanente** : c'est elle qui rend le dépôt découvrable,
    /// et le §1.1 la veut « active », pas révélée par le survol.
    private var dropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(isDragging ? One2OneToken.action : One2OneToken.inkMuted)
            Text(isDragging
                 ? "Relâchez pour importer dans cette séance"
                 : "Déposez un PDF, un support ou une note ici — le texte est extrait et indexé")
                .font(.plexSans(11.5))
                .foregroundStyle(isDragging ? One2OneToken.actionInk : One2OneToken.inkMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(isDragging ? One2OneToken.actionBg : One2OneToken.surfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(isDragging ? One2OneToken.action : One2OneToken.strongBorder,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .padding(12)
        .animation(.easeInOut(duration: 0.12), value: isDragging)
    }

    /// Symbole SF par type de pièce jointe. Repris tel quel de l'ancien
    /// `MeetingView.icon(for:)`.
    static func icon(for kind: String) -> String {
        switch kind {
        case "pdf":      return "doc.richtext"
        case "pptx":     return "rectangle.on.rectangle.angled"
        case "docx":     return "doc.text"
        case "xlsx":     return "tablecells"
        case "image":    return "photo"
        case "slides":   return "camera.viewfinder"
        case "markdown", "text": return "text.alignleft"
        default:         return "doc"
        }
    }
}
