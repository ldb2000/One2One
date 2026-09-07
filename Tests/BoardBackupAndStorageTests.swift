import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Point 6 des points durs du plan (§2.4) : « `StorageStatsService`,
/// `OrphanCleanupService`, `BackupService` ne connaissent que les emplacements
/// existants : **chaque nouveau dossier de fichiers s'y enregistre** ».
///
/// Le dossier `boards/` est ce nouvel emplacement.
@Suite("Planches : sauvegarde et comptage du stockage")
@MainActor
struct BoardBackupAndStorageTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func racine() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("boards-backup-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Une planche fait l'aller-retour dans la sauvegarde, scène et vignette comprises")
    func boardSurvivesBackupRoundTrip() throws {
        let racineSource = racine()
        let racineCible = racine()
        defer {
            try? FileManager.default.removeItem(at: racineSource)
            try? FileManager.default.removeItem(at: racineCible)
        }

        // --- Source
        let source = try context()
        let store = BoardStore(recordingsRoot: racineSource)
        let reglages = AppSettings()
        source.insert(reglages)
        let reunion = Meeting(title: "Atelier GitLab",
                              date: Date(timeIntervalSince1970: 1_788_523_200),
                              notes: "")
        reunion.kind = .workshop
        source.insert(reunion)

        let planche = Board(index: 2, title: "Cible d'architecture", mode: .sketch,
                            t: 2_060, authorNames: "Yann")
        source.insert(planche)
        planche.meeting = reunion
        let scene = BoardScene.scene(boxes: [
            .init(x: 0, y: 0, width: 200, height: 60, text: "Runners GitLab")
        ])
        try store.save(scene: scene, board: planche, meeting: reunion)
        try store.saveThumbnail(Data([0x89, 0x50, 0x4E, 0x47]), board: planche, meeting: reunion)
        try source.save()

        let data = try BackupService(boardStore: store).backup(
            settings: reglages, entities: [], projects: [], collaborators: [],
            meetings: [reunion])

        // La scène est bien dans le JSON, pas seulement son chemin.
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let reunions = try #require(json["meetings"] as? [[String: Any]])
        let planches = try #require(reunions.first?["boards"] as? [[String: Any]])
        #expect(planches.count == 1)
        #expect((planches[0]["title"] as? String) == "Cible d'architecture")
        #expect((planches[0]["sceneJSON"] as? String)?.contains("Runners GitLab") == true)
        #expect(planches[0]["thumbData"] != nil)

        // --- Restauration, sur une autre racine
        let cible = try context()
        let storeCible = BoardStore(recordingsRoot: racineCible)
        try BackupService(boardStore: storeCible).restore(from: data, into: cible)

        let restaurees = try cible.fetch(FetchDescriptor<Board>())
        #expect(restaurees.count == 1)
        let restauree = try #require(restaurees.first)
        #expect(restauree.title == "Cible d'architecture")
        #expect(restauree.index == 2)
        #expect(restauree.mode == .sketch)
        #expect(restauree.t == 2_060)
        #expect(restauree.authorNames == "Yann")
        #expect(restauree.stableID == planche.stableID)
        let reunionCible = try #require(restauree.meeting)
        #expect(reunionCible.title == "Atelier GitLab")
        // Les fichiers sont réécrits **dans la nouvelle racine**, pas à leur
        // chemin d'origine, qui n'existe pas sur la machine de destination.
        #expect(storeCible.loadScene(board: restauree, meeting: reunionCible) == scene)
        #expect(storeCible.thumbnailData(board: restauree, meeting: reunionCible)
                == Data([0x89, 0x50, 0x4E, 0x47]))
        let fichier = storeCible.url(meetingStableID: reunionCible.ensuredStableID,
                                     relativePath: restauree.scenePath)
        #expect(fichier.path.hasPrefix(racineCible.path),
                "la scène restaurée doit vivre sous la racine de destination")
        #expect(FileManager.default.fileExists(atPath: fichier.path))
    }

    @Test("Une sauvegarde antérieure au lot 16, sans clé boards, se restaure")
    func backupWithoutBoardsStillRestores() throws {
        let racineSource = racine()
        defer { try? FileManager.default.removeItem(at: racineSource) }
        let source = try context()
        let reglages = AppSettings()
        source.insert(reglages)
        let collaborateur = Collaborator(name: "Yann Pichon", role: "Architecte")
        source.insert(collaborateur)
        try source.save()

        let data = try BackupService(boardStore: BoardStore(recordingsRoot: racineSource)).backup(
            settings: reglages, entities: [], projects: [], collaborators: [collaborateur])
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // On retire explicitement la clé, comme une sauvegarde d'avant le lot.
        if var reunions = json["meetings"] as? [[String: Any]] {
            for index in reunions.indices { reunions[index]["boards"] = nil }
            json["meetings"] = reunions
        }
        let ancienne = try JSONSerialization.data(withJSONObject: json)

        let cible = try context()
        try BackupService(boardStore: BoardStore(recordingsRoot: racine())).restore(
            from: ancienne, into: cible)
        #expect(try cible.fetch(FetchDescriptor<Collaborator>()).contains { $0.name == "Yann Pichon" })
        #expect(try cible.fetch(FetchDescriptor<Board>()).isEmpty)
    }

    @Test("Le dossier boards/ entre dans les statistiques de stockage")
    func storageStatsCountBoards() throws {
        // On ne rejoue pas `StorageStatsService` (qui lit le dossier de
        // production) : on vérifie que le `Stats` porte la catégorie et que le
        // total l'additionne — l'oubli le plus probable.
        var stats = StorageStatsService.Stats()
        stats.wavBytes = 1_000
        stats.slidesBytes = 200
        stats.boardsBytes = 4_096
        stats.boardsCount = 8
        #expect(stats.totalBytes == 5_296)
        #expect(stats.boardsCount == 8)
        // Le nom du dossier est **partagé** entre le magasin et le compteur :
        // deux littéraux auraient divergé.
        #expect(BoardStore.folderName == "boards")
        #expect(BoardStore.relativeScenePath(boardStableID: UUID())
            .hasPrefix(BoardStore.folderName + "/"))
    }
}
