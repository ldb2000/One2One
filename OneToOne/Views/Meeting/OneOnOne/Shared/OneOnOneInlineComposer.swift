import SwiftUI
import AppKit

/// Le composeur d'une ligne en pied de carte : `Ajouter un sujet…`,
/// `＋ Ajouter un engagement…` (capture 2a).
///
/// Réemploie `CommandReturnTextField` (lot 2) plutôt que `TextField` : `⌘⏎`
/// doit être intercepté **avant** l'item de menu qui porte le même raccourci
/// (« Générer le rapport »), et `Retour` doit valider sans perdre le focus —
/// on enchaîne les sujets en début d'entretien.
///
/// Partagé (`Shared/`) : les captures 2b, 5a et 5b portent le même composeur.
struct OneOnOneInlineComposer: View {

    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        InlineComposerField(placeholder: placeholder, text: $text, onSubmit: onSubmit)
            .frame(height: 20)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .strokeBorder(One2OneToken.strongBorder,
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .help("\(placeholder) — Retour ou ⌘⏎ pour valider")
    }
}

/// Le champ AppKit d'une ligne, sans bordure ni fond : c'est la carte qui
/// dessine le cadre pointillé.
private struct InlineComposerField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> CommandReturnTextField {
        let field = CommandReturnTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        // Même règle que `Font.plexSans` : le nom PostScript est abrégé, et
        // l'absence de la fonte retombe sur le système plutôt que de rendre un
        // champ sans fonte.
        field.font = NSFont(name: PlexWeight.regular.sansPostScriptName, size: 12)
            ?? .systemFont(ofSize: 12)
        field.textColor = NSColor(One2OneToken.ink2)
        field.delegate = context.coordinator
        field.onSubmit = { context.coordinator.submit() }
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: CommandReturnTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        nsView.placeholderString = placeholder
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func submit() { onSubmit() }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            submit()
            return true
        }
    }
}
