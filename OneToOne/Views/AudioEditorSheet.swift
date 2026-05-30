import SwiftUI
import SwiftData

/// Mode initial à l'ouverture du sheet. L'utilisateur peut basculer entre
/// les trois modes via les onglets en tête sans fermer la sheet.
enum AudioEditMode: String, Identifiable {
    case trimStart
    case trimEnd
    case split

    var id: String { rawValue }
}

// MARK: - Shared formatters

/// Cached fr_FR "d MMM HH:mm" formatter — `DateFormatter` instantiation est
/// coûteuse et était précédemment refaite à chaque rendu de cell de Picker.
private let audioEditorDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = "d MMM HH:mm"
    return f
}()

/// `5:42` ou `1:23:45` selon que la durée dépasse l'heure. Partagé entre
/// `AudioEditorSheet` et `AudioWaveformEditor` (mêmes besoins, ex-doublon).
func formatAudioTime(_ s: Double) -> String {
    let total = Int(s.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let sec = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%d:%02d", m, sec)
}

struct AudioEditorSheet: View {
    let meeting: Meeting
    let mode: AudioEditMode
    let onFinish: (_ trimmedOrSplit: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var currentMode: AudioEditMode = .trimStart
    @State private var markerSeconds: Double = 0
    @State private var error: String?
    @State private var isWorking = false

    // Split-spécifique
    @State private var splitStage: SplitStage = .pickPosition
    @State private var splitTarget: SplitTarget = .newMeeting
    @State private var existingTargetID: PersistentIdentifier?
    @State private var showOverwriteTargetConfirm: Bool = false
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]

    enum SplitStage { case pickPosition, pickTarget }
    enum SplitTarget: String, Identifiable, CaseIterable {
        case newMeeting, existing
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            modeTabs
            if let url = meeting.wavFileURL {
                AudioWaveformEditor(
                    url: url,
                    markerSeconds: $markerSeconds,
                    mode: waveformMode
                )
            } else {
                Text("Fichier audio introuvable.").foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if currentMode == .split && splitStage == .pickTarget {
                Divider()
                splitTargetForm
            } else {
                Divider()
                bottomBar
            }
        }
        .padding(18)
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            currentMode = mode
            cleanupStaleTmp()
        }
    }

    // MARK: - Top bar (title + close)

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor)
                .font(.title2)
            Text("Édition audio")
                .font(.title3.bold())
            Text(audioFileName)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.callout)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
        }
    }

    private var audioFileName: String {
        meeting.wavFileURL?.lastPathComponent ?? ""
    }

    // MARK: - Mode tabs (segmented control)

    private var modeTabs: some View {
        HStack(spacing: 6) {
            tabButton(.trimStart, label: "Couper le début", icon: "scissors")
            tabButton(.trimEnd,   label: "Couper la fin",  icon: "scissors")
            tabButton(.split,     label: "Diviser en deux", icon: "rectangle.split.2x1")
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: AudioEditMode, label: String, icon: String) -> some View {
        let isActive = (currentMode == tab)
        Button {
            currentMode = tab
            if tab != .split { splitStage = .pickPosition }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.callout.weight(isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive
                          ? Color(nsColor: .controlBackgroundColor)
                          : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isActive ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.15),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var waveformMode: AudioWaveformEditorMode {
        switch currentMode {
        case .trimEnd:    return .trimEnd
        case .split:      return .split
        case .trimStart:  return .trimStart
        }
    }

    // MARK: - Bottom bar (stats + CTA)

    private var bottomBar: some View {
        HStack(spacing: 16) {
            statBlock(label: "Conservé",
                      value: formatAudioTime(keptDuration),
                      dotColor: Color.accentColor)
            statBlock(label: "Supprimé",
                      value: formatAudioTime(droppedDuration),
                      dotColor: Color.secondary.opacity(0.6))
            Spacer()
            primaryCTA
        }
    }

    @ViewBuilder
    private func statBlock(label: String, value: String, dotColor: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit().bold())
        }
    }

    @ViewBuilder
    private var primaryCTA: some View {
        switch currentMode {
        case .trimStart:
            trimCTAButton(label: "Couper le début à \(formatAudioTime(markerSeconds))",
                          from: markerSeconds, to: nil, jobSuffix: "trim début")
        case .trimEnd:
            trimCTAButton(label: "Couper la fin à \(formatAudioTime(markerSeconds))",
                          from: nil, to: markerSeconds, jobSuffix: "trim fin")
        case .split:
            Button {
                splitStage = .pickTarget
            } label: {
                Label("Diviser à \(formatAudioTime(markerSeconds))",
                      systemImage: "rectangle.split.2x1")
            }
            .controlSize(.large)
            .disabled(markerSeconds < 1 || markerSeconds >= totalDuration - 1 || isWorking)
        }
    }

    @ViewBuilder
    private func trimCTAButton(label: String,
                                from: Double?,
                                to: Double?,
                                jobSuffix: String) -> some View {
        Button(role: .destructive) {
            Task { await runTrim(from: from, to: to, jobSuffix: jobSuffix) }
        } label: {
            Label(label, systemImage: "checkmark")
        }
        .controlSize(.large)
        .disabled(markerSeconds < 0.5 || markerSeconds >= totalDuration - 0.5 || isWorking)
    }

    // MARK: - Stats helpers

    private var totalDuration: Double {
        Double(meeting.durationSeconds)
    }

    private var keptDuration: Double {
        switch currentMode {
        case .trimStart: return max(0, totalDuration - markerSeconds)
        case .trimEnd:          return max(0, markerSeconds)
        case .split:            return totalDuration  // les 2 parties restent
        }
    }

    private var droppedDuration: Double {
        switch currentMode {
        case .trimStart: return max(0, markerSeconds)
        case .trimEnd:          return max(0, totalDuration - markerSeconds)
        case .split:            return 0
        }
    }

    // MARK: - Trim action (unifié pour début/fin)

    private func runTrim(from: Double?, to: Double?, jobSuffix: String) async {
        guard let url = meeting.wavFileURL else { return }
        isWorking = true
        defer { isWorking = false }
        let queue = JobQueue.shared
        _ = queue.start(
            kind: .audioEdit,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title + " · \(jobSuffix)"
        ) { _ in
            do {
                try await AudioFileEditor.trim(url: url, from: from, to: to)
                await MainActor.run { self.finishTrim(url: url) }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
                throw error
            }
        }
    }

    @MainActor
    private func finishTrim(url: URL) {
        meeting.durationSeconds = Int(AudioFileEditor.duration(url: url))
        invalidateTranscriptArtifacts(of: meeting, in: context)
        try? context.save()
        onFinish(true)
        dismiss()
    }

    // MARK: - Split stage 2 (target picker)

    private var splitTargetForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Affecter le second morceau à :")
                .font(.subheadline.bold())

            Picker("", selection: $splitTarget) {
                Text("Nouvelle réunion").tag(SplitTarget.newMeeting)
                Text("Réunion existante").tag(SplitTarget.existing)
            }
            .pickerStyle(.radioGroup)

            if splitTarget == .existing {
                Picker("Réunion", selection: $existingTargetID) {
                    Text("— choisir —").tag(PersistentIdentifier?.none)
                    ForEach(candidateMeetings, id: \.persistentModelID) { m in
                        Text("\(audioEditorDateFormatter.string(from: m.date)) — \(m.title)")
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
                    Label("Confirmer la division", systemImage: "checkmark")
                }
                .controlSize(.large)
                .disabled(isWorking ||
                          (splitTarget == .existing && existingTargetID == nil))
            }
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

    private var targetHasExistingWav: Bool {
        guard splitTarget == .existing,
              let id = existingTargetID,
              let m = allMeetings.first(where: { $0.persistentModelID == id })
        else { return false }
        return !(m.wavFilePath ?? "").isEmpty
    }

    private var candidateMeetings: [Meeting] {
        let cal = Calendar.current
        let lower = cal.date(byAdding: .day, value: -1, to: meeting.date) ?? meeting.date
        let upper = cal.date(byAdding: .day, value: 1, to: meeting.date) ?? meeting.date
        let sourceID = meeting.persistentModelID
        return allMeetings.filter {
            $0.persistentModelID != sourceID && $0.date >= lower && $0.date <= upper
        }
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
                    meeting.wavFilePath = urlA.path
                    meeting.durationSeconds = Int(AudioFileEditor.duration(url: urlA))
                    invalidateTranscriptArtifacts(of: meeting, in: context)

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
                await MainActor.run { self.error = error.localizedDescription }
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

    // MARK: - Helpers

    private func cleanupStaleTmp() {
        guard let url = meeting.wavFileURL else { return }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".tmp.wav")
        // Tente attributesOfItem direct ; absent ou inaccessible → no-op
        // (évite la double-tour fileExists + attributesOfItem qui était TOCTOU).
        if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
           let mtime = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) > 5 * 60 {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

}

/// Vide les artefacts de transcription après une édition audio. Les
/// `ReportRevision` sont conservées mais devront être régénérées par
/// l'utilisateur.
func invalidateTranscriptArtifacts(of meeting: Meeting, in context: ModelContext) {
    meeting.rawTranscript = ""
    meeting.mergedTranscript = ""
    meeting.summary = ""
    for seg in meeting.transcriptSegments { context.delete(seg) }
}
