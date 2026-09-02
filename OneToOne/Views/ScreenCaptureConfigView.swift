import CoreGraphics
import SwiftData
import SwiftUI

/// Popover de la capture automatique de slides. Trois faces selon l'état du service :
/// configurer (`idle`), suivre (`running` / `paused`), reprendre ou terminer (`stopped`),
/// plus un écran de refus d'autorisation qui remplace tout.
///
/// Règle : tout contrôle dont l'action n'aurait aucun effet est **désactivé**, l'état réel
/// est affiché, et une instruction désigne une action présente au même endroit.
struct ScreenCaptureConfigView: View {
    @ObservedObject var service: ScreenCaptureService
    var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var windows: [ShareableWindow] = []
    @State private var selectedWindowID: CGWindowID?
    @State private var preview: CGImage?
    @State private var previewError: String?
    @State private var crop: NormalizedRect = .full
    @State private var sensitivity: SlideCaptureSettings.Sensitivity = .normal
    @State private var appendToPrevious = false
    @State private var permissionDenied = false
    @State private var catalogError: String?
    @State private var startError: String?
    @State private var settingsOpenFailed = false

    private var settings: AppSettings? { settingsList.canonicalSettings }

    /// Dernier lot de slides de la réunion, s'il existe (pour « Ajouter au lot précédent »).
    private var previousAttachment: MeetingAttachment? {
        meeting.attachments.filter { $0.kind == "slides" }.sorted { $0.importedAt > $1.importedAt }.first
    }

    private var selectedWindow: ShareableWindow? {
        windows.first { $0.id == selectedWindowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if permissionDenied {
                permissionFace
            } else {
                switch service.state {
                case .idle: configureFace
                case .running, .paused: followFace
                case .stopped: stoppedFace
                }
            }
        }
        .padding()
        .frame(width: 420)
        .task { await refreshWindows() }
        .onAppear {
            sensitivity = settings?.slideCaptureSensitivity ?? .normal
            if let previous = previousAttachment {
                // Ajouter par défaut si le lot date de moins de quatre heures.
                appendToPrevious = Date().timeIntervalSince(previous.importedAt) < 4 * 3600
            }
        }
    }

    // MARK: - Face « configurer » (idle)

    private var configureFace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capturer les slides depuis…").font(.headline)

            windowPicker(onChange: { window in
                crop = .full
                Task { await loadPreview(of: window) }
            })

            if let preview {
                VStack(alignment: .leading, spacing: 6) {
                    CropSelectionView(image: preview, rect: $crop)
                        .frame(maxHeight: 220)
                    HStack {
                        Text("Tracez la zone du slide sur l'aperçu.")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("Toute la fenêtre") { crop = .full }
                            .buttonStyle(.link).font(.caption)
                            .disabled(crop == .full)
                    }
                }
            } else if let previewError {
                Text("Aperçu indisponible : \(previewError). La fenêtre entière sera capturée.")
                    .font(.caption).foregroundColor(.orange)
            } else if selectedWindowID != nil {
                ProgressView("Aperçu en cours…").controlSize(.small)
            }

            Divider()

            Picker("Sensibilité", selection: $sensitivity) {
                ForEach(SlideCaptureSettings.Sensitivity.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text("Élevée : détecte les petits changements. Faible : source bruitée ou très compressée.")
                .font(.caption2).foregroundColor(.secondary)

            if let previous = previousAttachment {
                Picker("Lot", selection: $appendToPrevious) {
                    Text("Nouveau lot").tag(false)
                    Text("Ajouter au lot précédent (\(previous.slides.count) slides, \(previous.importedAt.formatted(date: .omitted, time: .shortened)))").tag(true)
                }
                .pickerStyle(.radioGroup)
            }

            if let catalogError { errorLabel(catalogError) }
            if let startError { errorLabel(startError) }

            HStack {
                Button("Annuler") { dismiss() }
                Spacer()
                Button("Commencer") { startCapture() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedWindowID == nil)
            }
        }
    }

    // MARK: - Face « suivre » (running / paused)

