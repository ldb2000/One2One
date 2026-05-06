import Foundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import os

private let captureLog = Logger(subsystem: "com.onetoone.app", category: "capture")

@MainActor
final class ScreenCaptureService: NSObject, ObservableObject, SCStreamOutput {
    
    enum CaptureMode {
        case manual
        case auto
    }
    
    enum CaptureSource {
        case window(SCWindow)
        case display(SCDisplay, CGRect) // Area on a display
    }
    
    @Published var isCapturing = false
    /// Attachment courant exposé pour que la vue lise les slides sans
    /// deviner via `meeting.attachments`. Réinitialisé à `nil` entre sessions.
    @Published var currentAttachment: MeetingAttachment?
    @Published var lastError: String?
    @Published var ocrProgress: (current: Int, total: Int)?

    /// Nombre de slides capturées dans la session courante.
    /// Source de vérité : le nombre d'éléments dans `currentAttachment.slides`.
    var capturedSlidesCount: Int {
        currentAttachment?.slides.count ?? 0
    }
    
    private var stream: SCStream?
    private var mode: CaptureMode = .manual
    private var autoInterval: TimeInterval = 2.0
    private var autoThreshold: Int = 12
    
    private var lastCapturedHash: UInt64?
    private var lastCheckTime: Date = .distantPast
    
    private var modelContext: ModelContext?
    private var ocrTasks: [Task<Void, Never>] = []
    
    private let captureQueue = DispatchQueue(label: "com.onetoone.capture", qos: .userInitiated)
    
    // Config
    var selectedSource: CaptureSource?
    
    func start(mode: CaptureMode, 
               interval: TimeInterval = 2.0, 
               threshold: Int = 12, 
               meeting: Meeting, 
               context: ModelContext) async {
        self.mode = mode
        self.autoInterval = interval
        self.autoThreshold = threshold
        self.modelContext = context
        self.lastError = nil
        self.currentAttachment = nil
        self.lastCapturedHash = nil
        self.lastCheckTime = .distantPast
        
        guard let source = selectedSource else {
            self.lastError = "Aucune source sélectionnée"
            return
        }
        
        // Create attachment
        let attachment = MeetingAttachment(url: URL(fileURLWithPath: "slides-\(Date().timeIntervalSince1970).slides"), kind: "slides")
        attachment.fileName = "Slides capture - \(Date().formatted(date: .abbreviated, time: .shortened))"
        attachment.meeting = meeting
        context.insert(attachment)
        self.currentAttachment = attachment
        
        do {
            let filter: SCContentFilter
            let configuration = SCStreamConfiguration()
            configuration.width = 1280
            configuration.height = 720
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1.0 / autoInterval))
            
            switch source {
            case .window(let window):
                filter = SCContentFilter(desktopIndependentWindow: window)
                configuration.width = Int(window.frame.width * 2) // Retinal
                configuration.height = Int(window.frame.height * 2)
            case .display(let display, let rect):
                filter = SCContentFilter(display: display, including: [], exceptingWindows: [])
                configuration.sourceRect = rect
                configuration.width = Int(rect.width * 2)
                configuration.height = Int(rect.height * 2)
            }
            
            self.stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            try await stream?.startCapture()
            
