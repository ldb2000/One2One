import SwiftUI
import SwiftData
import ScreenCaptureKit

struct ScreenCaptureConfigView: View {
    @ObservedObject var service: ScreenCaptureService
    var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var sources: SCShareableContent?
    @State private var selectedWindowID: CGWindowID?
    @State private var captureType: CaptureType = .window
    @State private var mode: ScreenCaptureService.CaptureMode = .manual
    @State private var interval: Double = 2.0
    @State private var threshold: Double = 12.0
    @State private var selectedRect: CGRect?

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }
    
    enum CaptureType {
        case window
        case rect
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capturer depuis…").font(.headline)
            
            Picker("Source", selection: $captureType) {
                Text("Fenêtre").tag(CaptureType.window)
                Text("Zone d'écran précise").tag(CaptureType.rect)
            }
            .pickerStyle(.segmented)
            
            if captureType == .window {
                HStack {
                    Picker("Fenêtre", selection: $selectedWindowID) {
                        Text("Sélectionner une fenêtre").tag(nil as CGWindowID?)
                        let buckets = groupedWindows()
                        // Teams en tête (priorité visuelle)
                        if !buckets.teams.isEmpty {
                            Section("Teams") {
                                ForEach(buckets.teams, id: \.windowID) { w in
                                    Text(windowLabel(w)).tag(w.windowID as CGWindowID?)
                                }
                            }
                        }
                        // Autres fenêtres (exclut OneToOne + blacklist utilisateur)
                        if !buckets.others.isEmpty {
                            Section("Autres fenêtres") {
                                ForEach(buckets.others, id: \.windowID) { w in
                                    Text(windowLabel(w)).tag(w.windowID as CGWindowID?)
                                }
                            }
                        }
                    }
                    Button(action: refreshSources) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Définir la zone…") {
                        RectSelectorWindow.show(onSelected: { rect in
                            self.selectedRect = rect
                        }, onCancel: {})
                    }
                    .buttonStyle(.bordered)
                    
                    if let rect = selectedRect {
                        Text("Zone : \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Aucune zone définie")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Divider()
            
            Text("Mode").font(.headline)
            Picker("Mode de capture", selection: $mode) {
                Text("Manuel (snapshot)").tag(ScreenCaptureService.CaptureMode.manual)
                Text("Auto (changement de slide)").tag(ScreenCaptureService.CaptureMode.auto)
            }
            .pickerStyle(.radioGroup)
            
            if mode == .auto {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Intervalle : \(Int(interval))s")
                        Slider(value: $interval, in: 1...5, step: 1)
                    }
                    HStack {
                        Text("Seuil : \(Int(threshold))")
                        Slider(value: $threshold, in: 5...30, step: 1)
                    }
                    Text("Un seuil plus bas est plus sensible aux petits changements.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Button("Annuler") { dismiss() }
                Spacer()
                Button("Commencer") {
                    startCapture()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear(perform: refreshSources)
    }
    
    private var canStart: Bool {
        if captureType == .window {
            return selectedWindowID != nil
        } else {
            return selectedRect != nil
        }
    }
    
    /// Trie les fenêtres : Teams en premier, "OneToOne" et la blacklist
    /// utilisateur exclus, le reste alpha par (app, titre).
    private func groupedWindows() -> (teams: [SCWindow], others: [SCWindow]) {
        guard let all = sources?.windows else { return ([], []) }
        let visible = all.filter { $0.windowLayer == 0 && !($0.title?.isEmpty ?? true) }
        let blacklist = Set(settings.captureBlacklist.map { $0.lowercased() })
        let ownAppNames: Set<String> = ["onetoone", "one2one"]

        var teams: [SCWindow] = []
        var others: [SCWindow] = []
        for w in visible {
            let appName = (w.owningApplication?.applicationName ?? "").lowercased()
            if ownAppNames.contains(appName) { continue }
            if blacklist.contains(appName) { continue }
            if appName.contains("teams") || appName.contains("microsoft teams") {
                teams.append(w)
            } else {
                others.append(w)
            }
        }
        let byAppTitle: (SCWindow, SCWindow) -> Bool = { a, b in
            let na = (a.owningApplication?.applicationName ?? "")
            let nb = (b.owningApplication?.applicationName ?? "")
            if na != nb { return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending }
            return (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "") == .orderedAscending
        }
        return (teams.sorted(by: byAppTitle), others.sorted(by: byAppTitle))
    }

    private func windowLabel(_ w: SCWindow) -> String {
        "\(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "?")"
    }

    private func refreshSources() {
        Task {
            do {
                self.sources = try await SCShareableContent.current
            } catch {
                print("Failed to get shareable content: \(error)")
            }
        }
    }
    
    private func startCapture() {
        guard let sources = sources else { return }
        
        if captureType == .window {
            guard let windowID = selectedWindowID,
                  let window = sources.windows.first(where: { $0.windowID == windowID }) else { return }
            service.selectedSource = .window(window)
        } else {
            guard let rect = selectedRect,
                  let display = sources.displays.first else { return } // On prend le premier display par défaut
            service.selectedSource = .display(display, rect)
        }
        
        Task {
            await service.start(
                mode: mode,
                interval: interval,
                threshold: Int(threshold),
                meeting: meeting,
                context: context
            )
        }
    }
}
