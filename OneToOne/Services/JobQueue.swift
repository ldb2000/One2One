import Foundation
import SwiftData
import Combine

/// File centralisée des jobs async (transcription, rapport, à étendre). Permet :
/// - une sidebar visualisant tous les jobs en cours et récemment terminés
/// - l'annulation à la demande (`task.cancel()` propagé jusqu'au worker)
/// - le suivi de progression unifié (fraction + label)
/// - une concurrence configurable par kind (ex. 1 seul `.report` à la fois,
///   les suivants attendent en `.queued`)
///
/// Pas de persistence : si l'app crashe, les jobs en cours sont perdus.
@MainActor
final class JobQueue: ObservableObject {

    static let shared = JobQueue()

    enum JobKind: String { case transcription, report, audioEdit, diarization }

    enum JobStatus: Equatable {
        case queued       // attente — limite de concurrence par kind
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
        let queuedAt: Date
        var startedAt: Date?
        var status: JobStatus
        var progress: Double?
        var statusText: String?
        var finishedAt: Date?
        var task: Task<Void, Never>?
        var work: ((UUID) async throws -> Void)?
    }

    @Published private(set) var jobs: [Job] = []

    /// Plafond du nombre de jobs terminés conservés.
    private let terminalCap = 8

    /// Concurrence max par kind. Les LLM endpoints ne supportent pas le
    /// streaming parallèle → 1 seul rapport à la fois. La transcription
    /// MLX et l'édition audio sont aussi sérialisées par sécurité.
    private let maxConcurrentByKind: [JobKind: Int] = [
        .report:        1,
        .transcription: 1,
        .audioEdit:     1,
        .diarization:   1
    ]

    @discardableResult
    func start(kind: JobKind,
               meetingID: PersistentIdentifier,
               meetingTitle: String,
               work: @escaping (UUID) async throws -> Void) -> UUID {
        let id = UUID()
        let job = Job(
            id: id,
            kind: kind,
            meetingID: meetingID,
            meetingTitle: meetingTitle.isEmpty ? "(sans titre)" : meetingTitle,
            queuedAt: Date(),
            startedAt: nil,
            status: .queued,
            progress: nil,
            statusText: nil,
            finishedAt: nil,
            task: nil,
            work: work
        )
        jobs.insert(job, at: 0)
        dispatchNextIfPossible(kind: kind)
        return id
    }

    func updateProgress(_ id: UUID, fraction: Double?, status: String?) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let f = fraction { jobs[idx].progress = f }
        if let s = status   { jobs[idx].statusText = s }
    }

    func cancel(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch jobs[idx].status {
        case .queued:
            // Annulation avant exécution — on flip directement en .cancelled.
            jobs[idx].status = .cancelled
            jobs[idx].finishedAt = Date()
            jobs[idx].work = nil
            dispatchNextIfPossible(kind: jobs[idx].kind)
        case .running:
            jobs[idx].status = .cancelling
            jobs[idx].task?.cancel()
        default:
            return
        }
    }

    func cancelAll() {
        for job in jobs where job.status == .running || job.status == .queued {
            cancel(job.id)
        }
    }

    func clearTerminal() {
        jobs.removeAll { $0.status.isTerminal }
    }

    /// Visible jobs (queued + running + cancelling) en premier, puis terminés.
    var activeJobs: [Job]   { jobs.filter { !$0.status.isTerminal } }
    var terminalJobs: [Job] { jobs.filter {  $0.status.isTerminal } }

    var hasActiveJobs: Bool { activeJobs.isEmpty == false }

    // MARK: - Internal

    /// Si la concurrence le permet pour ce `kind`, démarre le prochain job
    /// `.queued` (FIFO sur `queuedAt`).
    private func dispatchNextIfPossible(kind: JobKind) {
        let cap = maxConcurrentByKind[kind] ?? Int.max
        let runningCount = jobs.filter {
            $0.kind == kind && ($0.status == .running || $0.status == .cancelling)
        }.count
        guard runningCount < cap else { return }
        // Plus ancien d'abord (FIFO).
        guard let nextIdx = jobs
            .enumerated()
            .filter({ $0.element.kind == kind && $0.element.status == .queued })
            .min(by: { $0.element.queuedAt < $1.element.queuedAt })?
            .offset
        else { return }

        guard let work = jobs[nextIdx].work else {
            jobs[nextIdx].status = .failed("Closure manquante")
            jobs[nextIdx].finishedAt = Date()
            return
        }
        let jobID = jobs[nextIdx].id
        jobs[nextIdx].status = .running
        jobs[nextIdx].startedAt = Date()
        jobs[nextIdx].statusText = nil
        jobs[nextIdx].work = nil  // libère la closure une fois consommée
        let task = Task { [weak self] in
            do {
                try await work(jobID)
                await MainActor.run { self?.finish(id: jobID, status: .succeeded) }
            } catch is CancellationError {
                await MainActor.run { self?.finish(id: jobID, status: .cancelled) }
            } catch {
                await MainActor.run {
                    self?.finish(id: jobID, status: .failed(error.localizedDescription))
                }
            }
        }
        jobs[nextIdx].task = task
    }

    private func finish(id: UUID, status: JobStatus) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        let kind = jobs[idx].kind
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
        // Démarre le suivant en attente pour ce kind.
        dispatchNextIfPossible(kind: kind)
    }
}
