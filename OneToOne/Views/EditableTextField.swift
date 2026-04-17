import SwiftUI
import AppKit

// MARK: - Image Paste Service

enum ImagePasteService {
    static var imagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OneToOne/images", isDirectory: true)
    }

    static var clipboardHasImage: Bool {
        let pb = NSPasteboard.general
        return pb.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue,
                                                          NSPasteboard.PasteboardType.tiff.rawValue])
    }

    static func saveClipboardImage() -> URL? {
        let pb = NSPasteboard.general

        // Try PNG first, then TIFF
        var imageData: Data?
        if let png = pb.data(forType: .png) {
            imageData = png
        } else if let tiff = pb.data(forType: .tiff),
                  let bitmapRep = NSBitmapImageRep(data: tiff),
                  let png = bitmapRep.representation(using: .png, properties: [:]) {
            imageData = png
        }

        guard let data = imageData else { return nil }

        // Compress if > 2MB
        var finalData = data
        if finalData.count > 2_000_000 {
            if let bitmapRep = NSBitmapImageRep(data: data),
               let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                finalData = jpeg
            }
        }

        let isJpeg = finalData.count != data.count
        let ext = isJpeg ? "jpg" : "png"
        let fileName = "img_\(UUID().uuidString).\(ext)"
        let dir = imagesDirectory

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(fileName)
            try finalData.write(to: fileURL)
            return fileURL
        } catch {
            print("[ImagePasteService] Failed to save image: \(error)")
            return nil
        }
    }

    static func markdownReference(for imageURL: URL, alt: String = "image") -> String {
        "![\(alt)](\(imageURL.absoluteString))"
    }
}

// MARK: - Pastable Markdown NSTextView

/// NSTextView subclass that intercepts Cmd+V to handle image paste from clipboard.
class PastableMarkdownTextView: NSTextView {
    override func paste(_ sender: Any?) {
        if ImagePasteService.clipboardHasImage {
            if let imageURL = ImagePasteService.saveClipboardImage() {
                let ref = ImagePasteService.markdownReference(for: imageURL)
                let insertion = "\n\(ref)\n"
                insertText(insertion, replacementRange: selectedRange())
            }
        } else {
            super.paste(sender)
        }
    }
}

// MARK: - Warm Background

/// Shared warm gradient background matching the chatbot style.
struct WarmBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.95, blue: 0.93),
                    Color(red: 0.90, green: 0.92, blue: 0.90),
                    Color(red: 0.96, green: 0.93, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
        }
    }
}

extension View {
    func warmBackground() -> some View {
        modifier(WarmBackground())
    }
}

// MARK: - Markdown Preview

