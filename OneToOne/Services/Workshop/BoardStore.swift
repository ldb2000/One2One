import Foundation

/// Persistance des planches d'atelier : la scène JSON et la vignette PNG sur
/// **disque**, la ligne `Board` en base ne portant que les chemins (cf. le
/// doc-comment de `Board` et l'ADR du 2026-09-07).
///
/// Disposition, calquée sur `recordings/<uuid>/slides/` de `ScreenCaptureService` :
///
/// ```
/// ~/Library/Application Support/OneToOne/recordings/
///   <uuid de la réunion>/boards/<stableID de la planche>.excalidraw.json
///   <uuid de la réunion>/boards/<stableID de la planche>.png
/// ```
///
/// `recordingsRoot` et l'horloge sont **injectables** : toute la logique
/// (chemins, amortissement de la vignette) se teste sur un dossier temporaire,
/// sans jamais toucher le store de production.
@MainActor
final class BoardStore {

    /// Instance de production. Les tests construisent la leur.
    static let shared = BoardStore()

    /// Nom du sous-dossier, aussi utilisé par `StorageStatsService`.
    static let folderName = "boards"

    /// Extension complète du fichier de scène.
    static let sceneExtension = "excalidraw.json"

    /// Amortissement de la vignette (spec §7.4 : « régénérée au plus toutes les
    /// 5 s »).
    static let thumbnailInterval: TimeInterval = 5

    /// Amortissement de la sauvegarde de scène (spec §7.4 : « à chaque idle de
    /// 400 ms »). L'attente est faite côté page ; la constante vit ici pour que
    /// le pont et le test parlent du même nombre.
    static let sceneIdleInterval: TimeInterval = 0.4

    let recordingsRoot: URL
    private let now: () -> Date

    /// Dernière génération de vignette, par planche.
    private var lastThumbnailAt: [UUID: Date] = [:]

    init(recordingsRoot: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.recordingsRoot = recordingsRoot ?? AudioRecorderService.recordingsDirectory
        self.now = now
    }

    // MARK: - Chemins

    /// Chemin **relatif** de la scène, tel que stocké dans `Board.scenePath`.
    /// Relatif au dossier de la réunion : un store déplacé ou restauré ne casse
    /// pas les liens.
    static func relativeScenePath(boardStableID: UUID) -> String {
        "\(folderName)/\(boardStableID.uuidString).\(sceneExtension)"
    }

    /// Chemin relatif de la vignette, tel que stocké dans `Board.thumbPath`.
    static func relativeThumbPath(boardStableID: UUID) -> String {
        "\(folderName)/\(boardStableID.uuidString).png"
    }

    /// Dossier de la réunion.
    func meetingDirectory(meetingStableID: UUID) -> URL {
        recordingsRoot.appendingPathComponent(meetingStableID.uuidString, isDirectory: true)
    }

    /// Dossier `boards/` de la réunion.
    func boardsDirectory(meetingStableID: UUID) -> URL {
        meetingDirectory(meetingStableID: meetingStableID)
            .appendingPathComponent(Self.folderName, isDirectory: true)
    }

    /// Résout un chemin relatif de `Board` en URL absolue.
    func url(meetingStableID: UUID, relativePath: String) -> URL {
        meetingDirectory(meetingStableID: meetingStableID).appendingPathComponent(relativePath)
    }

    /// Crée `boards/` s'il manque. Appelé avant toute écriture : une racine non
    /// inscriptible doit échouer avant que l'utilisateur croie avoir dessiné.
    @discardableResult
    func createBoardsDirectory(meetingStableID: UUID) throws -> URL {
        let dossier = boardsDirectory(meetingStableID: meetingStableID)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier
    }

    // MARK: - Scène

    /// Écrit la scène et met la ligne `Board` à jour (`scenePath`, `updatedAt`).
    @discardableResult
    func save(scene: String, board: Board, meetingStableID: UUID) throws -> URL {
        try createBoardsDirectory(meetingStableID: meetingStableID)
        let identifiant = board.ensuredStableID
        let relatif = Self.relativeScenePath(boardStableID: identifiant)
        let destination = url(meetingStableID: meetingStableID, relativePath: relatif)
        try Data(scene.utf8).write(to: destination, options: .atomic)
        board.scenePath = relatif
        board.updatedAt = now()
        return destination
    }

    /// Relit la scène. `nil` quand le fichier manque — une planche dont le
    /// fichier a disparu s'ouvre vierge plutôt que de faire échouer l'écran.
    func loadScene(board: Board, meetingStableID: UUID) -> String? {
        let relatif = board.scenePath.isEmpty
            ? Self.relativeScenePath(boardStableID: board.ensuredStableID)
            : board.scenePath
        let source = url(meetingStableID: meetingStableID, relativePath: relatif)
        guard let data = try? Data(contentsOf: source) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Vignette

    /// La vignette doit-elle être régénérée ? Vrai la première fois, puis au
    /// plus une fois toutes les `thumbnailInterval` secondes. `force` sert au
    /// changement de planche, où la spec exige une vignette à jour.
    func shouldRegenerateThumbnail(boardStableID: UUID, force: Bool = false) -> Bool {
        if force { return true }
        guard let dernier = lastThumbnailAt[boardStableID] else { return true }
        return now().timeIntervalSince(dernier) >= Self.thumbnailInterval
    }

    /// Écrit la vignette, met `thumbPath` à jour et arme l'amortissement.
    func saveThumbnail(_ data: Data, board: Board, meetingStableID: UUID) throws {
        try createBoardsDirectory(meetingStableID: meetingStableID)
        let identifiant = board.ensuredStableID
        let relatif = Self.relativeThumbPath(boardStableID: identifiant)
        let destination = url(meetingStableID: meetingStableID, relativePath: relatif)
        try data.write(to: destination, options: .atomic)
        board.thumbPath = relatif
        lastThumbnailAt[identifiant] = now()
    }

    /// Données de la vignette, pour le dock et pour `BackupService`.
    func thumbnailData(board: Board, meetingStableID: UUID) -> Data? {
        guard !board.thumbPath.isEmpty else { return nil }
        return try? Data(contentsOf: url(meetingStableID: meetingStableID, relativePath: board.thumbPath))
    }

    // MARK: - Cycle de vie

    /// Copie la scène d'une planche vers une autre — la duplication du dock.
    func copyScene(from source: Board, to destination: Board, meetingStableID: UUID) throws {
        let scene = loadScene(board: source, meetingStableID: meetingStableID) ?? BoardScene.empty
        try save(scene: scene, board: destination, meetingStableID: meetingStableID)
        if let vignette = thumbnailData(board: source, meetingStableID: meetingStableID) {
            try saveThumbnail(vignette, board: destination, meetingStableID: meetingStableID)
        }
    }

    /// Supprime les fichiers d'une planche. La cascade SwiftData ne retire que
    /// la ligne : sans cet appel, le dossier `boards/` enflerait sans fin.
    func deleteFiles(board: Board, meetingStableID: UUID) {
        for relatif in [board.scenePath, board.thumbPath] where !relatif.isEmpty {
            try? FileManager.default.removeItem(
                at: url(meetingStableID: meetingStableID, relativePath: relatif))
        }
        lastThumbnailAt[board.stableID ?? UUID()] = nil
    }

    /// Réinitialise l'amortissement — utilisé par les tests et au changement de
    /// réunion.
    func resetThumbnailClock() {
        lastThumbnailAt.removeAll()
    }
}
