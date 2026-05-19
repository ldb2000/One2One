import Foundation
import SwiftData
import Combine

/// File centralisée des jobs async (transcription, rapport, à étendre). Permet :
/// - une sidebar visualisant tous les jobs en cours et récemment terminés
/// - l'annulation à la demande (`task.cancel()` propagé jusqu'au worker)
/// - le suivi de progression unifié (fraction + label)
///
/// Pas de persistence : si l'app crashe, les jobs en cours sont perdus.
@MainActor
final class JobQueue: ObservableObject {

    static let shared = JobQueue()

    enum JobKind: String { case transcription, report, audioEdit }
    enum JobStatus: Equatable {
        case running
        case cancelling
        case succeeded
        case cancelled
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .succeeded, .cancelled, .failed: return true
            default: return false
            }
        }
    }

    struct Job: Identifiable {
        let id: UUID
        let kind: JobKind
        let meetingID: PersistentIdentifier
        let meetingTitle: String
        let startedAt: Date
        var status: JobStatus
        var progress: Double?     // 0..1 ou nil pour indéterminé
        var statusText: String?   // ex. "Segment 9/27"
        var finishedAt: Date?
        var task: Task<Void, Never>?
    }

    @Published private(set) var jobs: [Job] = []

    /// Plafond du nombre de jobs terminés conservés. Au-delà, on évince le
    /// plus ancien pour garder la sidebar légère.
    private let terminalCap = 8

    /// Démarre un job de type `kind` et exécute `work`. Renvoie l'ID pour que
    /// l'appelant puisse mettre à jour la progression via `updateProgress`.
    @discardableResult
    func start(kind: JobKind,
               meetingID: PersistentIdentifier,
               meetingTitle: String,
               work: @escaping (UUID) async throws -> Void) -> UUID {
        let id = UUID()
        let task = Task { [weak self] in
            do {
                try await work(id)
                await MainActor.run {
                    self?.finish(id: id, status: .succeeded)
                }
            } catch is CancellationError {
                await MainActor.run { self?.finish(id: id, status: .cancelled) }
            } catch {
                await MainActor.run {
                    self?.finish(id: id, status: .failed(error.localizedDescription))
                }
            }
        }
        let job = Job(
            id: id,
            kind: kind,
            meetingID: meetingID,
            meetingTitle: meetingTitle.isEmpty ? "(sans titre)" : meetingTitle,
            startedAt: Date(),
            status: .running,
            progress: nil,
            statusText: nil,
            finishedAt: nil,
            task: task
        )
        jobs.insert(job, at: 0)
        return id
    }

    func updateProgress(_ id: UUID, fraction: Double?, status: String?) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let f = fraction { jobs[idx].progress = f }
        if let s = status   { jobs[idx].statusText = s }
    }

    func cancel(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[idx].status == .running else { return }
        jobs[idx].status = .cancelling
        jobs[idx].task?.cancel()
    }

    func cancelAll() {
        for job in jobs where job.status == .running {
            cancel(job.id)
        }
    }

    func clearTerminal() {
        jobs.removeAll { $0.status.isTerminal }
    }

    /// Visible jobs: actifs en premier, puis terminés (cap).
    var activeJobs: [Job]   { jobs.filter { !$0.status.isTerminal } }
    var terminalJobs: [Job] { jobs.filter {  $0.status.isTerminal } }

    var hasActiveJobs: Bool { activeJobs.isEmpty == false }

    // MARK: - Internal

    private func finish(id: UUID, status: JobStatus) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = status
        jobs[idx].finishedAt = Date()
        jobs[idx].task = nil
        // Éviction du plus ancien job terminé si on dépasse le cap.
        var terminalIdx = jobs.enumerated()
            .filter { $0.element.status.isTerminal }
            .map { $0.offset }
        while terminalIdx.count > terminalCap {
            if let last = terminalIdx.last {
                jobs.remove(at: last)
                terminalIdx.removeLast()
            }
        }
    }
}
