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
}
