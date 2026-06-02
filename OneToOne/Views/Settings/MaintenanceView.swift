import SwiftUI
import SwiftData

/// Tableau de bord de maintenance : visualisation du stockage, lancement de
/// traitements en lot (rapports/transcriptions/diarisations manquants),
/// rétention/compression audio, nettoyage des fichiers orphelins et VACUUM SQLite.
struct MaintenanceView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @State private var stats: StorageStatsService.Stats?

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            storageSection
            batchJobsSection
            cleanupAudioSection
            filesCleanupSection
            databaseSection
            footerSection
        }
        .padding(8)
        .task { refreshStats(force: false) }
    }

    @ViewBuilder
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("STOCKAGE", systemImage: "internaldrive")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    refreshStats(force: true)
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let s = stats {
                storageBar(s)
                storageLegend(s)
            } else {
                Text("Chargement…").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func storageBar(_ s: StorageStatsService.Stats) -> some View {
        GeometryReader { geo in
            let total = max(Int64(1), s.totalBytes)
            HStack(spacing: 0) {
                segment(width: geo.size.width * CGFloat(s.wavBytes) / CGFloat(total),
                        color: .accentColor)
                segment(width: geo.size.width * CGFloat(s.attachmentBytes) / CGFloat(total),
                        color: .orange)
                segment(width: geo.size.width * CGFloat(s.slidesBytes) / CGFloat(total),
                        color: .purple)
                segment(width: geo.size.width * CGFloat(s.databaseBytes) / CGFloat(total),
                        color: .green)
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func storageLegend(_ s: StorageStatsService.Stats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(color: .accentColor, label: "Fichiers WAV",
                      detail: "\(formatBytes(s.wavBytes)) (\(s.wavCount))")
            legendRow(color: .orange, label: "Attachements",
                      detail: "\(formatBytes(s.attachmentBytes)) (\(s.attachmentCount))")
            legendRow(color: .purple, label: "Slides capturées",
                      detail: "\(formatBytes(s.slidesBytes)) (\(s.slidesCount))")
            legendRow(color: .green, label: "Base de données",
                      detail: formatBytes(s.databaseBytes))
        }
    }

    private func legendRow(color: Color, label: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption)
            Spacer()
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func refreshStats(force: Bool) {
        stats = StorageStatsService.shared.snapshot(in: context, force: force)
    }

    private func formatBytes(_ b: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: b)
    }

    // MARK: - Batch Jobs Section

    /// Affiche, pour chaque type de traitement (rapport, transcription,
    /// diarisation), le nombre de réunions à traiter et un bouton qui en
    /// enfile un job par réunion candidate dans la `JobQueue` partagée.
    @ViewBuilder
    private var batchJobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("TRAITEMENTS EN LOT", systemImage: "rectangle.stack.badge.play")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            batchRow(
                count: BatchJobsService.meetingsWithoutReport(in: context).count,
                label: "réunions sans rapport",
                buttonLabel: "Générer les rapports manquants",
                action: enqueueMissingReports
            )
            batchRow(
                count: BatchJobsService.meetingsWithoutTranscript(in: context).count,
                label: "réunions sans transcription",
                buttonLabel: "Transcrire les réunions sans transcript",
                action: enqueueMissingTranscripts
            )
            batchRow(
                count: BatchJobsService.meetingsWithoutDiarisation(in: context).count,
                label: "réunions sans diarisation",
                buttonLabel: "Diariser les locuteurs",
                action: enqueueMissingDiarisations
            )
        }
    }

    private func batchRow(count: Int,
                          label: String,
                          buttonLabel: String,
                          action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: count > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(count > 0 ? .orange : .green)
            Text("\(count) \(label)").font(.callout)
            Spacer()
            Button(buttonLabel, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(count == 0)
        }
    }

    /// Enfile un job de génération de rapport par réunion sans rapport. Chaque
    /// job appelle `AIReportService` puis écrit le résultat sur la réunion.
    private func enqueueMissingReports() {
        let queue = JobQueue.shared
        let candidates = BatchJobsService.meetingsWithoutReport(in: context)
        let snap = settings
        for meeting in candidates {
            let title = meeting.title
            let id = meeting.persistentModelID
            _ = queue.start(
                kind: .report,
                meetingID: id,
                meetingTitle: title + " · batch"
            ) { _ in
                let result = try await AIReportService.generate(
                    meeting: meeting,
                    in: context,
                    settings: snap
                )
                await MainActor.run {
                    meeting.summary = result.summary
                    meeting.keyPoints = result.keyPoints
                    meeting.decisions = result.decisions
                    meeting.openQuestions = result.openQuestions
                    try? context.save()
                }
            }
        }
    }

    /// Enfile un job de transcription par réunion disposant d'un WAV mais sans
    /// transcript. Les réunions sans fichier audio sont ignorées.
    private func enqueueMissingTranscripts() {
        let queue = JobQueue.shared
        let candidates = BatchJobsService.meetingsWithoutTranscript(in: context)
        let snap = settings
        for meeting in candidates {
            guard let wavURL = meeting.wavFileURL else { continue }
            let title = meeting.title
            let id = meeting.persistentModelID
            _ = queue.start(
                kind: .transcription,
                meetingID: id,
                meetingTitle: title + " · batch"
            ) { _ in
                let stt = TranscriptionService.shared
                _ = try await stt.runTranscription(
                    audioURL: wavURL,
                    meeting: meeting,
                    settings: snap,
                    in: context
                )
            }
        }
    }

    /// Enfile un job de diarisation par réunion disposant d'un WAV mais sans
    /// diarisation. Chaque job appelle `PyannoteDiarizer`, associe les clusters
    /// aux collaborateurs via `SpeakerMatcher` et persiste le mapping en JSON.
    private func enqueueMissingDiarisations() {
        let queue = JobQueue.shared
        let candidates = BatchJobsService.meetingsWithoutDiarisation(in: context)
        let snap = settings
        for meeting in candidates {
            guard let wavURL = meeting.wavFileURL else { continue }
            let title = meeting.title
            let id = meeting.persistentModelID
            _ = queue.start(
                kind: .diarization,
                meetingID: id,
                meetingTitle: title + " · batch"
            ) { _ in
                let out = try await PyannoteDiarizer.shared.diarize(audioURL: wavURL)
                await MainActor.run {
                    let assignments = SpeakerMatcher.match(
                        clusterEmbeddings: out.perClusterEmbedding,
                        meeting: meeting,
                        in: context,
                        settings: snap
                    )
                    var dict: [String: Any] = [:]
                    for (cid, a) in assignments {
                        dict[String(cid)] = a.collaborator?.ensuredStableID.uuidString ?? NSNull()
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: dict),
                       let s = String(data: data, encoding: .utf8) {
                        meeting.speakerAssignmentsJSON = s
                    }
                    try? context.save()
                }
            }
        }
    }

    // MARK: - Cleanup Audio Section

    @ViewBuilder
    private var cleanupAudioSection: some View {
        let plan = WavRetentionService.plan(in: context, settings: settings)
        VStack(alignment: .leading, spacing: 10) {
            Label("NETTOYAGE AUDIO", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack {
                Text("Compresser les WAV (AAC 32 kbps mono) après")
                Stepper("\(settings.wavCompressionDays) jours",
                        value: Binding(
                            get: { settings.wavCompressionDays },
                            set: { settings.wavCompressionDays = $0; saveCtx() }
                        ),
                        in: 1...365)
                    .labelsHidden()
                Text("\(settings.wavCompressionDays) jours")
                    .font(.callout.monospacedDigit())
            }
            HStack {
                Text("Supprimer définitivement les WAV après")
                Stepper("\(settings.wavDeletionDays) jours",
                        value: Binding(
                            get: { settings.wavDeletionDays },
                            set: { settings.wavDeletionDays = $0; saveCtx() }
                        ),
                        in: 1...365)
                    .labelsHidden()
                Text("\(settings.wavDeletionDays) jours")
                    .font(.callout.monospacedDigit())
            }
            Toggle("Lancer automatiquement au démarrage de l'app",
                   isOn: Binding(
                    get: { settings.autoCleanupOnLaunch },
                    set: { settings.autoCleanupOnLaunch = $0; saveCtx() }
                   ))

            Text("Sera affecté : \(plan.toCompress.count) WAV à compresser · \(plan.toDelete.count) à supprimer")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Lancer le cleanup maintenant") {
                    runCleanup(plan: plan)
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan.toCompress.isEmpty && plan.toDelete.isEmpty)
            }
        }
    }

    private func saveCtx() {
        try? context.save()
    }

    // MARK: - Files Cleanup Section

    @ViewBuilder
    private var filesCleanupSection: some View {
        let orphans = OrphanCleanupService.orphanAttachments(in: context)
        let staleTmp = OrphanCleanupService.staleTmpWavs(
            in: applicationSupportDir().appendingPathComponent("recordings")
        )
        VStack(alignment: .leading, spacing: 10) {
            Label("NETTOYAGE FICHIERS", systemImage: "trash")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: orphans.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(orphans.isEmpty ? .green : .orange)
                Text("\(orphans.count) attachements pointent vers des fichiers introuvables")
                    .font(.callout)
                Spacer()
                Button("Nettoyer") {
                    OrphanCleanupService.deleteAttachments(orphans, in: context)
                }
                .disabled(orphans.isEmpty)
            }
            HStack {
                Image(systemName: staleTmp.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(staleTmp.isEmpty ? .green : .orange)
                Text("\(staleTmp.count) fichiers .tmp.wav orphelins")
                    .font(.callout)
                Spacer()
                Button("Supprimer") {
                    OrphanCleanupService.deleteFiles(staleTmp)
                    StorageStatsService.shared.invalidate()
                }
                .disabled(staleTmp.isEmpty)
            }
        }
    }

    // MARK: - Database Section

    @ViewBuilder
    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("BASE DE DONNÉES", systemImage: "cylinder.split.1x2")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack {
                Text("Compaction SQLite — récupère l'espace après suppressions massives")
                    .font(.callout)
                Spacer()
                Button("Compacter (VACUUM)") {
                    do {
                        let r = try DatabaseVacuumService.vacuum()
                        print("[Maintenance] VACUUM \(r.bytesBefore)B → \(r.bytesAfter)B")
                        StorageStatsService.shared.invalidate()
                    } catch {
                        print("[Maintenance] VACUUM failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Footer Section

    @ViewBuilder
    private var footerSection: some View {
        if let date = settings.lastCleanupAt {
            Text("Dernier cleanup : \(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))")
                .font(.caption2).foregroundStyle(.tertiary)
        } else {
            Text("Dernier cleanup : jamais")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private func applicationSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OneToOne")
    }

    /// Exécute le plan de rétention dans un unique job `.maintenance` : compresse
    /// puis supprime les WAV concernés, en publiant la progression (fraction +
    /// statut) à chaque étape, puis met à jour `lastCleanupAt`. Annulable.
    private func runCleanup(plan: WavRetentionService.CleanupPlan) {
        let queue = JobQueue.shared
        let snapshotPlan = plan
        _ = queue.start(
            kind: .maintenance,
            meetingTitle: "Cleanup audio"
        ) { jobID in
            var done = 0
            let total = snapshotPlan.toCompress.count + snapshotPlan.toDelete.count
            for m in snapshotPlan.toCompress {
                try Task.checkCancellation()
                await MainActor.run {
                    queue.updateProgress(jobID,
                                         fraction: Double(done) / Double(max(1, total)),
                                         status: "Compression : \(m.title)")
                }
                do {
                    try await WavRetentionService.compress(m, in: context)
                } catch {
                    print("[Maintenance] compress échec \(m.title): \(error)")
                }
                done += 1
            }
            for m in snapshotPlan.toDelete {
                try Task.checkCancellation()
                await MainActor.run {
                    queue.updateProgress(jobID,
                                         fraction: Double(done) / Double(max(1, total)),
                                         status: "Suppression : \(m.title)")
                    WavRetentionService.delete(m, in: context)
                }
                done += 1
            }
            await MainActor.run {
                settings.lastCleanupAt = Date()
                saveCtx()
                StorageStatsService.shared.invalidate()
            }
        }
    }
}
