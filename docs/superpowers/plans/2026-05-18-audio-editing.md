# Audio editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trim + split editing on meeting WAV files and a notification when recording starts.

**Architecture:** New stateless service `AudioFileEditor` rewrites WAVs via `AVAudioFile`; new helper `AudioWaveform` produces decimated peaks; new SwiftUI `AudioWaveformEditor` + `AudioEditorSheet` provide the modal UI launched from `MeetingView`. `AudioRecorderService.start()` posts a local `UNNotification` on success. All long-running edits flow through `JobQueue` for cancellation and visibility in the sidebar.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation (`AVAudioFile`, `AVAudioPCMBuffer`), `UserNotifications`, XCTest.

---

## File map

| Path | Responsibility |
|---|---|
| `OneToOne/Services/AudioFileEditor.swift` (new) | `trim(url:from:)`, `split(url:at:)`, `duration(url:)` — pure WAV IO. |
| `OneToOne/Services/AudioWaveform.swift` (new) | `peaks(url:count:)` → `[Float]` decimated PCM magnitudes. |
| `OneToOne/Services/JobQueue.swift` (modify) | Add `.audioEdit` case to `JobKind`. |
| `OneToOne/Services/MeetingNotificationService.swift` (modify) | `notifyRecordingStarted(meetingTitle:)`, register `RECORDING_STARTED` category. |
| `OneToOne/Services/AudioRecorderService.swift` (modify) | Post recording-started notif after successful `start()`. |
| `OneToOne/Models/AppSettings.swift` (modify) | New `notifRecordingStart: Bool = true`. |
| `OneToOne/Views/SettingsView.swift` (modify) | Toggle for `notifRecordingStart`. |
| `OneToOne/Views/AudioWaveformEditor.swift` (new) | Canvas + draggable marker + play/pause. |
| `OneToOne/Views/AudioEditorSheet.swift` (new) | Modal hosting the editor; trim and split flows. |
| `OneToOne/Views/MeetingView.swift` (modify) | Toolbar buttons "Couper début" / "Diviser" + sheet wiring + post-edit cleanup. |
| `OneToOne/Views/Meeting/JobQueueSidebar.swift` (modify) | Icon mapping for `.audioEdit`. |
| `Tests/AudioFileEditorTests.swift` (new) | Synthetic sine-wave round-trip checks. |
| `Tests/AudioWaveformTests.swift` (new) | Peak count + magnitude bounds. |

Total: 8 new files, 6 modifications.

---

### Task 1: Add `.audioEdit` case to JobQueue

**Files:**
- Modify: `OneToOne/Services/JobQueue.swift:16`
- Modify: `OneToOne/Views/JobQueueSidebar.swift` (icon mapping)

- [ ] **Step 1: Extend `JobKind`**

In `OneToOne/Services/JobQueue.swift`, replace:
```swift
enum JobKind: String { case transcription, report }
```
with:
```swift
enum JobKind: String { case transcription, report, audioEdit }
```

- [ ] **Step 2: Map icon + label for audioEdit in sidebar**

In `OneToOne/Views/JobQueueSidebar.swift`, locate `Text(job.kind == .transcription ? "Transcription" : "Rapport IA")` and replace with:
```swift
Text(jobKindLabel(job.kind))
```
Add the helper at the bottom of the struct:
```swift
private func jobKindLabel(_ k: JobQueue.JobKind) -> String {
    switch k {
    case .transcription: return "Transcription"
    case .report:        return "Rapport IA"
    case .audioEdit:     return "Édition audio"
    }
}
```
Find the `case .running:` line in `jobIcon(_:)` and replace the whole switch with:
```swift
switch job.status {
case .running:
    let sf: String
    switch job.kind {
    case .transcription: sf = "waveform"
    case .report:        sf = "wand.and.stars"
    case .audioEdit:     sf = "scissors"
    }
    Image(systemName: sf).foregroundStyle(Color.accentColor)
case .cancelling: Image(systemName: "xmark.circle").foregroundStyle(.orange)
case .succeeded:  Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
case .cancelled:  Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
case .failed:     Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/JobQueue.swift OneToOne/Views/JobQueueSidebar.swift
git commit -m "feat(jobqueue): add .audioEdit case + sidebar icon"
```

---

### Task 2: `AudioFileEditor.duration()`

