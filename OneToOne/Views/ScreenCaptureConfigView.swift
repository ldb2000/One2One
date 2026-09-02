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
    @State private var selectedRect: CGRect?
    @State private var selectedDisplayID: CGDirectDisplayID?

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }
    
    /// Type de source de capture : une fenêtre applicative entière (`.window`)
    /// ou une zone rectangulaire précise sur un écran (`.rect`).
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
                        RectSelectorWindow.show(onSelected: { rect, displayID in
                            self.selectedRect = rect
                            self.selectedDisplayID = displayID
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
    
    /// Configure la source du service puis démarre la capture.
    // TODO Task 6 : reconstruire cet écran sur la nouvelle API de session
    // (`ScreenCaptureService.SessionConfiguration` + `beginSession`/`start`).
    private func startCapture() {
    }
}
