import Foundation
import Contacts
import AppKit
import SwiftData

/// Fetches missing Collaborator photos from the macOS Contacts database.
/// - Looks up by email first, then by full name (case-insensitive).
/// - Stores the JPEG to Application Support/OneToOne/photos/<stableID>.jpg.
/// - Updates `Collaborator.photoPath` only on success; never overwrites
///   an existing photo.
@MainActor
final class ContactPhotoService {

    static let shared = ContactPhotoService()

    private let store = CNContactStore()
    private var refreshTask: Task<Void, Never>?
    private(set) var hasAccess: Bool = false

    private init() {}

    // MARK: - Public

    func requestAccess() async -> Bool {
        do {
            hasAccess = try await store.requestAccess(for: .contacts)
        } catch {
            hasAccess = false
        }
        return hasAccess
    }

    /// Scans Collaborators without `photoPath` and tries to populate them.
    /// Returns the number of photos applied. Safe to call repeatedly.
    @discardableResult
    func syncMissingPhotos(context: ModelContext) -> Int {
        guard hasAccess else { return 0 }
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? context.fetch(descriptor)) ?? []
        var applied = 0

        for collab in all where collab.photoPath.isEmpty {
            guard let data = lookupPhoto(for: collab) else { continue }
            guard let path = saveImage(data: data, for: collab) else { continue }
            collab.photoPath = path
            applied += 1
        }

        if applied > 0 {
            try? context.save()
            print("[ContactPhotoService] applied \(applied) photo(s).")
        }
        return applied
    }

    /// Relance le timer de synchronisation périodique selon les réglages courants.
    /// Annule la tâche précédente puis, si `contactPhotoSyncEnabled`, planifie une
    /// boucle qui appelle `syncMissingPhotos` toutes les N minutes (min. 5).
    /// La boucle s'exécute sur le `MainActor` (service `@MainActor`) ; chaque
    /// itération est repassée explicitement sur le `MainActor` pour l'accès au
    /// `ModelContext`.
    func reschedulePeriodicSync(context: ModelContext, settings: AppSettings) {
        refreshTask?.cancel()
        guard settings.contactPhotoSyncEnabled else { return }
        let interval = max(5, settings.contactPhotoSyncIntervalMinutes)
        let nanos = UInt64(interval) * 60 * 1_000_000_000

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                await MainActor.run { _ = self?.syncMissingPhotos(context: context) }
            }
        }
    }

    // MARK: - Internals

    private func lookupPhoto(for collab: Collaborator) -> Data? {
        let keys: [CNKeyDescriptor] = [
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor
        ]

        // 1. By email (preferred)
        let email = collab.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
            if let match = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys))?.first,
               match.imageDataAvailable,
               let data = match.imageData ?? match.thumbnailImageData {
                return data
            }
        }

        // 2. By name
        let name = collab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingName: name)
            if let match = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys))?.first,
               match.imageDataAvailable,
               let data = match.imageData ?? match.thumbnailImageData {
                return data
            }
        }

        return nil
    }

    private func saveImage(data: Data, for collab: Collaborator) -> String? {
        let dir = URL.applicationSupportDirectory
            .appending(path: "OneToOne", directoryHint: .isDirectory)
            .appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Fresh UUID per save — never reuse a filename based on stableID
        // (legacy collabs may share a stableID and would overwrite each other).
        let filename = "\(UUID().uuidString).jpg"
        let target = dir.appending(path: filename)
        do {
            try data.write(to: target, options: .atomic)
            return target.path
        } catch {
            print("[ContactPhotoService] saveImage failed: \(error)")
            return nil
        }
    }
}
