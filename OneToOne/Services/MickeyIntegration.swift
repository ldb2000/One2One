import Foundation
import AppKit
import Combine
import os

private let mickeyLog = Logger(subsystem: "com.onetoone.app", category: "mickey")

/// Log vers Logger (Console.app / `log stream`) + stdout (utile pour `swift run`).
private func mlog(_ level: OSLogType = .default, _ message: String) {
    switch level {
    case .debug: mickeyLog.debug("\(message, privacy: .public)")
    case .info:  mickeyLog.info("\(message, privacy: .public)")
    case .error: mickeyLog.error("\(message, privacy: .public)")
    case .fault: mickeyLog.fault("\(message, privacy: .public)")
    default:     mickeyLog.log("\(message, privacy: .public)")
    }
    print("[Mickey] \(message)")
}

// MARK: - MeetingReport (miroir exact du modèle Mickey)
// Cf. Mickey/App/Shared/Models/IntegrationResult.swift

struct MeetingReport: Codable {
    let sessionId: String
    let date: Date
    let durationSeconds: Int
    let metadata: [String: String]?
    let summary: String
    let keyPoints: [String]
    let decisions: [String]
    let tasks: [TaskItem]
    let openQuestions: [String]
    let transcriptFull: String

    struct TaskItem: Codable {
        let title: String
        let assignee: String?
        let deadline: String?
    }
}

// MARK: - MickeyIntegration

/// Intégration OneToOne ↔ Mickey via URL scheme + App Group partagé.
///
/// Protocole (défini par Mickey `IntegrationService`):
///   mickey://start-session?type=meeting&callback=onetoone://session-done&metadata=<b64-json>
/// Retour:
///   onetoone://session-done?session_id=<uuid>
/// Résultat:
///   ~/Library/Group Containers/group.com.ldb.mickey.shared/results/<uuid>.json
///
/// OneToOne n'étant pas sandboxée (SwiftPM executable), accès direct au
/// container sans entitlement App Group.
final class MickeyIntegration: ObservableObject {
    static let shared = MickeyIntegration()

    static let appGroupIdentifier = "group.com.ldb.mickey.shared"
    static let callbackScheme = "onetoone"
    static let callbackHost = "session-done"

    /// Notification envoyée quand un `MeetingReport` a été récupéré.
    /// userInfo: ["report": MeetingReport, "metadata": [String:String]?]
    static let didReceiveReport = Notification.Name("MickeyIntegration.didReceiveReport")

    /// Sessions en attente : sessionId absent du dictionnaire tant que Mickey
    /// ne nous a pas rappelés. On conserve ici les métadonnées fournies au
    /// démarrage pour router le résultat.
    @Published private(set) var pendingMetadata: [String: [String: String]] = [:]

    private init() {}

    // MARK: - Démarrage d'une session Mickey

