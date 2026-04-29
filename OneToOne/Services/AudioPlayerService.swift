import Foundation
import AVFoundation
import Combine
import os

private let playerLog = Logger(subsystem: "com.onetoone.app", category: "player")

/// Lecture de fichiers WAV enregistrés par `AudioRecorderService`.
/// Un seul fichier chargé à la fois. `currentTime` rafraîchi 4x / seconde.
@MainActor
final class AudioPlayerService: NSObject, ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var lastError: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private(set) var loadedURL: URL?

    /// Charge un WAV. Si déjà chargé (même URL), conserve la position.
    func load(url: URL) throws {
        if loadedURL == url, player != nil { return }
        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.prepareToPlay()
        self.player = p
        self.loadedURL = url
        self.duration = p.duration
        self.currentTime = 0
        playerLog.info("load: \(url.path, privacy: .public) duration=\(p.duration, format: .fixed(precision: 1))s")
    }

    func play() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }

    /// Seek en secondes absolues.
    func seek(to seconds: TimeInterval) {
        guard let p = player else { return }
        let clamped = max(0, min(seconds, p.duration))
        p.currentTime = clamped
        currentTime = clamped
    }

    /// Seek relatif (+15 / -15 typiquement).
    func skip(by seconds: TimeInterval) {
        guard let p = player else { return }
        seek(to: p.currentTime + seconds)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension AudioPlayerService: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = player.duration
        stopTimer()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        lastError = error?.localizedDescription ?? "Erreur de décodage."
        isPlaying = false
        stopTimer()
    }
}