/// Renders Markdown text using NSTextView for full block-level support (headers, lists, bold, italic, code).
struct MarkdownTextView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = .clear
        applyMarkdown(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        applyMarkdown(to: textView)
    }

    private func applyMarkdown(to textView: NSTextView) {
        let maxImageWidth: CGFloat = max(textView.bounds.width - 40, 200)
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let bodyColor = NSColor.labelColor

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Image: ![alt](url)
            if let imageAttr = parseImageLine(trimmed, maxWidth: maxImageWidth) {
                result.append(imageAttr)
            } else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                let attr = NSMutableAttributedString(string: text + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: bodyColor
                ])
                result.append(attr)
            } else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                let attr = NSMutableAttributedString(string: text + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 17, weight: .bold),
                    .foregroundColor: bodyColor
                ])
                result.append(attr)
            } else if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2))
                let attr = NSMutableAttributedString(string: text + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: bodyColor
                ])
                result.append(attr)
            } else if trimmed.hasPrefix("[ACTION]") {
                let attr = NSMutableAttributedString(string: trimmed + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold),
                    .foregroundColor: NSColor.systemBlue
                ])
                result.append(attr)
            } else if trimmed.hasPrefix("[RISQUE]") {
                let attr = NSMutableAttributedString(string: trimmed + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold),
                    .foregroundColor: NSColor.systemRed
                ])
                result.append(attr)
            } else if trimmed.hasPrefix("[DECISION]") || trimmed.hasPrefix("[DÉCISION]") {
                let attr = NSMutableAttributedString(string: trimmed + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold),
                    .foregroundColor: NSColor.systemGreen
                ])
                result.append(attr)
            } else if trimmed.hasPrefix("[PROJET") {
                let attr = NSMutableAttributedString(string: trimmed + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold),
                    .foregroundColor: NSColor.systemOrange
                ])
                result.append(attr)
            } else {
                // Inline bold **text** and italic _text_
                let attr = parseInlineMarkdown(line + "\n", font: bodyFont, color: bodyColor)
                result.append(attr)
            }
        }

        textView.textStorage?.setAttributedString(result)
    }

    /// Detects ![alt](url) pattern and returns an attributed string with the image, or nil.
    private func parseImageLine(_ line: String, maxWidth: CGFloat) -> NSAttributedString? {
        let pattern = #"^!\[([^\]]*)\]\(([^)]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let urlRange = match.range(at: 2)
        let urlString = (line as NSString).substring(with: urlRange)

        // Load image from file URL
        guard let url = URL(string: urlString),
              let image = NSImage(contentsOf: url) else {
            // Show broken image placeholder
            let placeholder = NSMutableAttributedString(string: "[Image introuvable: \(urlString)]\n", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.systemRed
            ])
            return placeholder
        }

        // Scale image to fit
        let originalSize = image.size
        let scale = originalSize.width > maxWidth ? maxWidth / originalSize.width : 1.0
        let displaySize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let resizedImage = NSImage(size: displaySize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: displaySize))
        resizedImage.unlockFocus()

        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: resizedImage)
        attachment.attachmentCell = cell

        let imageAttr = NSMutableAttributedString()
        imageAttr.append(NSAttributedString(attachment: attachment))
        imageAttr.append(NSAttributedString(string: "\n"))

        return imageAttr
    }

    private func parseInlineMarkdown(_ text: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])

        // Bold: **text** or __text__
        let boldPattern = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#)
        if let matches = boldPattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            for match in matches.reversed() {
                let contentRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                let content = (text as NSString).substring(with: contentRange)
                let boldAttr = NSAttributedString(string: content, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: font.pointSize),
                    .foregroundColor: color
                ])
                result.replaceCharacters(in: match.range, with: boldAttr)
            }
        }

        // Italic: _text_ (but not __text__)
        let italicPattern = try? NSRegularExpression(pattern: #"(?<![_*])_([^_]+?)_(?![_*])"#)
        if let matches = italicPattern?.matches(in: result.string, range: NSRange(result.string.startIndex..., in: result.string)) {
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                let content = (result.string as NSString).substring(with: contentRange)
                let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                let italicAttr = NSAttributedString(string: content, attributes: [
                    .font: italicFont,
                    .foregroundColor: color
                ])
                result.replaceCharacters(in: match.range, with: italicAttr)
            }
        }

        // Inline code: `text`
        let codePattern = try? NSRegularExpression(pattern: #"`([^`]+?)`"#)
        if let matches = codePattern?.matches(in: result.string, range: NSRange(result.string.startIndex..., in: result.string)) {
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                let content = (result.string as NSString).substring(with: contentRange)
                let codeAttr = NSAttributedString(string: content, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                    .foregroundColor: NSColor.systemPurple,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ])
                result.replaceCharacters(in: match.range, with: codeAttr)
            }
        }

        return result
    }
}

// MARK: - Markdown Editor (NSTextView with shared registry for toolbar access)

/// Global registry so the toolbar can find the active NSTextView by ID.
final class MarkdownEditorRegistry {
    static let shared = MarkdownEditorRegistry()
    private var editors: [String: NSTextView] = [:]

    func register(_ textView: NSTextView, id: String) {
        editors[id] = textView
    }

    func unregister(id: String) {
        editors.removeValue(forKey: id)
    }

    func textView(for id: String) -> NSTextView? {
        editors[id]
    }
}