            self.isCapturing = true
            captureLog.info("Capture started: mode=\(mode == .manual ? "manual" : "auto")")
            
        } catch {
            self.lastError = "Erreur de capture: \(error.localizedDescription)"
            captureLog.error("Start capture failed: \(error.localizedDescription)")
        }
    }
    
    func stop() async {
        guard isCapturing else { return }
        
        // Stop stream first to avoid new frames
        try? await stream?.stopCapture()
        self.isCapturing = false
        self.stream = nil
        
        // Wait for OCR tasks
        if !ocrTasks.isEmpty {
            let total = ocrTasks.count
            self.ocrProgress = (0, total)
            for (idx, task) in ocrTasks.enumerated() {
                await task.value
                self.ocrProgress = (idx + 1, total)
            }
        }
        self.ocrProgress = nil
        self.ocrTasks = []
        
        try? modelContext?.save()
        
        // Final RAG re-indexing
        if let attachment = currentAttachment, let context = modelContext {
            Task {
                try? await MeetingAttachmentService.reindexAttachment(attachment, context: context)
            }
        }
        
        captureLog.info("Capture stopped")
    }
    
    func snapshot() {
        self.shouldTakeManualSnapshot = true
    }
    
    private var shouldTakeManualSnapshot = false
    
    // MARK: - SCStreamOutput
    
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        
        Task { @MainActor in
            guard isCapturing else { return }
            let now = Date()
            
            if mode == .auto {
                if now.timeIntervalSince(lastCheckTime) >= autoInterval {
                    lastCheckTime = now
                    processFrameForAuto(imageBuffer)
                }
            } else if shouldTakeManualSnapshot {
                shouldTakeManualSnapshot = false
                processFrame(imageBuffer)
            }
        }
    }
    
    private func processFrameForAuto(_ imageBuffer: CVImageBuffer) {
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Run pHash on background to avoid UI lag
        Task.detached(priority: .userInitiated) {
            let currentHash = PerceptualHasher.hash(cgImage: cgImage)
            
            await MainActor.run {
                if let lastHash = self.lastCapturedHash {
                    let distance = PerceptualHasher.hammingDistance(lastHash, currentHash)
                    if distance >= self.autoThreshold {
                        captureLog.info("Slide change detected (distance=\(distance))")
                        self.saveSlide(cgImage: cgImage, hash: currentHash)
                    }
                } else {
                    self.saveSlide(cgImage: cgImage, hash: currentHash)
                }
                self.lastCapturedHash = currentHash
            }
        }
    }
    
    private func processFrame(_ imageBuffer: CVImageBuffer) {
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        Task.detached(priority: .userInitiated) {
            let currentHash = PerceptualHasher.hash(cgImage: cgImage)
            await MainActor.run {
                self.saveSlide(cgImage: cgImage, hash: currentHash)
            }
        }
    }
    
    private func saveSlide(cgImage: CGImage, hash: UInt64) {
        guard let attachment = currentAttachment, let context = modelContext else { return }

        // Index = position courante dans la liste réelle des slides +1 (source unique).
        let index = attachment.slides.count + 1
        let date = Date()
        let timestamp = date.formatted(.dateTime.hour().minute().second().hour(.twoDigits(amPM: .omitted)))
        let fileName = "slide-\(String(format: "%03d", index))-\(timestamp).png"
        
        // Directory recording
        guard let meeting = attachment.meeting else { return }
        let recordingsDir = getRecordingsDirectory().appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        let fileURL = recordingsDir.appendingPathComponent(fileName)
        
        // Save PNG
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        if let data = nsImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }
        
        let slide = SlideCapture(index: index, capturedAt: date, imagePath: fileURL.path)
        slide.perceptualHash = String(hash, radix: 16)
        slide.attachment = attachment
        context.insert(slide)

        // Force un objectWillChange pour que la vue observe le changement du
        // computed `capturedSlidesCount` (qui lit attachment.slides).
        self.objectWillChange.send()
        
        // Launch OCR task
        let ocrTask = Task.detached {
            do {
                let text = try await OCRService.recognize(cgImage: cgImage)
                await MainActor.run {
                    slide.ocrText = text
                    self.rebuildAttachmentText()
                }
            } catch {
                captureLog.error("OCR failed for slide \(index): \(error.localizedDescription)")
            }
        }
        ocrTasks.append(ocrTask)
    }
    
    private func rebuildAttachmentText() {
        guard let attachment = currentAttachment else { return }
        let slides = attachment.slides.sorted(by: { $0.index < $1.index })
        var fullText = ""
        for slide in slides {
            let timestamp = slide.capturedAt.formatted(date: .omitted, time: .standard)
            fullText += "--- Slide \(slide.index) [\(timestamp)] ---\n"
            fullText += slide.ocrText + "\n\n"
        }
        attachment.extractedText = fullText
    }
    
    private func getRecordingsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("OneToOne", isDirectory: true)
        return appSupport.appendingPathComponent("recordings", isDirectory: true)
    }
    
    func deleteSlide(_ slide: SlideCapture) {
        guard let context = modelContext else { return }
        let path = slide.imagePath
        context.delete(slide)
        try? FileManager.default.removeItem(atPath: path)
        rebuildAttachmentText()
        objectWillChange.send()
        try? context.save()
    }
}