**Files:**
- Create: `OneToOne/Services/AudioFileEditor.swift`
- Create: `Tests/AudioFileEditorTests.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/AudioFileEditorTests.swift`:
```swift
import XCTest
import AVFoundation
@testable import OneToOne

final class AudioFileEditorTests: XCTestCase {

    /// Génère un WAV 16-bit PCM mono 16 kHz à 440 Hz, durée `seconds`.
    func makeSyntheticWAV(seconds: Double) throws -> URL {
        let sr: Double = 16_000
        let frameCount = AVAudioFrameCount(sr * seconds)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: sr, channels: 1,
                                   interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let ptr = buffer.int16ChannelData![0]
        for i in 0..<Int(frameCount) {
            let s = sin(2.0 * .pi * 440.0 * Double(i) / sr)
            ptr[i] = Int16(s * 16_000)  // ~50% amplitude
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synth-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func test_duration_returnsExpectedSeconds() throws {
        let url = try makeSyntheticWAV(seconds: 5.0)
        defer { try? FileManager.default.removeItem(at: url) }
        let d = AudioFileEditor.duration(url: url)
        XCTAssertEqual(d, 5.0, accuracy: 0.05)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioFileEditorTests/test_duration_returnsExpectedSeconds`
Expected: FAIL `cannot find 'AudioFileEditor' in scope`.

- [ ] **Step 3: Create `AudioFileEditor` with `duration()`**

In `OneToOne/Services/AudioFileEditor.swift`:
```swift
import Foundation
import AVFoundation
import os

private let editorLog = Logger(subsystem: "com.onetoone.app", category: "audio-editor")

/// Stateless WAV editor. All operations rewrite files on disk atomically and
/// run off-main via `Task.detached` for large files.
struct AudioFileEditor {

    /// Total duration via AVAudioFile.length / sampleRate. Returns 0 on error.
    static func duration(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sr = file.processingFormat.sampleRate
        guard sr > 0 else { return 0 }
        return Double(file.length) / sr
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioFileEditorTests/test_duration_returnsExpectedSeconds`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/AudioFileEditor.swift Tests/AudioFileEditorTests.swift
git commit -m "feat(audio): AudioFileEditor.duration()"
```

---

### Task 3: `AudioFileEditor.trim(url:from:)`

**Files:**
- Modify: `OneToOne/Services/AudioFileEditor.swift`
- Modify: `Tests/AudioFileEditorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AudioFileEditorTests.swift`:
```swift
extension AudioFileEditorTests {
    func test_trim_dropsLeadingSeconds() async throws {
        let url = try makeSyntheticWAV(seconds: 6.0)
        defer { try? FileManager.default.removeItem(at: url) }
        try await AudioFileEditor.trim(url: url, from: 2.0)
        let d = AudioFileEditor.duration(url: url)
        XCTAssertEqual(d, 4.0, accuracy: 0.05)
    }

    func test_trim_throws_whenFromSecExceedsDuration() async throws {
        let url = try makeSyntheticWAV(seconds: 3.0)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await AudioFileEditor.trim(url: url, from: 5.0)
            XCTFail("trim should throw when fromSec >= duration")
        } catch { /* expected */ }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AudioFileEditorTests/test_trim_dropsLeadingSeconds`
Expected: FAIL with `static member 'trim' …`.

- [ ] **Step 3: Implement `trim(url:from:)`**

Append to `OneToOne/Services/AudioFileEditor.swift`:
```swift
extension AudioFileEditor {

    /// Rewrite `url` keeping only samples from `fromSec` onward. Atomic:
    /// writes a `.tmp.wav` sibling then replaces the original.
    /// Throws if `fromSec` >= total duration.
    static func trim(url: URL, from fromSec: Double) async throws {
        let total = duration(url: url)
        guard fromSec > 0, fromSec < total else {
            throw NSError(domain: "AudioFileEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Position invalide"])
        }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".tmp.wav")
        try? FileManager.default.removeItem(at: tmp)

        try await Task.detached(priority: .userInitiated) {
            let src = try AVAudioFile(forReading: url)
            let format = src.processingFormat
            let dst = try AVAudioFile(forWriting: tmp, settings: src.fileFormat.settings)
            let startFrame = AVAudioFramePosition(fromSec * format.sampleRate)
            src.framePosition = startFrame
            let chunk: AVAudioFrameCount = 8192
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
            while src.framePosition < src.length {
                try Task.checkCancellation()
                try src.read(into: buf)
                if buf.frameLength == 0 { break }
                try dst.write(from: buf)
            }
        }.value

