import SwiftUI
import SwiftData

/// Réglages du scan automatique des mails (section « Mails » des Paramètres).
struct MailSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    @State private var availableMailboxes: [MailboxRef] = []
    @State private var isLoadingMailboxes = false
    @State private var mailboxStatus: String?

    private var settings: AppSettings { settingsList.canonicalSettings ?? AppSettings() }

    /// Binding générique : écrit dans AppSettings, sauve et ré-arme la boucle.
    private func binding<T>(_ get: @escaping (AppSettings) -> T,
                            _ set: @escaping (AppSettings, T) -> Void) -> Binding<T> {
        Binding(
            get: { get(settings) },
            set: { newValue in
                set(settings, newValue)
                try? context.save()
                MailAutoIndexService.shared.reschedule(context: context, settings: settings)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Scanner automatiquement mes mails (mails lus uniquement)",
                   isOn: binding({ $0.mailAutoIndexEnabled }, { $0.mailAutoIndexEnabled = $1 }))

            // Boîtes scannées
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Boîtes scannées").font(.callout.bold())
                    Spacer()
                    Button {
                        loadMailboxes()
                    } label: {
                        Label("Recharger", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingMailboxes)
                }
                if availableMailboxes.isEmpty {
                    Text(mailboxStatus ?? "Cliquer sur « Recharger » pour lister les boîtes (autorisation Automation → Mail requise).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableMailboxes) { box in
                        Toggle(box.displayName, isOn: Binding(
                            get: { settings.mailAutoIndexMailboxes.contains(box) },
                            set: { on in
                                var boxes = settings.mailAutoIndexMailboxes
                                if on { boxes.append(box) } else { boxes.removeAll { $0 == box } }
                                settings.mailAutoIndexMailboxes = boxes
                                try? context.save()
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }

            HStack(spacing: 20) {
                Stepper("Historique : \(settings.mailAutoIndexLookbackDays) jours",
                        value: binding({ $0.mailAutoIndexLookbackDays },
                                       { $0.mailAutoIndexLookbackDays = $1 }),
                        in: 7...365, step: 7)
                Stepper("Intervalle : \(settings.mailAutoIndexIntervalMinutes) min",
                        value: binding({ $0.mailAutoIndexIntervalMinutes },
                                       { $0.mailAutoIndexIntervalMinutes = $1 }),
                        in: 15...480, step: 15)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Seuil rattachement auto : \(settings.mailAutoIndexAutoThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(value: binding({ $0.mailAutoIndexAutoThreshold },
                                          { $0.mailAutoIndexAutoThreshold = $1 }),
                           in: 0.5...1.0)
                        .frame(maxWidth: 220)
                }
                HStack {
                    Text("Seuil suggestion : \(settings.mailAutoIndexSuggestThreshold, format: .number.precision(.fractionLength(2)))")
                    Slider(value: binding({ $0.mailAutoIndexSuggestThreshold },
                                          { $0.mailAutoIndexSuggestThreshold = $1 }),
                           in: 0.1...0.75)
                        .frame(maxWidth: 220)
                }
                Text("≥ seuil auto : rattaché et indexé sans confirmation. Entre les deux : file de validation. En dessous : ignoré.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Scanner maintenant") {
                    MailAutoIndexService.shared.scanNow(context: context, settings: settings)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.mailAutoIndexEnabled || settings.mailAutoIndexMailboxes.isEmpty)

                if let last = settings.mailAutoIndexLastScanAt {
                    Text("Dernière passe : \(last.formatted(date: .abbreviated, time: .shortened)) — \(settings.mailAutoIndexLastScanStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Aucune passe effectuée.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { if settings.mailAutoIndexEnabled { loadMailboxes() } }
    }

    private func loadMailboxes() {
        isLoadingMailboxes = true
        mailboxStatus = nil
        Task {
            do {
                let boxes = try await MailService.listMailboxes()
                await MainActor.run {
                    availableMailboxes = boxes
                    isLoadingMailboxes = false
                    if boxes.isEmpty { mailboxStatus = "Aucune boîte trouvée dans Mail." }
                }
            } catch {
                await MainActor.run {
                    isLoadingMailboxes = false
                    mailboxStatus = "Erreur : \(error.localizedDescription)"
                }
            }
        }
    }
}