/// Editable NSTextView that registers itself for toolbar access.
struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    let textViewID: String

    func makeNSView(context: Context) -> NSScrollView {
        // Use PastableMarkdownTextView to support Cmd+V image paste
        let textView = PastableMarkdownTextView()
        textView.string = text
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        MarkdownEditorRegistry.shared.register(textView, id: textViewID)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PastableMarkdownTextView else { return }
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Restore cursor if valid
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.unregister()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, textViewID: textViewID)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let textViewID: String

        init(text: Binding<String>, textViewID: String) {
            self.text = text
            self.textViewID = textViewID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func unregister() {
            MarkdownEditorRegistry.shared.unregister(id: textViewID)
        }
    }
}

/// Formatting toolbar that inserts markdown syntax into the registered editor.
struct MarkdownToolbar: View {
    let textViewID: String

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton("bold", icon: "bold", wrap: "**")
            toolbarButton("italic", icon: "italic", wrap: "_")
            Divider().frame(height: 14)
            toolbarButton("h2", icon: "textformat.size.larger", prefix: "## ")
            toolbarButton("h3", icon: "textformat.size", prefix: "### ")
            Divider().frame(height: 14)
            toolbarButton("list", icon: "list.bullet", prefix: "- ")
            Divider().frame(height: 14)
            tagButton("[ACTION] ", color: .blue, label: "Action")
            tagButton("[RISQUE] ", color: .red, label: "Risque")
            tagButton("[DECISION] ", color: .green, label: "Decision")
            tagButton("[PROJET] ", color: .orange, label: "Projet")
            Divider().frame(height: 14)
            pasteImageButton
        }
    }

    private var pasteImageButton: some View {
        Button(action: {
            guard let tv = MarkdownEditorRegistry.shared.textView(for: textViewID) else { return }
            guard let imageURL = ImagePasteService.saveClipboardImage() else { return }
            let ref = ImagePasteService.markdownReference(for: imageURL)
            let insertion = "\n\(ref)\n"
            tv.insertText(insertion, replacementRange: tv.selectedRange())
            tv.window?.makeFirstResponder(tv)
        }) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.caption)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help("Coller une image du presse-papiers")
    }

    private func toolbarButton(_ id: String, icon: String, wrap: String? = nil, prefix: String? = nil) -> some View {
        Button(action: {
            guard let tv = MarkdownEditorRegistry.shared.textView(for: textViewID) else { return }
            let range = tv.selectedRange()

            if let wrap {
                let selected = (tv.string as NSString).substring(with: range)
                let replacement = wrap + (selected.isEmpty ? "texte" : selected) + wrap
                tv.insertText(replacement, replacementRange: range)
            } else if let prefix {
                // Insert at beginning of current line
                let nsString = tv.string as NSString
                let lineStart = nsString.lineRange(for: NSRange(location: range.location, length: 0)).location
                tv.insertText(prefix, replacementRange: NSRange(location: lineStart, length: 0))
            }

            tv.window?.makeFirstResponder(tv)
        }) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(id)
    }

    private func tagButton(_ tag: String, color: Color, label: String) -> some View {
        Button(action: {
            guard let tv = MarkdownEditorRegistry.shared.textView(for: textViewID) else { return }
            let range = tv.selectedRange()
            let nsString = tv.string as NSString
            let lineStart = nsString.lineRange(for: NSRange(location: range.location, length: 0)).location
            tv.insertText(tag, replacementRange: NSRange(location: lineStart, length: 0))
            tv.window?.makeFirstResponder(tv)
        }) {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Inserer tag \(label)")
    }
}

// MARK: - Editable Text Fields

/// NSTextField wrapper that reliably accepts keyboard input in NavigationSplitView detail panes.
/// Works around the macOS SwiftUI bug where SwiftUI TextField never receives key events
/// when placed inside the detail column of a NavigationSplitView.
struct EditableTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// Same as EditableTextField but for multi-line text (NSTextView-based).
struct EditableTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.string = text
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 5, height: 5)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
