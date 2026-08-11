import XCTest
import AppKit
@testable import OneToOne

final class NativeMermaidRendererTests: XCTestCase {

    // MARK: - Syntaxe non consommée → erreur (déclenche le fallback JS)
    //
    // Les parseurs natifs vendored ignoraient en silence toute ligne non
    // reconnue : le diagramme rendait incomplet (autonumber, activations,
    // interactions… perdus), l'image partielle était mise en cache et le
    // moteur Mermaid JavaScript n'était jamais sollicité. Une ligne non
    // consommée doit faire échouer le rendu natif pour que
    // `MermaidRenderer.render` retombe sur le fallback compatible.

    func test_sequenceWithAutonumber_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "sequenceDiagram\n    autonumber\n    Alice->>Bob: Salut",
            "`autonumber` n'est pas rendu nativement : le rendu doit échouer, pas produire un diagramme incomplet"
        )
    }

    func test_sequenceWithStandaloneActivate_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "sequenceDiagram\n    Alice->>Bob: Salut\n    activate Bob",
            "`activate` seul sur sa ligne n'est pas rendu nativement"
        )
    }

    func test_flowchartWithClickInteraction_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "flowchart TD\n    A[Début] --> B[Fin]\n    click A callback",
            "`click` n'est pas rendu nativement — et créait même un nœud parasite « click »"
        )
    }

    func test_stateDiagramWithNote_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "stateDiagram-v2\n    [*] --> A\n    note right of A: bonjour",
            "les notes d'état ne sont pas rendues nativement"
        )
    }

    func test_classDiagramWithNote_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "classDiagram\n    class Canard\n    note for Canard \"peut voler\"",
            "les notes de classe ne sont pas rendues nativement"
        )
    }

    func test_erDiagramWithStyle_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "erDiagram\n    CLIENT ||--o{ COMMANDE : passe\n    style CLIENT fill:#f9f",
            "`style` d'entité n'est pas rendu nativement"
        )
    }

    func test_xychartWithUnknownStatement_throwsSoTheJSFallbackTakesOver() async {
        await assertNativeRenderThrows(
            "xychart-beta\n    x-axis [a, b]\n    bar [1, 2]\n    histogram [3, 4]",
            "une série inconnue n'est pas rendue nativement"
        )
    }

    // MARK: - Syntaxe couverte → rendu natif inchangé

    func test_simpleSequence_stillRendersNatively() async throws {
        let image = try await NativeMermaidRenderer.render(
            source: "sequenceDiagram\n    Alice->>Bob: Salut\n    Bob-->>Alice: Re",
            isDark: false
        )
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func test_flowchartWithAComment_stillRendersNatively() async throws {
        let image = try await NativeMermaidRenderer.render(
            source: "flowchart TD\n    %% commentaire\n    A[Début] --> B[Fin]",
            isDark: false
        )
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func test_simpleStateDiagram_stillRendersNatively() async throws {
        let image = try await NativeMermaidRenderer.render(
            source: "stateDiagram-v2\n    [*] --> Actif\n    Actif --> [*]",
            isDark: false
        )
        XCTAssertGreaterThan(image.size.width, 0)
    }

    private func assertNativeRenderThrows(
        _ source: String, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await NativeMermaidRenderer.render(source: source, isDark: false)
            XCTFail(message, file: file, line: line)
        } catch {}
    }

    func test_simpleFlowchart_rendersANonEmptyNativeImage() async throws {
        let image = try await NativeMermaidRenderer.render(
            source: "flowchart TD\n    A[Début] --> B[Fin]",
            isDark: false
        )

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertNotNil(image.tiffRepresentation)

        if let snapshotPath = ProcessInfo.processInfo.environment["ONETOONE_MERMAID_SNAPSHOT"],
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: snapshotPath))
        }
    }
}
