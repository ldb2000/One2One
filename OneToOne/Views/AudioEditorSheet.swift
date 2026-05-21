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
    @State private var splitStage: SplitStage = .pickPosition
    @State private var splitTarget: SplitTarget = .newMeeting
    @State private var showOverwriteTargetConfirm: Bool = false
    @State private var existingTargetID: PersistentIdentifier?
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]

    enum SplitStage { case pickPosition, pickTarget }
    enum SplitTarget: String, Identifiable, CaseIterable {
        case newMeeting, existing
        var id: String { rawValue }
    }

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
        .onAppear {
            cleanupStaleTmp()
        }
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
            switch splitStage {
            case .pickPosition:
                HStack {
                    Spacer()
                    Button {
                        splitStage = .pickTarget
                    } label: {
                        Label("Diviser ici (\(format(markerSeconds)))",
                              systemImage: "rectangle.split.2x1")
                    }
                    .disabled(markerSeconds < 1)
                }
            case .pickTarget:
                splitTargetForm
            }
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

    /// Supprime un éventuel `<wav>.tmp.wav` orphelin (crash pendant trim)
    /// vieux de plus de 5 minutes.
    private func cleanupStaleTmp() {
        guard let url = meeting.wavFileURL else { return }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".tmp.wav")
        guard FileManager.default.fileExists(atPath: tmp.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        if Date().timeIntervalSince(mtime) > 5 * 60 {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private func format(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }

    private var splitTargetForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Affecter le second morceau à :").font(.subheadline.bold())
            Picker("", selection: $splitTarget) {
                Text("Nouvelle réunion").tag(SplitTarget.newMeeting)
                Text("Réunion existante").tag(SplitTarget.existing)
            }
            .pickerStyle(.radioGroup)

            if splitTarget == .existing {
                Picker("Réunion", selection: Binding(
                    get: { existingTargetID },
                    set: { existingTargetID = $0 }
                )) {
                    Text("— choisir —").tag(PersistentIdentifier?.none)
                    ForEach(candidateMeetings, id: \.persistentModelID) { m in
                        Text("\(formatDate(m.date)) — \(m.title)")
                            .tag(Optional(m.persistentModelID))
                    }
                }
                .pickerStyle(.menu)
            }

            if targetHasExistingWav {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("La réunion cible a déjà un audio — il sera remplacé et supprimé du disque.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.top, 4)
            }

            HStack {
                Button("Retour") { splitStage = .pickPosition }
                Spacer()
                Button(role: .destructive) {
                    if targetHasExistingWav {
                        showOverwriteTargetConfirm = true
                    } else {
                        Task { await runSplit() }
                    }
                } label: {
                    Label("Confirmer", systemImage: "checkmark")
                }
                .disabled(isWorking ||
                          (splitTarget == .existing && existingTargetID == nil))
            }
            .padding(.top, 4)
        }
        .alert("Remplacer l'audio existant ?",
               isPresented: $showOverwriteTargetConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Remplacer", role: .destructive) {
                Task { await runSplit() }
            }
        } message: {
            Text("La réunion cible a déjà un fichier audio. Il sera supprimé du disque et remplacé par la seconde partie du split.")
        }
    }

    /// True si la cible existante a un wavFilePath non vide.
    private var targetHasExistingWav: Bool {
        guard splitTarget == .existing,
              let id = existingTargetID,
              let m = allMeetings.first(where: { $0.persistentModelID == id })
        else { return false }
        return !(m.wavFilePath ?? "").isEmpty
    }

    /// Réunions du même jour ± 1 jour, excluant la source.
    private var candidateMeetings: [Meeting] {
        let cal = Calendar.current
        let lower = cal.date(byAdding: .day, value: -1, to: meeting.date) ?? meeting.date
        let upper = cal.date(byAdding: .day, value: 1, to: meeting.date) ?? meeting.date
        return allMeetings
            .filter { $0.persistentModelID != meeting.persistentModelID }
            .filter { $0.date >= lower && $0.date <= upper }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }

    private func runSplit() async {
        guard let url = meeting.wavFileURL else { return }
        isWorking = true
        defer { isWorking = false }
        let queue = JobQueue.shared
        let cut = markerSeconds
        _ = queue.start(
            kind: .audioEdit,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title + " · split"
        ) { _ in
            do {
                let (urlA, urlB) = try await AudioFileEditor.split(url: url, at: cut)
                await MainActor.run {
                    // Part A → source meeting
                    meeting.wavFilePath = urlA.path
                    meeting.durationSeconds = Int(AudioFileEditor.duration(url: urlA))
                    invalidateTranscriptArtifacts(of: meeting, in: context)

                    // Part B → target meeting. Si la cible avait déjà un
                    // fichier wav, on le supprime du disque (sinon orphelin)
                    // avant de pointer vers la partie B.
                    let target = resolveTargetMeeting(cutSec: cut)
                    if let oldPath = target.wavFilePath,
                       !oldPath.isEmpty,
                       oldPath != urlB.path,
                       FileManager.default.fileExists(atPath: oldPath) {
                        try? FileManager.default.removeItem(atPath: oldPath)
                    }
                    target.wavFilePath = urlB.path
                    target.durationSeconds = Int(AudioFileEditor.duration(url: urlB))
                    invalidateTranscriptArtifacts(of: target, in: context)

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

    @MainActor
    private func resolveTargetMeeting(cutSec: Double) -> Meeting {
        switch splitTarget {
        case .existing:
            if let id = existingTargetID,
               let m = allMeetings.first(where: { $0.persistentModelID == id }) {
                return m
            }
            return makeNewMeeting(cutSec: cutSec)
        case .newMeeting:
            return makeNewMeeting(cutSec: cutSec)
        }
    }

    @MainActor
    private func makeNewMeeting(cutSec: Double) -> Meeting {
        let new = Meeting(
            title: "\(meeting.title) — partie 2",
            date: meeting.date.addingTimeInterval(cutSec),
            notes: ""
        )
        new.kind = meeting.kind
        new.project = meeting.project
        new.participants = meeting.participants
        context.insert(new)
        return new
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
