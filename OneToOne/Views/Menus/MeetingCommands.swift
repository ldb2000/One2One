import SwiftUI
import SwiftData

/// Menus natifs macOS pour la réunion ayant le focus. Lit `MeetingMenuActions`
/// via `FocusedValue` : tout est grisé si aucune réunion n'a le focus
/// (`menu == nil`). Export rangé sous « Fichier » (`.importExport`) ; le reste
/// dans un nouveau menu « Réunion ».
struct MeetingCommands: Commands {
    @FocusedValue(\.meetingMenu) private var menu
    /// Contexte partagé, pour la commande de recette qui sème le jeu de
    /// démonstration. `Commands` n'a pas d'`@Environment(\.modelContext)` :
    /// c'est le conteneur de l'application qui le fournit.
    private var demoContext: ModelContext? {
        guard let container = OneToOneApp.sharedContainer else { return nil }
        return ModelContext(container)
    }

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
            // Spec §1.4 : ⌘K ouvre l'assistant sur la réunion courante, ⌘M
            // pose un marqueur sur l'axe temps à l'instant courant.
            Button("Assistant…") { menu?.openAssistant() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!isEnabled(.assistant))
            Button("Poser un marqueur") { menu?.addPlayheadMarker() }
                .keyboardShortcut("m", modifiers: .command)
                .disabled(!isEnabled(.marker))
            // Spec §2.6 : le mode séance plein écran s'ouvre depuis la pilule
            // audio ou par `⌃⌘F`. `⌘⌃F` et non `⌘F`, qui reste la recherche.
            Button("Mode séance plein écran") { menu?.toggleSessionFullscreen() }
                .keyboardShortcut("f", modifiers: [.control, .command])
                .disabled(!isEnabled(.sessionFullscreen))
            // Spec §1.4 : ⌘⇧V colle un lien ou une image dans les ressources.
            Button("Coller dans les ressources") { menu?.pasteResource() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!isEnabled(.pasteResource))
            Button("Ressources…") { menu?.openResources() }
                .disabled(!isEnabled(.resources))
            // Spec §1.4 : ⌘⇧S capture la source configurée — le sélecteur à la
            // première utilisation (lot 7, spec §5.1).
            Button("Capturer l'écran") { menu?.captureNow() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!isEnabled(.captureNow))

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

            Divider()
            // Recette de la refonte : sème la réunion de la capture
            // `1a-cockpit.png` (6 participants, 12 actions dont 9 non
            // assignées, 3 décisions, 5 risques), complétée de ce que
            // `1c-poste-de-pilotage.png` ajoute (décisions horodatées à
            // porteur, thèmes, fil du projet). Idempotent — cliquer deux fois
            // ne duplique rien.
            Button("Charger le jeu de démonstration (refonte)") {
                guard let demoContext else { return }
                // Un seul item de menu, mais **tous** les semis de la vague :
                // chaque `seedLotN` commence par `seed(in:)`, qui est
                // idempotent, puis complète sa part — `seedLot5` les décisions
                // horodatées, les thèmes et le fil du projet, `seedLot6` les
                // ressources de `3a-tiroir-ressources.png` (4 pièces de
                // séance, 17 du projet, 2 épinglées, 1 lien). Les appeler tous
                // les deux ne duplique donc rien.
                let reunion = RefonteDemoSeed.seedLot5(in: demoContext)
                _ = RefonteDemoSeed.seedLot6(in: demoContext)
                QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
                    meetingID: reunion.ensuredStableID,
                    autoStartRecording: false
                )
            }
            .disabled(demoContext == nil)

            // Lot 16 : la réunion d'atelier de `6a-atelier-planche.png`
            // (4 participants, 4 planches). Même idempotence.
            Button("Charger le jeu de démonstration (atelier)") {
                guard let demoContext else { return }
                let reunion = RefonteDemoSeed.seedWorkshop(in: demoContext)
                QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
                    meetingID: reunion.ensuredStableID,
                    autoStartRecording: false
                )
            }
            .disabled(demoContext == nil)
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