    /// Ouvre Mickey en mode "meeting" avec callback vers OneToOne.
    /// - Parameter metadata: champs libres (collaborator, project, interviewId…)
    /// - Returns: `false` si Mickey n'est pas joignable (scheme non installé).
    @discardableResult
    func startMeeting(metadata: [String: String] = [:]) -> Bool {
        var components = URLComponents()
        components.scheme = "mickey"
        components.host = "start-session"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "meeting"),
            URLQueryItem(name: "callback", value: "\(Self.callbackScheme)://\(Self.callbackHost)")
        ]

        if !metadata.isEmpty,
           let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            items.append(URLQueryItem(name: "metadata", value: json))
        }

        components.queryItems = items

        guard let url = components.url else {
            mlog(.error, "startMeeting: URL construction échouée")
            return false
        }

        // Pré-enregistre les métadonnées sous une clé provisoire (horodatage).
        let placeholderKey = "pending-\(Int(Date().timeIntervalSince1970 * 1000))"
        pendingMetadata[placeholderKey] = metadata

        mlog(.info, "startMeeting: open \(url.absoluteString) | metadata=\(metadata)")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(url, configuration: config) { app, error in
            if let error {
                mlog(.error, "startMeeting: NSWorkspace.open error=\(error.localizedDescription)")
            } else if let app {
                mlog(.info, "startMeeting: Mickey ouvert (bundle=\(app.bundleIdentifier ?? "?"), pid=\(app.processIdentifier))")
            } else {
                mlog(.error, "startMeeting: aucune app n'a répondu au scheme mickey://")
            }
        }
        return true
    }

    /// Reset état côté OneToOne (bouton Annuler, timeout).
    func cancelPending() {
        mlog(.info, "cancelPending: pending keys=\(self.pendingMetadata.keys.sorted())")
        pendingMetadata.removeAll()
    }

    // MARK: - Réception du callback

    /// À appeler depuis `.onOpenURL` de la scène SwiftUI.
    /// Accepte `onetoone://session-done?session_id=<uuid>`.
    func handleCallback(_ url: URL) {
        mlog(.info, "handleCallback: reçu \(url.absoluteString)")
        guard url.scheme == Self.callbackScheme,
              url.host == Self.callbackHost else {
            mlog(.error, "handleCallback: scheme/host incorrects (\(url.scheme ?? "?")/\(url.host ?? "?"))")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let sessionId = components?.queryItems?
                .first(where: { $0.name == "session_id" })?.value else {
            mlog(.error, "handleCallback: session_id manquant dans \(url.absoluteString)")
            return
        }

        mlog(.info, "handleCallback: session_id=\(sessionId)")
        loadReport(sessionId: sessionId)
    }

    // MARK: - Lecture du résultat dans l'App Group

    private func loadReport(sessionId: String) {
        let fileURL = Self.resultFileURL(sessionId: sessionId)
        mlog(.info, "loadReport: lecture \(fileURL.path)")

        readWithRetry(fileURL: fileURL, attempts: 10, delay: 0.3) { [weak self] data in
            guard let self else { return }
            guard let data else {
                mlog(.error, "loadReport: résultat introuvable après retries: \(fileURL.path)")
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let report = try decoder.decode(MeetingReport.self, from: data)
                mlog(.info, "loadReport: décodé OK sessionId=\(report.sessionId) duration=\(report.durationSeconds)s tasks=\(report.tasks.count)")
                let matched = self.consumePendingMetadata(for: report)
                var info: [AnyHashable: Any] = ["report": report]
                if let matched { info["metadata"] = matched }
                NotificationCenter.default.post(
                    name: Self.didReceiveReport,
                    object: self,
                    userInfo: info
                )
            } catch {
                mlog(.error, "loadReport: décodage MeetingReport échoué: \(error)")
            }
        }
    }

    private func consumePendingMetadata(for report: MeetingReport) -> [String: String]? {
        // Si Mickey a renvoyé les métadonnées dans le rapport, priorité à
        // celles-là (source de vérité). Sinon on vide la plus ancienne entrée
        // en attente.
        if let reportMeta = report.metadata, !reportMeta.isEmpty {
            pendingMetadata.removeAll()
            return reportMeta
        }
        guard let key = pendingMetadata.keys.sorted().first else { return nil }
        return pendingMetadata.removeValue(forKey: key)
    }

    private func readWithRetry(
        fileURL: URL,
        attempts: Int,
        delay: TimeInterval,
        completion: @escaping (Data?) -> Void
    ) {
        if let data = try? Data(contentsOf: fileURL) {
            completion(data)
            return
        }
        guard attempts > 1 else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.readWithRetry(
                fileURL: fileURL,
                attempts: attempts - 1,
                delay: delay,
                completion: completion
            )
        }
    }

    // MARK: - Chemin filesystem du container partagé

    static func resultFileURL(sessionId: String) -> URL {
        containerURL()
            .appendingPathComponent("results", isDirectory: true)
            .appendingPathComponent("\(sessionId).json")
    }

    static func containerURL() -> URL {
        // API officielle (nécessite entitlement App Group) :
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return url
        }
        // Fallback filesystem (OneToOne SwiftPM non-sandboxée) :
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)
    }
}
