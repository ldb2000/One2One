import SwiftUI

/// Menus natifs macOS pour la réunion ayant le focus. Lit `MeetingMenuActions`
/// via `FocusedValue` : tout est grisé si aucune réunion n'a le focus
/// (`menu == nil`). Export rangé sous « Fichier » (`.importExport`) ; le reste
/// dans un nouveau menu « Réunion ».
struct MeetingCommands: Commands {
    @FocusedValue(\.meetingMenu) private var menu

    var body: some Commands {
        // Export → menu « Fichier », emplacement conventionnel.
        CommandGroup(after: .importExport) {
            Button("Copier le rapport en Markdown") { menu?.exportMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!isEnabled(.exportMarkdown))
            Button("Exporter en PDF…") { menu?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!isEnabled(.exportPDF))
            Menu("Envoyer via Apple Mail") { mailItems(menu?.exportMail) }
                .disabled(!isEnabled(.exportMail))
            Menu("Envoyer via Microsoft Outlook") { mailItems(menu?.exportOutlook) }
                .disabled(!isEnabled(.exportOutlook))
            Menu("Exporter vers Apple Notes") { mailItems(menu?.exportAppleNotes) }
                .disabled(!isEnabled(.exportNotes))
        }

        // Tout le reste → nouveau menu « Réunion ».
        CommandMenu("Réunion") {
            Button(menu?.isRecording == true ? "Arrêter et transcrire" : "Démarrer l'enregistrement") {
                if menu?.isRecording == true { menu?.stopRecording() } else { menu?.startRecording() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!isEnabled(.startStopRecording))
            Button("Reprendre l'enregistrement") { menu?.appendRecording() }
                .disabled(!isEnabled(.appendRecording))
            Button(menu?.isPaused == true ? "Reprendre" : "Mettre en pause") { menu?.togglePause() }
                .disabled(!isEnabled(.pause))

            Divider()
            Button("Générer le rapport") { menu?.generateReport() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isEnabled(.generateReport))
            Button("Relancer la transcription") { menu?.retranscribe() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!isEnabled(.retranscribe))
            Button("Prompt spécifique…") { menu?.toggleCustomPrompt() }
                .disabled(!isEnabled(.customPrompt))

            Divider()
            Button("Importer depuis le calendrier…") { menu?.importCalendar() }
                .disabled(!isEnabled(.importCalendar))
            Button("Importer un fichier WAV…") { menu?.importExistingWAV() }
                .disabled(!isEnabled(.importWAV))

            Divider()
            Button("Éditer l'audio…") { menu?.editAudio() }
                .disabled(!isEnabled(.editAudio))
            Button("Révéler le WAV dans le Finder") { menu?.revealWAV() }
                .disabled(!isEnabled(.revealWAV))

            Divider()
            Button("Supprimer la réunion…", role: .destructive) { menu?.deleteMeeting() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!isEnabled(.delete))
        }
    }

    private func isEnabled(_ item: MeetingMenuItem) -> Bool {
        menu?.isEnabled(item) ?? false
    }

    /// Les 4 variantes d'export e-mail/notes (mêmes options que l'ancien « ⋯ »).
    @ViewBuilder
    private func mailItems(_ action: ((MeetingMailExportOptions) -> Void)?) -> some View {
        Button("Rapport seul") { action?([]) }
        Button("Rapport + slides (PDF)") { action?(.includeSlidesPDF) }
        Button("Rapport + transcript") { action?([.includeTranscript]) }
        Button("Rapport + transcript + slides") { action?([.includeTranscript, .includeSlidesPDF]) }
    }
}
