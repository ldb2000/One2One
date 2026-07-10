import SwiftUI
import AppKit

/// Éditeur de notes markdown à deux modes commutables :
/// - **Aperçu** (défaut) : markdown rendu via `MarkdownText`.
/// - **Édition** : markdown **brut** (les marqueurs `**`, `##`, `-`… restent
///   visibles) dans un `NSTextView` texte plein, avec une toolbar qui insère du
///   markdown au curseur.
///
/// Défaut = Aperçu, sauf note vide → démarre en Édition (évite l'écran blanc).
/// Distinct de l'éditeur WYSIWYG (`MarkdownTextEditor`) utilisé ailleurs.
struct MarkdownNoteEditor: View {
    @Binding var text: String
    let editorID: String

    @State private var isEditing: Bool

    init(text: Binding<String>, editorID: String) {
        self._text = text
        self.editorID = editorID
        self._isEditing = State(initialValue: text.wrappedValue.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $isEditing) {
                    Text("Aperçu").tag(false)
                    Text("Édition").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            if isEditing {
                RawMarkdownToolbar(editorID: editorID)
                RawMarkdownTextView(text: $text, editorID: editorID)
            } else if text.isEmpty {
                Text("Aucune note — passe en Édition pour écrire.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    MarkdownText(markdown: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Raw markdown text editor (plain NSTextView)

/// `NSTextView` en texte **brut** (aucun stylage markdown), relié à un
/// `Binding<String>` avec debounce. S'enregistre dans `MarkdownEditorRegistry`
/// sous `editorID` pour que `RawMarkdownToolbar` puisse insérer au curseur.
struct RawMarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var editorID: String = ""
    var debounce: TimeInterval = 0.3

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.string = text
        context.coordinator.textView = tv
        if !editorID.isEmpty { MarkdownEditorRegistry.shared.register(tv, id: editorID) }
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if !coordinator.parent.editorID.isEmpty {
            MarkdownEditorRegistry.shared.unregister(id: coordinator.parent.editorID)
        }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        // Changement externe (pas notre propre frappe) → resync sans casser le curseur.
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            let loc = min(sel.location, (text as NSString).length)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RawMarkdownTextView
        weak var textView: NSTextView?
        private var pending: DispatchWorkItem?

        init(_ parent: RawMarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let value = tv.string
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.parent.text = value }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + parent.debounce, execute: work)
        }
    }
}

// MARK: - Raw markdown toolbar (inserts markdown at the cursor)

/// Barre d'outils qui insère du **markdown en clair** au curseur de l'éditeur
/// brut enregistré sous `editorID` (via `MarkdownEditorRegistry`). Indépendante
/// de la `MarkdownToolbar` WYSIWYG (qui, elle, manipule un modèle attribué).
struct RawMarkdownToolbar: View {
    let editorID: String

    private var textView: NSTextView? { MarkdownEditorRegistry.shared.textView(for: editorID) }

    var body: some View {
        HStack(spacing: 2) {
            iconButton("bold") { wrapSelection(with: "**", placeholder: "texte") }
            iconButton("italic") { wrapSelection(with: "*", placeholder: "texte") }
            Divider().frame(height: 14)
            iconButton("textformat.size.larger") { insertLinePrefix("## ") }
            iconButton("textformat.size") { insertLinePrefix("### ") }
            Divider().frame(height: 14)
            iconButton("list.bullet") { insertLinePrefix("- ") }
            iconButton("checklist") { insertLinePrefix("- [ ] ") }
            Divider().frame(height: 14)
            tagButton("[ACTION] ", color: .blue, label: "Action")
            tagButton("[RISQUE] ", color: .red, label: "Risque")
            tagButton("[DECISION] ", color: .green, label: "Decision")
            tagButton("[PROJET] ", color: .orange, label: "Projet")
            Spacer()
        }
    }

    private func iconButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.bordered).controlSize(.small)
    }

    private func tagButton(_ tag: String, color: Color, label: String) -> some View {
        Button { insertAtCursor(tag) } label: {
            Text(label).font(.caption.weight(.medium)).foregroundColor(color)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    /// Entoure la sélection (ou insère un placeholder) avec `marker` de part et d'autre.
    private func wrapSelection(with marker: String, placeholder: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: sel)
        let inner = selected.isEmpty ? placeholder : selected
        let replacement = marker + inner + marker
        guard tv.shouldChangeText(in: sel, replacementString: replacement) else { return }
        tv.insertText(replacement, replacementRange: sel)
        // Sélectionne le texte intérieur (pratique pour remplacer le placeholder).
        let innerLoc = sel.location + (marker as NSString).length
        tv.setSelectedRange(NSRange(location: innerLoc, length: (inner as NSString).length))
        tv.window?.makeFirstResponder(tv)
    }

    /// Insère `prefix` en tête de la ligne courante.
    private func insertLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let at = NSRange(location: lineStart, length: 0)
        guard tv.shouldChangeText(in: at, replacementString: prefix) else { return }
        tv.insertText(prefix, replacementRange: at)
        tv.setSelectedRange(NSRange(location: sel.location + (prefix as NSString).length, length: 0))
        tv.window?.makeFirstResponder(tv)
    }

    private func insertAtCursor(_ string: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard tv.shouldChangeText(in: sel, replacementString: string) else { return }
        tv.insertText(string, replacementRange: sel)
        tv.window?.makeFirstResponder(tv)
    }
}
