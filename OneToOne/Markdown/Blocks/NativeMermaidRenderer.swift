import AppKit
import BeautifulMermaid

/// Adaptateur de la copie locale de BeautifulMermaidSwift. Le reste de
/// l'éditeur dépend de ce petit contrat plutôt que de l'API du moteur tiers.
enum NativeMermaidRenderer {
    static func render(source: String, isDark: Bool) async throws -> NSImage {
        let theme = diagramTheme(isDark: isDark)
        guard let image = try await BeautifulMermaid.MermaidRenderer.renderImageAsync(
            source: source,
            theme: theme,
            scale: 2
        ) else {
            throw NativeMermaidError.emptyImage
        }
        return image
    }

    private static func diagramTheme(isDark: Bool) -> BeautifulMermaid.DiagramTheme {
        if isDark {
            return BeautifulMermaid.DiagramTheme(
                background: NSColor(red: 0x1f/255, green: 0x20/255, blue: 0x24/255, alpha: 1),
                foreground: NSColor(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255, alpha: 1),
                line: NSColor(red: 0xaa/255, green: 0xb2/255, blue: 0xbf/255, alpha: 1),
                accent: NSColor(red: 0x7a/255, green: 0xa2/255, blue: 0xf7/255, alpha: 1),
                muted: NSColor(red: 0x8b/255, green: 0x93/255, blue: 0xa1/255, alpha: 1),
                surface: NSColor(red: 0x29/255, green: 0x2c/255, blue: 0x33/255, alpha: 1),
                border: NSColor(red: 0x7d/255, green: 0x85/255, blue: 0x92/255, alpha: 1),
                font: NSFont.systemFont(ofSize: 14, weight: .medium),
                lineWidth: 1.25,
                cornerRadius: 6,
                transparent: true
            )
        }

        return BeautifulMermaid.DiagramTheme(
            background: .white,
            foreground: NSColor(red: 0x1d/255, green: 0x1d/255, blue: 0x1f/255, alpha: 1),
            line: NSColor(red: 0x66/255, green: 0x70/255, blue: 0x85/255, alpha: 1),
            accent: NSColor(red: 0x0a/255, green: 0x6c/255, blue: 0xff/255, alpha: 1),
            muted: NSColor(red: 0x66/255, green: 0x70/255, blue: 0x85/255, alpha: 1),
            surface: NSColor(red: 0xf5/255, green: 0xf7/255, blue: 0xfb/255, alpha: 1),
            border: NSColor(red: 0x98/255, green: 0xa2/255, blue: 0xb3/255, alpha: 1),
            font: NSFont.systemFont(ofSize: 14, weight: .medium),
            lineWidth: 1.25,
            cornerRadius: 6,
            transparent: true
        )
    }

    private enum NativeMermaidError: Error {
        case emptyImage
    }
}
