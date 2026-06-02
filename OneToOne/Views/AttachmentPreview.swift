import SwiftUI
import QuickLookUI

/// Sheet d'aperçu d'une pièce jointe d'entretien (`InterviewAttachment`) :
/// en-tête + QuickLook + éditeur de commentaire. `onOpenExternally` ouvre le
/// fichier dans une app externe, `onClose` ferme la sheet et `onSave` est
/// appelé à chaque modification du commentaire.
struct AttachmentPreviewSheet: View {
    @Bindable var attachment: InterviewAttachment
    let onOpenExternally: () -> Void
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.headline)
                    Text(attachment.resolvedURL().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Ouvrir") {
                    onOpenExternally()
                }
                Button("Fermer") {
                    onClose()
                }
            }
            .padding()

            Divider()

            QuickLookPreview(url: attachment.resolvedURL())
                .frame(minHeight: 320)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Commentaires")
                    .font(.headline)
                EditableTextEditor(text: Binding(
                    get: { attachment.comment },
                    set: {
                        attachment.comment = $0
                        onSave()
                    }
                ))
                .frame(minHeight: 120)
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 620)
    }
}

/// Aperçu QuickLook d'un fichier. Gère le cycle de vie des security-scoped
/// resources (nécessaires pour accéder aux fichiers hors sandbox via un
/// bookmark) : démarre l'accès à l'ouverture/changement d'URL et le libère
/// quand l'URL change ou que la vue est démontée.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = true
        updatePreview(view)
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        updatePreview(nsView)
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        if let previewURL = nsView.previewItem as? URL {
            previewURL.stopAccessingSecurityScopedResource()
        }
    }

    private func updatePreview(_ view: QLPreviewView) {
        if let previousURL = view.previewItem as? URL, previousURL != url {
            previousURL.stopAccessingSecurityScopedResource()
        }

        _ = url.startAccessingSecurityScopedResource()
        view.previewItem = url as NSURL
    }
}

/// Variante de `AttachmentPreviewSheet` pour une pièce jointe de projet
/// (`ProjectAttachment`) : même structure (en-tête + QuickLook + commentaire)
/// mais affiche la catégorie au lieu du chemin et n'expose pas d'action
/// « ouvrir en externe ».
struct ProjectAttachmentPreviewSheet: View {
    @Bindable var attachment: ProjectAttachment
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.headline)
                    Text(attachment.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Fermer") {
                    onClose()
                }
            }
            .padding()

            Divider()

            QuickLookPreview(url: attachment.resolvedURL())
                .frame(minHeight: 320)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Commentaire")
                    .font(.headline)
                EditableTextEditor(text: Binding(
                    get: { attachment.comment },
                    set: {
                        attachment.comment = $0
                        onSave()
                    }
                ))
                .frame(minHeight: 120)
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 620)
    }
}