        // Atomic replace.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        editorLog.info("trim done from=\(fromSec)s")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AudioFileEditorTests/test_trim`
Expected: PASS 2/2.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/AudioFileEditor.swift Tests/AudioFileEditorTests.swift
git commit -m "feat(audio): AudioFileEditor.trim atomic from offset"
```

---

### Task 4: `AudioFileEditor.split(url:at:)`

**Files:**
- Modify: `OneToOne/Services/AudioFileEditor.swift`
- Modify: `Tests/AudioFileEditorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AudioFileEditorTests.swift`:
```swift
extension AudioFileEditorTests {
    func test_split_producesTwoFilesOfExpectedLengths() async throws {
        let url = try makeSyntheticWAV(seconds: 10.0)
        let (a, b) = try await AudioFileEditor.split(url: url, at: 4.0)
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        XCTAssertEqual(AudioFileEditor.duration(url: a), 4.0, accuracy: 0.05)
        XCTAssertEqual(AudioFileEditor.duration(url: b), 6.0, accuracy: 0.05)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "Original file must be removed after split")
    }

    func test_split_throws_whenCutTooCloseToEdge() async throws {
        let url = try makeSyntheticWAV(seconds: 5.0)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await AudioFileEditor.split(url: url, at: 0.5)
            XCTFail("split should refuse cuts < 1s from start")
        } catch { /* expected */ }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AudioFileEditorTests/test_split`
Expected: FAIL with `static member 'split' …`.

- [ ] **Step 3: Implement `split(url:at:)`**

Append to `OneToOne/Services/AudioFileEditor.swift`:
```swift
extension AudioFileEditor {

    /// Split `url` at `cutSec` into two WAVs. Returns `(urlA, urlB)`. The
    /// original is removed after both new files are written successfully.
    /// Throws if `cutSec < 1s` or `cutSec > duration - 1s`.
    static func split(url: URL, at cutSec: Double) async throws -> (URL, URL) {
        let total = duration(url: url)
        guard cutSec >= 1.0, cutSec <= total - 1.0 else {
            throw NSError(domain: "AudioFileEditor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Position de coupe trop proche d'un bord"])
        }
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let urlA = dir.appendingPathComponent("\(base)_A.wav")
        let urlB = dir.appendingPathComponent("\(base)_B.wav")
        try? FileManager.default.removeItem(at: urlA)
        try? FileManager.default.removeItem(at: urlB)

        do {
            try await Task.detached(priority: .userInitiated) {
                let src = try AVAudioFile(forReading: url)
                let format = src.processingFormat
                let cutFrame = AVAudioFramePosition(cutSec * format.sampleRate)
                let chunk: AVAudioFrameCount = 8192
                let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!

                // Part A: 0 ..< cutFrame
                let dstA = try AVAudioFile(forWriting: urlA, settings: src.fileFormat.settings)
                src.framePosition = 0
                while src.framePosition < cutFrame {
                    try Task.checkCancellation()
                    let remaining = AVAudioFrameCount(cutFrame - src.framePosition)
                    buf.frameLength = min(chunk, remaining)
                    try src.read(into: buf, frameCount: buf.frameLength)
                    if buf.frameLength == 0 { break }
                    try dstA.write(from: buf)
                }

                // Part B: cutFrame ..< end
                let dstB = try AVAudioFile(forWriting: urlB, settings: src.fileFormat.settings)
                src.framePosition = cutFrame
                while src.framePosition < src.length {
                    try Task.checkCancellation()
                    try src.read(into: buf)
                    if buf.frameLength == 0 { break }
                    try dstB.write(from: buf)
                }
            }.value
        } catch {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
            throw error
        }

