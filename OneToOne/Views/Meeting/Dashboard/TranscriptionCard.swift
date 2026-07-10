import SwiftUI

/// Carte « Transcription » du dashboard : aperçu de la transcription en direct.
/// La détection des locuteurs se fait après l'enregistrement (diarisation batch),
/// donc « Détecter » est un affordance désactivé en direct ; « Speakers » ne fait
/// qu'afficher/masquer d'éventuels libellés de locuteur.
struct TranscriptionCard: View {
    let meeting: Meeting
    @ObservedObject private var live = LiveTranscriptionService.shared
    var isEditing: Bool = false
    /// Bascule vers l'onglet « Direct » plein écran.
    let onExpand: () -> Void

    @State private var showSpeakers: Bool = true

    /// Transcript final généré (hors enregistrement) : fusionné, sinon brut.
    private var finalTranscript: String {
        meeting.mergedTranscript.isEmpty ? meeting.rawTranscript : meeting.mergedTranscript
    }

    var body: some View {
        DashboardCard(title: "Transcription", systemImage: "waveform", isEditing: isEditing) {
            HStack(spacing: 10) {
                Toggle("Speakers", isOn: $showSpeakers)
                    .toggleStyle(.switch).controlSize(.mini)
                    .fixedSize()
                Button { } label: { Label("Détecter", systemImage: "mic") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(live.isLive)
                    .help("La détection des locuteurs s'effectue après l'enregistrement")
                Button { onExpand() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if live.isLive {
                    Label("En direct", systemImage: "circle.fill")
                        .font(.caption).foregroundColor(MeetingTheme.accentOrange)
                }
                // En direct : flux live. Sinon : transcript final généré.
                let displayed = live.isLive ? live.liveTranscript : finalTranscript
                let placeholder = live.isLive ? "En écoute…" : "Aucune transcription."
                ScrollView {
                    Text(displayed.isEmpty ? placeholder : displayed)
                        .font(.body)
                        .foregroundColor(displayed.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120, maxHeight: 200)
                if let status = live.statusMessage {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
