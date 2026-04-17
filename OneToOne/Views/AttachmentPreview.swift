import SwiftUI
import QuickLookUI

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