        try FileManager.default.removeItem(at: url)
        editorLog.info("split done at=\(cutSec)s")
        return (urlA, urlB)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AudioFileEditorTests/test_split`
Expected: PASS 2/2.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/AudioFileEditor.swift Tests/AudioFileEditorTests.swift
git commit -m "feat(audio): AudioFileEditor.split + edge-case guards"
```

---

### Task 5: `AudioWaveform.peaks()`

**Files:**
- Create: `OneToOne/Services/AudioWaveform.swift`
- Create: `Tests/AudioWaveformTests.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/AudioWaveformTests.swift`:
```swift
import XCTest
import AVFoundation
@testable import OneToOne

final class AudioWaveformTests: XCTestCase {

    func makeSyntheticWAV(seconds: Double, amplitude: Double = 0.5) throws -> URL {
        let sr: Double = 16_000
        let frameCount = AVAudioFrameCount(sr * seconds)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: sr, channels: 1,
                                   interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let ptr = buffer.int16ChannelData![0]
        for i in 0..<Int(frameCount) {
            let s = sin(2.0 * .pi * 440.0 * Double(i) / sr) * amplitude
            ptr[i] = Int16(s * 32_767)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func test_peaks_returnsRequestedCountInUnitInterval() async throws {
        let url = try makeSyntheticWAV(seconds: 4.0, amplitude: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = try await AudioWaveform.peaks(url: url, count: 100)
        XCTAssertEqual(p.count, 100)
        for v in p {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
        let maxP = p.max() ?? 0
        XCTAssertGreaterThan(maxP, 0.3, "Peak should reflect the 0.5 amplitude")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioWaveformTests`
Expected: FAIL `cannot find 'AudioWaveform' in scope`.

- [ ] **Step 3: Implement `AudioWaveform`**

In `OneToOne/Services/AudioWaveform.swift`:
```swift
import Foundation
import AVFoundation

/// Reads a WAV, returns `count` decimated peak magnitudes in `[0.0, 1.0]`.
/// Each bucket = max absolute sample over its frame range.
struct AudioWaveform {

    static func peaks(url: URL, count: Int) async throws -> [Float] {
        let safeCount = max(1, min(count, 2_000))
        return try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let total = file.length
            guard total > 0 else { return [Float](repeating: 0, count: safeCount) }
            let bucketSize = max(AVAudioFrameCount(1), AVAudioFrameCount(total / Int64(safeCount)))
            var result: [Float] = []
            result.reserveCapacity(safeCount)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bucketSize)!
            file.framePosition = 0
            while file.framePosition < total, result.count < safeCount {
                buf.frameLength = 0
                try file.read(into: buf, frameCount: bucketSize)
                let n = Int(buf.frameLength)
                if n == 0 { break }
                var peak: Float = 0
                if let p = buf.floatChannelData?[0] {
                    for i in 0..<n { peak = max(peak, abs(p[i])) }
                } else if let p = buf.int16ChannelData?[0] {
                    for i in 0..<n {
                        let v = Float(abs(p[i])) / 32_767.0
                        if v > peak { peak = v }
                    }
                }
                result.append(min(peak, 1.0))
            }
            while result.count < safeCount { result.append(0) }
            return result
        }.value
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioWaveformTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/AudioWaveform.swift Tests/AudioWaveformTests.swift
git commit -m "feat(audio): AudioWaveform.peaks (decimated PCM)"
```

---

### Task 6: Notification at recording start — setting + service

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift`
- Modify: `OneToOne/Services/MeetingNotificationService.swift`

- [ ] **Step 1: Add the setting**

In `OneToOne/Models/AppSettings.swift`, locate the block:
```swift
var notifMeetingStart: Bool = true
```
Insert below it:
```swift
/// Bannière de confirmation au démarrage de l'enregistrement.
var notifRecordingStart: Bool = true
```

- [ ] **Step 2: Register the RECORDING_STARTED category**

In `OneToOne/Services/MeetingNotificationService.swift`, locate `private enum Category {` and add:
```swift
static let recording = "RECORDING_STARTED"
```

In `registerCategories()`, replace the `setNotificationCategories` call with:
```swift
let recordingCat = UNNotificationCategory(identifier: Category.recording,
                                          actions: [],
                                          intentIdentifiers: [])
center.setNotificationCategories([preStartCat, startCat, endCat, recordingCat])
```

- [ ] **Step 3: Add the public API**

Append in `MeetingNotificationService` (inside the class, after `snoozePreStart`):
```swift
/// Bannière immédiate "Enregistrement en cours". Auto-dismiss, sans action.
func notifyRecordingStarted(meetingTitle: String) {
    let content = UNMutableNotificationContent()
    content.title = "Enregistrement en cours"
    content.body = meetingTitle.isEmpty ? "Réunion en capture" : meetingTitle
    content.sound = .default
    content.categoryIdentifier = Category.recording
    content.interruptionLevel = .active
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
    let id = "recording.start.\(UUID().uuidString)"
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    center.add(request) { error in
        if let error { print("[MeetingNotificationService] recording: \(error)") }
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Models/AppSettings.swift OneToOne/Services/MeetingNotificationService.swift
git commit -m "feat(notif): recording-started banner + setting"
```

---

### Task 7: Hook recording-started in `AudioRecorderService`

**Files:**
- Modify: `OneToOne/Services/AudioRecorderService.swift`

- [ ] **Step 1: Locate the start() success branch**

Find the line near `audioLog.info("AudioRecorder: start \(fileURL.path, privacy: .public)")` (around line 163).

- [ ] **Step 2: Post the notification after the log line**

Just after `self.activeMeetingID = meetingID`, add:
```swift
// Bannière "Enregistrement en cours" si activée dans les réglages.
if let container = OneToOneApp.sharedContainer {
    let ctx = container.mainContext
    if let settings = (try? ctx.fetch(FetchDescriptor<AppSettings>()))?.first,
       settings.notifRecordingStart {
        let title: String
        if let id = meetingID {
            let descriptor = FetchDescriptor<Meeting>()
            let all = (try? ctx.fetch(descriptor)) ?? []
            title = all.first { $0.ensuredStableID == id }?.title ?? ""
        } else {
            title = ""
        }
        MeetingNotificationService.shared.notifyRecordingStarted(meetingTitle: title)
    }
}
```
Ensure `import SwiftData` is present at the top of the file; add it if missing.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/AudioRecorderService.swift
git commit -m "feat(notif): post recording-started banner from recorder.start()"
```

---

### Task 8: Settings UI toggle

**Files:**
- Modify: `OneToOne/Views/SettingsView.swift`

- [ ] **Step 1: Add the toggle**

Locate the line:
```swift
Toggle("Pré-rappel avant la réunion (style Outlook)", isOn: Binding(
```
Just above it (so the recording toggle appears first), insert:
```swift
Toggle("Notification au démarrage de l'enregistrement", isOn: Binding(
    get: { settings.notifRecordingStart },
    set: { settings.notifRecordingStart = $0; saveSettings() }
))
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): toggle notifRecordingStart"
```

---

### Task 9: `AudioWaveformEditor` view

**Files:**
- Create: `OneToOne/Views/AudioWaveformEditor.swift`

- [ ] **Step 1: Create the view**

In `OneToOne/Views/AudioWaveformEditor.swift`:
```swift
import SwiftUI
import AVFoundation

/// Waveform interactive avec marqueur draggable et lecture audio.
/// Le parent contrôle `markerSeconds` (binding) pour exécuter trim/split.
struct AudioWaveformEditor: View {
    let url: URL
    @Binding var markerSeconds: Double
    @StateObject private var player = AudioPlayerService()
    @State private var peaks: [Float] = []
    @State private var isLoadingPeaks = true
    @State private var totalDuration: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if isLoadingPeaks {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Canvas { ctx, size in
                            drawPeaks(ctx: ctx, size: size)
                        }
                    }
                    markerLine(width: geo.size.width, height: geo.size.height)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in moveMarker(to: g.location.x, width: geo.size.width) }
                )
            }
            .frame(height: 120)

            controls
        }
        .task { await loadPeaks() }
    }

    private func drawPeaks(ctx: GraphicsContext, size: CGSize) {
        guard !peaks.isEmpty else { return }
        let midY = size.height / 2
        let barWidth = size.width / CGFloat(peaks.count)
        var path = Path()
        for (i, p) in peaks.enumerated() {
            let x = CGFloat(i) * barWidth + barWidth / 2
            let h = CGFloat(p) * (size.height / 2 - 4)
            path.move(to: CGPoint(x: x, y: midY - h))
            path.addLine(to: CGPoint(x: x, y: midY + h))
        }
        ctx.stroke(path, with: .color(.secondary.opacity(0.65)), lineWidth: max(1, barWidth - 1))
    }

    private func markerLine(width: CGFloat, height: CGFloat) -> some View {
        let x = totalDuration > 0 ? CGFloat(markerSeconds / totalDuration) * width : 0
        return Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: height)
            .offset(x: x)
    }

    private func moveMarker(to x: CGFloat, width: CGFloat) {
        guard totalDuration > 0 else { return }
        let clamped = min(max(x, 0), width)
        markerSeconds = Double(clamped / width) * totalDuration
        player.seek(to: markerSeconds)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if player.isPlaying { player.pause() } else {
                    try? player.load(url: url)
                    player.seek(to: markerSeconds)
                    player.play()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)

            Text(format(markerSeconds))
                .font(.body.monospacedDigit())
            Text("/")
                .foregroundStyle(.tertiary)
            Text(format(totalDuration))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Slider(value: $markerSeconds, in: 0...max(totalDuration, 0.01)) { editing in
                if !editing { player.seek(to: markerSeconds) }
            }
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 4)
    }

    private func loadPeaks() async {
        totalDuration = AudioFileEditor.duration(url: url)
        do {
            peaks = try await AudioWaveform.peaks(url: url, count: 600)
        } catch {
            peaks = []
        }
        isLoadingPeaks = false
    }

    private func format(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/AudioWaveformEditor.swift
git commit -m "feat(audio): AudioWaveformEditor draggable marker view"
```

---

### Task 10: `AudioEditorSheet` — trim mode

**Files:**
- Create: `OneToOne/Views/AudioEditorSheet.swift`

- [ ] **Step 1: Create the sheet skeleton**

In `OneToOne/Views/AudioEditorSheet.swift`:
```swift
import SwiftUI
import SwiftData

enum AudioEditMode: String, Identifiable {
    case trim, split
    var id: String { rawValue }
}

/// Modal d'édition audio. Mode `.trim` rewrites the original WAV in place;
/// mode `.split` produces two files and reassigns part B to another meeting.
struct AudioEditorSheet: View {
    let meeting: Meeting
    let mode: AudioEditMode
    let onFinish: (_ trimmedOrSplit: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var markerSeconds: Double = 0
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let url = meeting.wavFileURL {
                AudioWaveformEditor(url: url, markerSeconds: $markerSeconds)
            } else {
                Text("Fichier audio introuvable.").foregroundStyle(.red)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 360)
    }

    private var header: some View {
        HStack {
            Image(systemName: mode == .trim ? "scissors" : "rectangle.split.2x1")
            Text(mode == .trim ? "Couper le début" : "Diviser l'enregistrement")
                .font(.headline)
            Spacer()
            Button("Fermer") { dismiss() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch mode {
        case .trim:
            HStack {
                Spacer()
                Button(role: .destructive) {
                    Task { await runTrim() }
                } label: {
                    Label("Couper le début à \(format(markerSeconds))",
                          systemImage: "scissors")
                }
                .disabled(markerSeconds < 1 || isWorking)
            }
        case .split:
            Text("Étape 2 — choix de la cible — implémentée à la tâche suivante.")
                .foregroundStyle(.secondary)
        }
    }

    private func runTrim() async {
        guard let url = meeting.wavFileURL else { return }
        isWorking = true
        defer { isWorking = false }
        let queue = JobQueue.shared
        _ = queue.start(
            kind: .audioEdit,
            meetingID: meeting.persistentModelID,
            meetingTitle: meeting.title + " · trim"
        ) { _ in
            do {
                try await AudioFileEditor.trim(url: url, from: markerSeconds)
                await MainActor.run {
                    meeting.durationSeconds = Int(AudioFileEditor.duration(url: url))
                    invalidateTranscriptArtifacts(of: meeting, in: context)
                    try? context.save()
                    onFinish(true)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
                throw error
            }
        }
    }

    private func format(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

/// Vide les artefacts de transcription après une édition audio. Les
/// `ReportRevision` sont conservées mais devront être régénérées par l'utilisateur.
func invalidateTranscriptArtifacts(of meeting: Meeting, in context: ModelContext) {
    meeting.rawTranscript = ""
    meeting.mergedTranscript = ""
    meeting.summary = ""
    for seg in meeting.transcriptSegments { context.delete(seg) }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/AudioEditorSheet.swift
git commit -m "feat(audio): AudioEditorSheet trim mode"
```

---

### Task 11: `AudioEditorSheet` — split mode + target picker

**Files:**
- Modify: `OneToOne/Views/AudioEditorSheet.swift`

- [ ] **Step 1: Add state for split flow**

At the top of `AudioEditorSheet` (after the existing `@State` declarations), add:
```swift
@State private var splitStage: SplitStage = .pickPosition
@State private var splitTarget: SplitTarget = .newMeeting
@State private var existingTargetID: PersistentIdentifier?
@Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]

enum SplitStage { case pickPosition, pickTarget }
enum SplitTarget: String, Identifiable, CaseIterable {
    case newMeeting, existing
    var id: String { rawValue }
}
```

- [ ] **Step 2: Replace the `.split` footer branch**

In the `footer` view-builder, replace the entire `case .split:` block with:
```swift
case .split:
    switch splitStage {
    case .pickPosition:
        HStack {
            Spacer()
            Button {
                splitStage = .pickTarget
            } label: {
                Label("Diviser ici (\(format(markerSeconds)))",
                      systemImage: "rectangle.split.2x1")
            }
            .disabled(markerSeconds < 1)
        }
    case .pickTarget:
        splitTargetForm
    }
```

- [ ] **Step 3: Add the target-picker form**

Append inside `AudioEditorSheet`:
```swift
private var splitTargetForm: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Affecter le second morceau à :").font(.subheadline.bold())
        Picker("", selection: $splitTarget) {
            Text("Nouvelle réunion").tag(SplitTarget.newMeeting)
            Text("Réunion existante").tag(SplitTarget.existing)
        }
        .pickerStyle(.radioGroup)

        if splitTarget == .existing {
            Picker("Réunion", selection: Binding(
                get: { existingTargetID },
                set: { existingTargetID = $0 }
            )) {
                Text("— choisir —").tag(PersistentIdentifier?.none)
                ForEach(candidateMeetings, id: \.persistentModelID) { m in
                    Text("\(formatDate(m.date)) — \(m.title)")
                        .tag(Optional(m.persistentModelID))
                }
            }
            .pickerStyle(.menu)
        }

        HStack {
            Button("Retour") { splitStage = .pickPosition }
            Spacer()
            Button(role: .destructive) {
                Task { await runSplit() }
            } label: {
                Label("Confirmer", systemImage: "checkmark")
            }
            .disabled(isWorking ||
                      (splitTarget == .existing && existingTargetID == nil))
        }
        .padding(.top, 4)
    }
}

/// Réunions du même jour ± 1 jour, excluant la source.
private var candidateMeetings: [Meeting] {
    let cal = Calendar.current
    let lower = cal.date(byAdding: .day, value: -1, to: meeting.date) ?? meeting.date
    let upper = cal.date(byAdding: .day, value: 1, to: meeting.date) ?? meeting.date
    return allMeetings
        .filter { $0.persistentModelID != meeting.persistentModelID }
        .filter { $0.date >= lower && $0.date <= upper }
}

private func formatDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = "d MMM HH:mm"
    return f.string(from: d)
}

private func runSplit() async {
    guard let url = meeting.wavFileURL else { return }
    isWorking = true
    defer { isWorking = false }
    let queue = JobQueue.shared
    let cut = markerSeconds
    _ = queue.start(
        kind: .audioEdit,
        meetingID: meeting.persistentModelID,
        meetingTitle: meeting.title + " · split"
    ) { _ in
        do {
            let (urlA, urlB) = try await AudioFileEditor.split(url: url, at: cut)
            await MainActor.run {
                // Part A → source meeting
                meeting.wavFilePath = urlA.path
                meeting.durationSeconds = Int(AudioFileEditor.duration(url: urlA))
                invalidateTranscriptArtifacts(of: meeting, in: context)

                // Part B → target meeting
                let target = resolveTargetMeeting(cutSec: cut)
                target.wavFilePath = urlB.path
                target.durationSeconds = Int(AudioFileEditor.duration(url: urlB))
                invalidateTranscriptArtifacts(of: target, in: context)

                try? context.save()
                onFinish(true)
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
            throw error
        }
    }
}

@MainActor
private func resolveTargetMeeting(cutSec: Double) -> Meeting {
    switch splitTarget {
    case .existing:
        if let id = existingTargetID,
           let m = allMeetings.first(where: { $0.persistentModelID == id }) {
            return m
        }
        return makeNewMeeting(cutSec: cutSec)
    case .newMeeting:
        return makeNewMeeting(cutSec: cutSec)
    }
}

@MainActor
private func makeNewMeeting(cutSec: Double) -> Meeting {
    let new = Meeting(
        title: "\(meeting.title) — partie 2",
        date: meeting.date.addingTimeInterval(cutSec),
        notes: ""
    )
    new.kind = meeting.kind
    new.project = meeting.project
    new.participants = meeting.participants
    context.insert(new)
    return new
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/AudioEditorSheet.swift
git commit -m "feat(audio): split flow with target picker"
```

---

### Task 12: Wire toolbar buttons in `MeetingView`

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Add state for the editor sheet**

In `MeetingView`, near the other `@State` declarations (around line 84), add:
```swift
@State private var audioEditMode: AudioEditMode?
```

- [ ] **Step 2: Add the toolbar above the transcript / player section**

Locate the place where `transcriptView` is shown (search for `case .transcript:`). Just above the `ScrollView` of that view, prepend a `HStack` of buttons. Replace:
```swift
case .transcript:
    transcriptView
```
with:
```swift
case .transcript:
    VStack(spacing: 0) {
        audioEditingToolbar
        transcriptView
    }
```

Then add the helper view above `transcriptView`:
```swift
@ViewBuilder
private var audioEditingToolbar: some View {
    HStack(spacing: 8) {
        Button {
            audioEditMode = .trim
        } label: {
            Label("Couper début", systemImage: "scissors")
        }
        .disabled(!canEditAudio)

        Button {
            audioEditMode = .split
        } label: {
            Label("Diviser", systemImage: "rectangle.split.2x1")
        }
        .disabled(!canEditAudio)

        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
}

/// Boutons disabled si pas de WAV, enregistrement en cours, ou job actif.
private var canEditAudio: Bool {
    guard meeting.wavFileURL != nil else { return false }
    if recorder.isRecording, recorder.activeMeetingID == meeting.ensuredStableID { return false }
    let active = JobQueue.shared.activeJobs.contains { $0.meetingID == meeting.persistentModelID }
    return !active
}
```

If `recorder` isn't yet referenced in this file, add at the top of `MeetingView`:
```swift
@ObservedObject private var recorder = AudioRecorderService.shared
```

- [ ] **Step 3: Attach the sheet**

At the bottom of the outermost `VStack` in `MeetingView.body` (just before the closing brace of the body's content), add:
```swift
.sheet(item: $audioEditMode) { mode in
    AudioEditorSheet(meeting: meeting, mode: mode) { _ in }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(audio): toolbar Couper début / Diviser + sheet wiring"
```

---

### Task 13: Cleanup leftover `.tmp.wav`

**Files:**
- Modify: `OneToOne/Views/AudioEditorSheet.swift`

- [ ] **Step 1: Add cleanup on appear**

In `AudioEditorSheet.swift`, locate the outer `VStack` of `body`. Append after `.frame(minWidth: 720, minHeight: 360)`:
```swift
.onAppear {
    cleanupStaleTmp()
}
```
Add the helper inside the struct:
```swift
/// Supprime un éventuel `<wav>.tmp.wav` orphelin (crash pendant trim)
/// vieux de plus de 5 minutes.
private func cleanupStaleTmp() {
    guard let url = meeting.wavFileURL else { return }
    let tmp = url.deletingLastPathComponent()
        .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".tmp.wav")
    guard FileManager.default.fileExists(atPath: tmp.path),
          let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
          let mtime = attrs[.modificationDate] as? Date else { return }
    if Date().timeIntervalSince(mtime) > 5 * 60 {
        try? FileManager.default.removeItem(at: tmp)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/AudioEditorSheet.swift
git commit -m "feat(audio): cleanup stale .tmp.wav on sheet open"
```

---

### Task 14: Banner "transcription absente" in the report tab

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Add the banner above the report content**

In `MeetingView.reportView`, locate `if meeting.summary.isEmpty {`. Just before the outer `if` (still inside the `VStack`), add:
```swift
if !meeting.reportRevisions.isEmpty,
   meeting.rawTranscript.isEmpty {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text("Transcription supprimée après édition audio — re-transcrire pour mettre à jour le rapport.")
            .font(.caption)
        Spacer()
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(audio): banner transcription absente après édition"
```

---

### Task 15: Final integration build + test

**Files:** (none)

- [ ] **Step 1: Run full test suite**

Run: `swift test --filter AudioFileEditorTests`
Expected: PASS 4/4.

Run: `swift test --filter AudioWaveformTests`
Expected: PASS 1/1.

- [ ] **Step 2: Run full build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Final commit (empty if everything already committed)**

```bash
git log --oneline -15
```
Confirm tasks 1–14 are all committed with `feat(audio):` or related prefix.

---

## Self-review

**Spec coverage:**
- 3 architectural files (Editor, Waveform, Sheet) → Tasks 2-5, 9-11. ✓
- Notification at recording start → Tasks 6, 7, 8. ✓
- Trim atomic via tmp + replace → Task 3. ✓
- Split with edge guards → Task 4. ✓
- Hereinafter Option C (existing or new meeting) → Task 11. ✓
- Waveform UX with draggable marker (Option C UI) → Task 9. ✓
- Effets de bord (purge transcript/segments, ReportRevision kept + banner) → Tasks 10, 11, 14. ✓
- `.audioEdit` job kind → Task 1. ✓
- Cleanup stale `.tmp.wav` → Task 13. ✓
- Tests unitaires synthetic WAV → Tasks 2, 3, 4, 5. ✓
- Settings toggle → Task 8. ✓
- Boutons disabled si enregistrement / job actif → Task 12 (`canEditAudio`). ✓

No gaps.

**Type consistency:**
- `AudioEditMode` enum → defined Task 10, used Task 12. ✓
- `AudioFileEditor.trim` / `split` / `duration` signatures consistent across Tasks 2-4. ✓
- `JobKind.audioEdit` defined Task 1, used Tasks 10, 11. ✓
- `invalidateTranscriptArtifacts(of:in:)` defined Task 10, reused Task 11. ✓
- `markerSeconds: Double` binding consistent in Tasks 9-11. ✓

**Placeholder scan:**
- No "TBD", "implement later", "similar to". ✓
- All code blocks present. ✓
- "implémentée à la tâche suivante" in Task 10 footer is a transient placeholder for the UI itself, replaced in Task 11 step 2. ✓ (intentional incremental dev)
