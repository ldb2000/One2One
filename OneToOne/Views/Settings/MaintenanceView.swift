import SwiftUI
import SwiftData

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
}
