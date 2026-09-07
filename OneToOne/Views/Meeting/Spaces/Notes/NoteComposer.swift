import SwiftUI
import SwiftData
import AppKit

/// Le composeur de notes en pied de la colonne MES NOTES (spec §2.4 :
/// « composeur en bas avec les commandes `/` visibles en permanence, pas de
/// découverte cachée »).
///
/// Trois exigences tenues ici :
/// - la note prend le **timecode courant** de la tête de lecture ; hors audio,
///   `t = 0` et la ligne s'affiche `--:--` ;
/// - `⌘⏎` — et `Retour`, qui est le geste naturel dans un champ d'une ligne —
///   valide **sans perdre le focus** : on enchaîne les notes en séance ;
/// - `⌘⇧N` rend le clavier au champ depuis n'importe où dans l'écran
///   (`MeetingScreenModel.noteComposerFocusToken`).
///
/// Le texte en cours vit dans `MeetingScreenModel.pendingNoteText` et non dans
/// un `@State` : le critère d'acceptation n° 4 du chantier 1 exige que le
/// passage Préparer → En séance → Relire ne perde aucune saisie, et la colonne
/// est détruite à chaque changement de mode.
struct NoteComposer: View {

    let meeting: Meeting
    let screen: MeetingScreenModel

    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if theme == .session { enSeance } else { enFenetre }
        }
        .overlay {
            // `⌘⇧N` (spec §1.4) : le raccourci vit dans la surface qui le rend
            // possible, plutôt que dans un item de menu qui obligerait
            // `MeetingView` à porter une closure de plus.
            Button("") { screen.focusNoteComposer() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Le composeur du mode fenêtré (capture 1a) : un cadre pointillé, le
    /// champ et les quatre pilules sur une seule ligne.
    private var enFenetre: some View {
        HStack(spacing: 8) {
            champ
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            pilules
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .strokeBorder(c.strongBorder,
                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Le composeur du mode séance (capture 1b) : la ligne en cours **est** une
    /// ligne de la colonne — timecode courant à gauche, texte au curseur rouge,
    /// puis les quatre commandes en dessous. Aucun cadre : la colonne est déjà
    /// une surface, et un rectangle pointillé de plus au milieu de l'écran ne
    /// désigne rien.
    private var enSeance: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TimecodeLabel(seconds: screen.playhead.t, teinte: c.ink1)
                champ
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
            }
            pilules
        }
    }

    private var champ: some View {
        NoteComposerField(
            placeholder: theme == .session ? "" : "Tape",
            text: Binding(get: { screen.pendingNoteText },
                          set: { screen.pendingNoteText = $0 }),
            focusToken: screen.noteComposerFocusToken,
            taille: theme == .session ? 12.5 : 12,
            encre: NSColor(c.ink1),
            curseur: NSColor(One2OneToken.railElapsed),
            onSubmit: valider
        )
    }

    @ViewBuilder
    private var pilules: some View {
        HStack(spacing: 6) {
            ForEach(NoteCommandParser.visiblePills, id: \.rawValue) { commande in
                Button {
                    inserer(commande)
                } label: {
                    Chip(commande.pill, ton: ton(for: commande))
                }
                .buttonStyle(.plain)
                .help(aide(for: commande))
            }
        }
    }

    /// Ton de la pilule : chaque commande porte l'accent de ce qu'elle produit
    /// (`/action` en bleu d'action, `/décision` en rouge brique du rapport,
    /// `/risque` en ambre).
    private func ton(for commande: NoteCommandParser.Command) -> ChipTon {
        switch commande {
        case .action:   return .action
        case .decision: return .report
        case .risk:     return .warn
        default:        return .neutre
        }
    }

    private func aide(for commande: NoteCommandParser.Command) -> String {
        switch commande {
        case .action:   return "Créer une action depuis la ligne saisie"
        case .decision: return "Noter une décision au timecode courant"
        case .risk:     return "Noter un risque au timecode courant"
        case .quote:    return "Citer un passage dans la note"
        default:        return commande.pill
        }
    }

    /// Insère la commande en tête du champ et redonne le focus : cliquer une
    /// pilule doit permettre de continuer à taper, pas ouvrir un dialogue.
    private func inserer(_ commande: NoteCommandParser.Command) {
        let reste = screen.pendingNoteText.trimmingCharacters(in: .whitespaces)
        let sansCommande = NoteCommandParser.parse(reste).command == nil
            ? reste
            : NoteCommandParser.parse(reste).text
        screen.pendingNoteText = "\(commande.pill) \(sansCommande)"
        screen.focusNoteComposer()
    }

    /// Valide la ligne : `/action` pose l'intention pour le rail, tout le reste
    /// crée une `MeetingNote` au timecode courant.
    private func valider() {
        let parsed = NoteCommandParser.parse(screen.pendingNoteText)
        guard !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let t = screen.playhead.t

        if parsed.opensActionComposer {
            // `/action` n'écrit **aucune** note : il pose l'intention — titre
            // nettoyé, source comprise — et c'est le composeur du rail
            // (`ActionComposerService.creer`) qui crée l'`ActionTask` au `⌘⏎`
            // suivant. Une seule création, un seul endroit.
            //
            // Source de nature `note` et non `transcript` : la ligne vient de
            // la colonne de notes, à l'instant de la tête de lecture. Faute de
            // note écrite, c'est la réunion qui porte l'identifiant — mais la
            // nature doit rester juste : `OwnerSuggestion` ne cherche un
            // locuteur que dans les sources `transcript`.
            screen.requestAction(from: ActionFromPhrase.draft(
                phrase: parsed.text,
                kind: .note,
                stableID: meeting.ensuredStableID,
                t: t
            ))
        } else {
            MeetingNoteStore.append(parsed, at: t, to: meeting, in: context)
            NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
        }

        screen.pendingNoteText = ""
        // Le focus ne doit pas partir avec le texte : en séance, on enchaîne.
        screen.focusNoteComposer()
    }
}

// MARK: - Champ AppKit

/// Champ d'une ligne du composeur : `Retour` et `⌘⏎` valident, un jeton rend
/// le clavier au champ.
///
/// AppKit et non `TextField` : SwiftUI n'offre pas de moyen fiable de garder le
/// focus après validation, et `⌘⏎` doit être intercepté avant que l'item de
/// menu qui porte le même raccourci (« Générer le rapport ») ne s'en saisisse.
private struct NoteComposerField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var focusToken: Int
    /// Corps de la fonte. 12 en fenêtré, 12,5 en séance (capture 1b : la ligne
    /// en cours a le corps des notes qui la précèdent, pas celui d'un champ).
    var taille: CGFloat = 12
    /// Encre du texte saisi. Sans elle, le champ retomberait sur
    /// `labelColor`, illisible sur `#1c1a17`.
    var encre: NSColor = .labelColor
    /// Couleur du curseur. Rouge en séance (capture 1b) : c'est le seul repère
    /// qui dit où la prochaine note s'écrira.
    var curseur: NSColor?
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> CommandReturnTextField {
        let field = CommandReturnTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        // Même règle que `Font.plexSans` : le nom PostScript est abrégé
        // (`IBMPlexSans`), et l'absence de la fonte retombe sur le système
        // plutôt que de rendre un champ sans fonte.
        field.font = NSFont(name: PlexWeight.regular.sansPostScriptName, size: taille)
            ?? .systemFont(ofSize: taille)
        field.textColor = encre
        field.caretColor = curseur
        field.delegate = context.coordinator
        field.onSubmit = { context.coordinator.submit() }
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: CommandReturnTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        nsView.placeholderString = placeholder
        nsView.textColor = encre
        nsView.caretColor = curseur
        nsView.applyCaretColor()
        if nsView.stringValue != text { nsView.stringValue = text }
        // Le jeton, et non un booléen : deux demandes de focus de suite doivent
        // toutes deux aboutir.
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            if focusToken > 0 {
                DispatchQueue.main.async {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var lastFocusToken = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func submit() {
            onSubmit()
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            submit()
            return true
        }
    }
}

/// `NSTextField` qui intercepte `⌘⏎` avant le menu principal.
final class CommandReturnTextField: NSTextField {
    var onSubmit: (() -> Void)?

    /// Couleur du curseur, appliquée à l'**éditeur de champ** — un
    /// `NSTextField` n'a pas de `insertionPointColor`, c'est le `NSTextView`
    /// partagé de la fenêtre qui dessine le curseur, et il faut donc le
    /// repeindre à chaque prise de focus.
    var caretColor: NSColor?

    override func becomeFirstResponder() -> Bool {
        let accepte = super.becomeFirstResponder()
        if accepte { applyCaretColor() }
        return accepte
    }

    func applyCaretColor() {
        guard let caretColor, let editeur = currentEditor() as? NSTextView else { return }
        editeur.insertionPointColor = caretColor
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modificateurs = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modificateurs == .command,
           event.charactersIgnoringModifiers == "\r",
           window?.firstResponder === currentEditor() || window?.firstResponder === self {
            onSubmit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
