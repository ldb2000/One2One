import SwiftUI
import SwiftData

/// Panneau gauche listant les jobs (transcription, rapport) en cours et
/// récemment terminés. Permet l'annulation et la navigation vers la réunion
/// concernée (via `QuickLaunchRouter`).
struct JobQueueSidebar: View {

    @ObservedObject var queue: JobQueue = .shared
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: QuickLaunchRouter

    /// Quand `true`, affiche un en-tête avec icône + bouton trash. Désactivé
    /// lorsqu'on est embarqué dans un autre conteneur qui fournit son propre
    /// en-tête (cf. MainSidebarView.jobsFooter).
    var showsHeader: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header
                Divider()
            } else if !queue.terminalJobs.isEmpty {
                HStack {
                    Spacer()
                    Button { queue.clearTerminal() } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Effacer les terminés")
                }
                .padding(.horizontal, 8).padding(.top, 4)
            }
            if queue.jobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !queue.activeJobs.isEmpty {
                            sectionLabel("En cours")
                            ForEach(queue.activeJobs) { job in jobRow(job) }
                        }
                        if !queue.terminalJobs.isEmpty {
                            sectionLabel("Terminés").padding(.top, 8)
                            ForEach(queue.terminalJobs) { job in jobRow(job) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .foregroundStyle(.secondary)
            Text("File de jobs")
                .font(.caption.bold())
            Spacer()
            if !queue.terminalJobs.isEmpty {
                Button {
                    queue.clearTerminal()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Effacer les terminés")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Aucun job")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func jobRow(_ job: JobQueue.Job) -> some View {
        HStack(alignment: .top, spacing: 8) {
            jobIcon(job)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.meetingTitle)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(jobKindLabel(job.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if job.status == .queued {
                    Text("En attente…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if job.status == .running || job.status == .cancelling {
                    progressLine(job)
                } else if case .failed(let msg) = job.status {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(terminalLabel(job))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            if job.status == .queued
                || job.status == .running
                || job.status == .cancelling {
                Button {
                    if job.status == .cancelling {
                        queue.forceCancel(job.id)
                    } else {
                        queue.cancel(job.id)
                    }
                } label: {
                    Image(systemName: job.status == .cancelling
                          ? "xmark.octagon.fill"
                          : "xmark.circle.fill")
                        .foregroundStyle(job.status == .cancelling ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .help({
                    switch job.status {
                    case .queued:     return "Retirer de la file"
                    case .cancelling: return "Forcer l'annulation (le travail peut continuer en arrière-plan)"
                    default:          return "Annuler ce job"
                    }
                }())
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground(for: job))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Naviguer vers la réunion via pendingToken (même mécanique que
            // les notifs et la menubar).
            guard let id = job.meetingID else { return }
            if let meeting = lookupMeeting(persistentID: id) {
                router.pendingToken = OneToOneLaunchToken(
                    meetingID: meeting.ensuredStableID,
                    autoStartRecording: false
                )
            }
        }
    }

    @ViewBuilder
    private func jobIcon(_ job: JobQueue.Job) -> some View {
        switch job.status {
        case .queued:
            Image(systemName: "hourglass").foregroundStyle(.secondary)
        case .running:
            switch job.kind {
            case .transcription:
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
            case .report:
                Image(systemName: "wand.and.stars").foregroundStyle(Color.accentColor)
            case .audioEdit:
                Image(systemName: "scissors").foregroundStyle(Color.accentColor)
            case .diarization:
                Image(systemName: "person.wave.2").foregroundStyle(Color.accentColor)
            case .maintenance:
                Image(systemName: "wrench.and.screwdriver").foregroundStyle(Color.accentColor)
            }
        case .cancelling: Image(systemName: "xmark.circle").foregroundStyle(.orange)
        case .succeeded:  Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .cancelled:  Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .failed:     Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func progressLine(_ job: JobQueue.Job) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let p = job.progress {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            if let s = job.statusText, !s.isEmpty {
                Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func terminalLabel(_ job: JobQueue.Job) -> String {
        let start = job.startedAt ?? job.queuedAt
        let dur = (job.finishedAt ?? Date()).timeIntervalSince(start)
        let secs = Int(dur)
        let suffix = secs >= 60 ? "\(secs / 60)m \(secs % 60)s" : "\(secs)s"
        switch job.status {
        case .succeeded: return "Terminé · \(suffix)"
        case .cancelled: return "Annulé · \(suffix)"
        default: return suffix
        }
    }

    private func rowBackground(for job: JobQueue.Job) -> Color {
        switch job.status {
        case .queued:               return Color.secondary.opacity(0.07)
        case .running, .cancelling: return Color.accentColor.opacity(0.08)
        case .failed:               return Color.red.opacity(0.06)
        default:                    return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func lookupMeeting(persistentID: PersistentIdentifier) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.persistentModelID == persistentID }
    }

    private func jobKindLabel(_ k: JobQueue.JobKind) -> String {
        switch k {
        case .transcription: return "Transcription"
        case .report:        return "Rapport IA"
        case .audioEdit:     return "Édition audio"
        case .diarization:   return "Diarisation"
        case .maintenance:   return "Maintenance"
        }
    }
}
