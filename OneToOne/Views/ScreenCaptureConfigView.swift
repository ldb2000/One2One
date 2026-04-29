import SwiftUI
import ScreenCaptureKit

struct ScreenCaptureConfigView: View {
    @ObservedObject var service: ScreenCaptureService
    var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var sources: SCShareableContent?
    @State private var selectedWindowID: CGWindowID?
    @State private var captureType: CaptureType = .window
    @State private var mode: ScreenCaptureService.CaptureMode = .manual
    @State private var interval: Double = 2.0
    @State private var threshold: Double = 12.0
    @State private var selectedRect: CGRect?
    
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
                        if let windows = sources?.windows {
                            ForEach(windows.filter { $0.windowLayer == 0 && !($0.title?.isEmpty ?? true) }, id: \.windowID) { window in
                                Text("\(window.owningApplication?.applicationName ?? "?") — \(window.title ?? "?")")
                                    .tag(window.windowID as CGWindowID?)
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
