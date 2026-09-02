import Foundation
import CoreGraphics
@testable import OneToOne

/// Source scriptée : rend les images dans l'ordre, puis `nil` (source disparue).
final class ScriptedFrameSource: FrameSource, @unchecked Sendable {
    private var frames: [CGImage?]
    private var index = 0
    private let lock = NSLock()

    init(frames: [CGImage?]) { self.frames = frames }

    func captureFrame() async throws -> CGImage? {
        lock.withLock {
            guard index < frames.count else { return nil }
            defer { index += 1 }
            return frames[index]
        }
    }
}

/// Source qui peut aussi lever une erreur : couvre le chemin « échec de capture »,
/// distinct de « fenêtre disparue » (`nil`).
final class FailingFrameSource: FrameSource, @unchecked Sendable {
    enum Outcome { case frame(CGImage?), failure }
    private var outcomes: [Outcome]
    private var index = 0
    private let lock = NSLock()

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func captureFrame() async throws -> CGImage? {
        let outcome: Outcome? = lock.withLock {
            guard index < outcomes.count else { return nil }
            defer { index += 1 }
            return outcomes[index]
        }
        switch outcome {
        case .frame(let image): return image
        case .failure: throw SimulatedCaptureError()
        case nil: return nil
        }
    }
}

struct SimulatedCaptureError: Error, LocalizedError {
    var errorDescription: String? { "panne simulée" }
}

/// Source dont la capture se suspend sous le contrôle du test : rend d'abord
/// `immediateFrames`, puis se suspend sur `captureFrame()` jusqu'à `resume(with:)`.
/// Permet de mettre un tick « en vol » pendant que `finish()` s'exécute, sans dépendre
/// du minutage de l'ordonnanceur.
final class SuspendingFrameSource: FrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var immediateFrames: [CGImage?]
    private var index = 0
    private var continuation: CheckedContinuation<CGImage?, Error>?
    private var suspendedContinuation: CheckedContinuation<Void, Never>?

    init(immediateFrames: [CGImage?]) { self.immediateFrames = immediateFrames }

    func captureFrame() async throws -> CGImage? {
        var immediate: CGImage?
        var hasImmediate = false
        lock.withLock {
            if index < immediateFrames.count {
                immediate = immediateFrames[index]
                hasImmediate = true
                index += 1
            }
        }
        if hasImmediate { return immediate }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
                if let suspendedContinuation {
                    self.suspendedContinuation = nil
                    suspendedContinuation.resume()
                }
            }
        }
    }

    /// Ne rend la main qu'une fois un appel à `captureFrame()` effectivement suspendu.
    func waitUntilSuspended() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if self.continuation != nil { continuation.resume() }
                else { self.suspendedContinuation = continuation }
            }
        }
    }

    func resume(with image: CGImage?) {
        let continuation: CheckedContinuation<CGImage?, Error>? = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: image)
    }
}
