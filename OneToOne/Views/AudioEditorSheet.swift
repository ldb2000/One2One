import SwiftUI
import SwiftData

enum AudioEditMode: String, Identifiable {
    case trim, split
    var id: String { rawValue }
}

/// Modal d'édition audio. Mode `.trim` rewrites the original WAV in place;
/// mode `.split` produces two files and reassigns part B to another meeting
/// (split flow implémenté à la tâche suivante T11).
struct AudioEditorSheet: View {
    let meeting: Meeting
    let mode: AudioEditMode
    let onFinish: (_ trimmedOrSplit: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var markerSeconds: Double = 0
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let url = meeting.wavFileURL {
                AudioWaveformEditor(url: url, markerSeconds: $markerSeconds)
            } else {
                Text("Fichier audio introuvable.").foregroundStyle(.red)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 360)
    }

    private var header: some View {
        HStack {
            Image(systemName: mode == .trim ? "scissors" : "rectangle.split.2x1")
            Text(mode == .trim ? "Couper le début" : "Diviser l'enregistrement")
                .font(.headline)
            Spacer()
            Button("Fermer") { dismiss() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch mode {
        case .trim:
            HStack {
                Spacer()
                Button(role: .destructive) {
                    Task { await runTrim() }
                } label: {
                    Label("Couper le début à \(format(markerSeconds))",
                          systemImage: "scissors")
                }
                .disabled(markerSeconds < 1 || isWorking)
            }
        case .split:
            Text("Étape 2 — choix de la cible — implémentée à la tâche suivante.")
                .foregroundStyle(.secondary)
        }
    }

    private func runTrim() async {
        guard let url = meeting.wavFileURL else { return }
        isWorking = true
        defer { isWorking = false }
        let queue = JobQueue.shared
        _ = queue.start(
            kind: .audioEdit,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title + " · trim"
        ) { _ in
            do {
                try await AudioFileEditor.trim(url: url, from: markerSeconds)
                await MainActor.run {
                    meeting.durationSeconds = Int(AudioFileEditor.duration(url: url))
                    invalidateTranscriptArtifacts(of: meeting, in: context)
                    try? context.save()
                    onFinish(true)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
                throw error
            }
        }
    }

    private func format(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

/// Vide les artefacts de transcription après une édition audio. Les
/// `ReportRevision` sont conservées mais devront être régénérées par
/// l'utilisateur. Helper file-level pour réutilisation par T11.
func invalidateTranscriptArtifacts(of meeting: Meeting, in context: ModelContext) {
    meeting.rawTranscript = ""
    meeting.mergedTranscript = ""
    meeting.summary = ""
    for seg in meeting.transcriptSegments { context.delete(seg) }
}
