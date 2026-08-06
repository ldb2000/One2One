import XCTest
@testable import OneToOne

final class MediaStoreTests: XCTestCase {

    /// `markdownReference(for:)` doit produire `![alt](url)` avec l'URL
    /// absolue de `imageURL`, et retomber sur l'alt par défaut "image" si
    /// aucun n'est fourni.
    func test_markdownReference_defaultAlt() {
        let url = URL(fileURLWithPath: "/tmp/img_abc123.png")
        XCTAssertEqual(
            MediaStore.markdownReference(for: url),
            "![image](\(url.absoluteString))"
        )
    }

    func test_markdownReference_customAlt() {
        let url = URL(fileURLWithPath: "/tmp/img_abc123.png")
        XCTAssertEqual(
            MediaStore.markdownReference(for: url, alt: "capture d'écran"),
            "![capture d'écran](\(url.absoluteString))"
        )
    }

    /// `imagesDirectory` doit pointer sous `Application Support/OneToOne/images`,
    /// le même répertoire que celui documenté pour les enregistrements audio
    /// et les sauvegardes.
    func test_imagesDirectory_pointsUnderApplicationSupport() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let expected = appSupport.appendingPathComponent("OneToOne/images", isDirectory: true)
        XCTAssertEqual(MediaStore.imagesDirectory.standardizedFileURL, expected.standardizedFileURL)
    }

    // NOTE de couverture : `clipboardHasImage` et `saveClipboardImage()` ne
    // sont pas testés ici. Les deux lisent `NSPasteboard.general`, l'état
    // partagé de la machine de l'utilisateur qui exécute les tests ; un test
    // qui écrirait dedans pour se donner un cas positif altérerait ce
    // presse-papiers pendant/après l'exécution de la suite. J'ai jugé que ce
    // n'était pas acceptable pour ce test unitaire (voir le rapport de tâche
    // pour le détail). Cette lacune est donc assumée, pas masquée.

    // MARK: - attachmentsDirectory / saveFile(from:)

    func test_attachmentsDirectory_pointsUnderApplicationSupport() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let expected = appSupport.appendingPathComponent("OneToOne/attachments", isDirectory: true)
        XCTAssertEqual(MediaStore.attachmentsDirectory.standardizedFileURL, expected.standardizedFileURL)
    }

    /// La copie doit exister sur disque, à un emplacement distinct de
    /// l'original, sous le même nom de fichier ("rapport.pdf" reste
    /// "rapport.pdf") — condition nécessaire pour que
    /// `SlashController.insertFile` puisse dériver le libellé du lien
    /// inséré depuis `destination.lastPathComponent`.
    func test_saveFile_copiesToAttachmentsDirectory_preservingFileName() throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-mediastore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }
        let source = sourceDir.appendingPathComponent("rapport.pdf")
        try Data("contenu de test".utf8).write(to: source)

        let destination = try XCTUnwrap(MediaStore.saveFile(from: source))
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        XCTAssertEqual(destination.lastPathComponent, "rapport.pdf")
        XCTAssertNotEqual(destination.standardizedFileURL, source.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(destination.path.contains("OneToOne/attachments"))
        XCTAssertEqual(try Data(contentsOf: destination), Data("contenu de test".utf8))
    }

    /// Deux fichiers de même nom, joints séparément, ne doivent pas se
    /// marcher dessus : chacun reçoit son propre sous-dossier `UUID`.
    func test_saveFile_sameFileNameTwice_doesNotCollide() throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-mediastore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }
        let source = sourceDir.appendingPathComponent("rapport.pdf")
        try Data("un".utf8).write(to: source)

        let first = try XCTUnwrap(MediaStore.saveFile(from: source))
        let second = try XCTUnwrap(MediaStore.saveFile(from: source))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        XCTAssertNotEqual(first.standardizedFileURL, second.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func test_saveFile_missingSource_returnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-mediastore-does-not-exist-\(UUID().uuidString).pdf")
        XCTAssertNil(MediaStore.saveFile(from: missing))
    }
}
