# BeautifulMermaidSwift vendored source

This directory contains a local, modifiable copy of
[`lukilabs/beautiful-mermaid-swift`](https://github.com/lukilabs/beautiful-mermaid-swift).

- Upstream commit: `6a23a29e91af8f5b3e9fc09945332ca193bd69ec`
- Upstream tag at import time: `1.0.4`
- Imported: 2026-08-08
- License: MIT, retained in `LICENSE`

The source is compiled as the local SwiftPM target `BeautifulMermaid`. Keep
application-specific integration in `OneToOne/Markdown/Blocks`; changes to
the renderer/parser itself can be made directly under `Sources`.

## Local changes

- `Sources/ImageRenderer.swift`: flip AppKit bitmap contexts to the
  top-left coordinate system expected by `DiagramRenderer`; upstream 1.0.4
  otherwise produces vertically inverted native images on macOS.
- Strict parsing (`Sources/Mermaid/src_parser.swift`,
  `src_sequence_parser.swift`, `src_class_parser.swift`,
  `src_er_parser.swift`, `src_xychart_parser.swift`, plus `try` propagation
  in `Sources/Parser.swift`, `src_index.swift`, `src_ascii_index.swift`,
  `src_ascii_xychart.swift`): upstream silently ignores any statement its
  grammars do not recognize (`autonumber`, standalone `activate`, `click`,
  notes, `style` on ER entities…), yielding incomplete diagrams. The
  patched parsers throw `…unsupportedLine` instead, so the host app can
  fall back to a fully compatible renderer (`MermaidRenderer`'s JavaScript
  path in OneToOne). `%%` comment lines remain accepted. Covered by
  `Tests/NativeMermaidRendererTests.swift` in the host repository.