    private var followFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine
            if let configuration = service.configuration {
                Text("Fenêtre : \(configuration.windowTitle)").font(.caption).foregroundColor(.secondary)
            }
            if let preview {
                CropSelectionView(image: preview, rect: $crop, isLocked: true)
                    .frame(maxHeight: 200)
            }
            Divider()
            // L'instruction et l'action sont au même endroit.
            HStack {
                Text("Arrêtez la capture pour changer la fenêtre.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Arrêter") { service.stop() }
                    .buttonStyle(.bordered)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
            }
        }
        .task { await loadPreviewOfCurrentSource() }
    }

    // MARK: - Face « arrêtée » (stopped)

    private var stoppedFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine
            if let configuration = service.configuration {
                let stillThere = windows.contains { $0.id == configuration.windowID }
                if stillThere {
                    Text("Fenêtre : \(configuration.windowTitle)").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("La fenêtre « \(configuration.windowTitle) » a disparu. Choisissez-en une autre : la zone tracée est conservée.")
                        .font(.caption).foregroundColor(.orange)
                    windowPicker(onChange: { window in
                        service.updateSource(windowID: window.id, title: window.displayName)
                        Task { await loadPreview(of: window) }
                    })
                }
            }
            if let preview {
                CropSelectionView(image: preview, rect: $crop, isLocked: true)
                    .frame(maxHeight: 200)
            }
            Divider()
            HStack {
                Button("Terminer", role: .destructive) {
                    Task { await service.finish(); dismiss() }
                }
                .help("Clôt le lot : OCR, sauvegarde, indexation. Un prochain démarrage ouvrira un nouveau lot.")
                Spacer()
                Button("Fermer") { dismiss() }
                Button("Reprendre") { service.resume() }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.configuration.map { config in !windows.contains { $0.id == config.windowID } } ?? true)
            }
        }
        .task { await loadPreviewOfCurrentSource() }
    }

    // MARK: - Face « autorisation refusée »

    private var permissionFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enregistrement de l'écran refusé", systemImage: "exclamationmark.shield")
                .font(.headline)
            Text("OneToOne a besoin de l'autorisation « Enregistrement de l'écran » pour capturer les slides. Après l'avoir accordée, relancez OneToOne.")
                .font(.callout)
            Button("Ouvrir les Réglages") {
                settingsOpenFailed = !ScreenRecordingSettingsLink.open()
            }
            .buttonStyle(.borderedProminent)
            if settingsOpenFailed {
                Text("Impossible d'ouvrir les Réglages automatiquement. Chemin : \(ScreenRecordingSettingsLink.manualPath)")
                    .font(.caption).foregroundColor(.orange)
            }
            HStack {
                Button("Réessayer") { Task { await refreshWindows() } }
                Spacer()
                Button("Fermer") { dismiss() }
            }
        }
    }

    // MARK: - Composants

    private var statusLine: some View {
        HStack(spacing: 8) {
            switch service.state {
            case .running:
                Circle().fill(Color.blue).frame(width: 8, height: 8)
                Text("Capture en cours · \(service.capturedSlidesCount) slides").font(.headline)
            case .paused(let reason):
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("En pause · \(service.capturedSlidesCount) slides").font(.headline)
                    Text(reason).font(.caption).foregroundColor(.secondary)
                }
            case .stopped:
                Circle().fill(Color.gray).frame(width: 8, height: 8)
                Text("Arrêtée · \(service.capturedSlidesCount) slides").font(.headline)
            case .idle:
                EmptyView()
            }
        }
    }

    private func windowPicker(onChange: @escaping (ShareableWindow) -> Void) -> some View {
        HStack {
            Picker("Fenêtre", selection: Binding<CGWindowID?>(
                get: { selectedWindowID },
                set: { newValue in
                    // Une désélection (nil) est un no-op : un rafraîchissement de la liste
                    // ne doit pas effacer le tracé. Seul un passage vers une fenêtre
                    // différente et non nulle réinitialise.
                    guard let newValue, newValue != selectedWindowID else { return }
                    selectedWindowID = newValue
                    if let window = windows.first(where: { $0.id == newValue }) { onChange(window) }
                }
            )) {
                Text("Sélectionner une fenêtre").tag(nil as CGWindowID?)
                let meeting = windows.filter(\.isMeetingApp)
                let others = windows.filter { !$0.isMeetingApp }
                if !meeting.isEmpty {
                    Section("Réunions") {
                        ForEach(meeting) { Text($0.displayName).tag($0.id as CGWindowID?) }
                    }
                }
                if !others.isEmpty {
                    Section("Autres fenêtres") {
                        ForEach(others) { Text($0.displayName).tag($0.id as CGWindowID?) }
                    }
                }
            }
            Button { Task { await refreshWindows() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Rafraîchir la liste des fenêtres")
        }
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.red)
    }

    // MARK: - Actions

    private func refreshWindows() async {
        catalogError = nil
        let blacklist = Set(settings?.captureBlacklist ?? [])
        do {
            windows = try await WindowCatalog.shareableWindows(excludingAppNames: blacklist)
            permissionDenied = false
        } catch let error as SlideCaptureError where error == .screenRecordingDenied {
            permissionDenied = true
        } catch let error as SlideCaptureError where error == .noShareableWindows {
            windows = []
            catalogError = "Aucune fenêtre partageable. Ouvrez la réunion, puis rafraîchissez."
        } catch {
            windows = []
            catalogError = error.localizedDescription
        }
    }

    private func loadPreview(of window: ShareableWindow) async {
        preview = nil
        previewError = nil
        do {
            let image = try await WindowFrameSource(windowID: window.id).captureFrame()
            // Une sélection plus récente a pu arriver pendant la capture : ne pas écraser son aperçu.
            guard selectedWindowID == window.id else { return }
            guard let image else {
                previewError = "fenêtre introuvable"
                return
            }
            preview = image
        } catch {
            // Une sélection plus récente a pu arriver pendant la capture : ne pas écraser son aperçu.
            guard selectedWindowID == window.id else { return }
            if SlideCaptureError.isPermissionDenial(error) { permissionDenied = true }
            previewError = error.localizedDescription
        }
    }

    private func loadPreviewOfCurrentSource() async {
        guard let configuration = service.configuration else { return }
        crop = configuration.crop
        if let image = try? await WindowFrameSource(windowID: configuration.windowID).captureFrame() {
            preview = image
        }
    }

    private func startCapture() {
        guard let window = selectedWindow else { return }
        startError = nil
        settings?.slideCaptureSensitivity = sensitivity
        let configuration = ScreenCaptureService.SessionConfiguration(
            windowID: window.id,
            windowTitle: window.displayName,
            crop: crop,
            sensitivity: sensitivity
        )
        do {
            try service.start(
                configuration: configuration,
                meeting: meeting,
                context: context,
                appendTo: appendToPrevious ? previousAttachment : nil
            )
            dismiss()
        } catch {
            startError = error.localizedDescription
        }
    }
}
