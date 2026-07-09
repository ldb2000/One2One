import SwiftUI

/// Panneau du transcript en direct pendant l'enregistrement. Auto-scroll vers
/// le bas au fil des ajouts. Affiché quand la transcription en direct est active.
struct LiveTranscriptPanel: View {
    @ObservedObject var live = LiveTranscriptionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundColor(live.isLive ? .red : .secondary)
                Text("Transcription en direct")
                    .font(.headline)
                if let status = live.statusMessage {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(live.liveTranscript.isEmpty ? "En écoute…" : live.liveTranscript)
                        .font(.body)
                        .foregroundColor(live.liveTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("liveBottom")
                        .padding(.vertical, 4)
                }
                .onChange(of: live.liveTranscript) { _, _ in
                    withAnimation { proxy.scrollTo("liveBottom", anchor: .bottom) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
