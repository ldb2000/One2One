import SwiftUI

public extension MarkdownTextEditor {
    /// Restrict the set of markdown features the editor permits. Passing an
    /// empty set disables every formatting affordance, leaving a plain
    /// multi-line text editor (typed markdown syntax is no longer auto-formatted).
    func markdownFeatures(_ features: Set<MarkdownFeature>) -> Self {
        var copy = self
        copy.features = features
        return copy
    }

    /// Placeholder shown when the binding is empty.
    func markdownPlaceholder(_ text: String) -> Self {
        var copy = self
        copy.placeholder = text
        return copy
    }

    /// Debounce delay (in seconds) before pushing edits to the `@Binding`.
    /// Default 0.3 s. A positive value is expected; 0 effectively pushes on
    /// every keystroke, and there is no enforced upper bound.
    func markdownDebounce(_ seconds: TimeInterval) -> Self {
        var copy = self
        copy.debounce = seconds
        return copy
    }

    /// When `true`, suppresses editing and keyboard input.
    func markdownReadOnly(_ flag: Bool = true) -> Self {
        var copy = self
        copy.readOnly = flag
        return copy
    }

    /// Enregistre l'éditeur dans `MarkdownEditorRegistry` sous cet identifiant
    /// pour qu'une `MarkdownToolbar(textViewID:)` puisse le piloter.
    func markdownEditorID(_ id: String) -> Self {
        var copy = self
        copy.editorID = id
        return copy
    }

    /// Active les mentions `@` de collaborateurs (voir
    /// `docs/superpowers/specs/2026-08-05-mentions-collaborateurs.md`).
    ///
    /// - `search` reçoit le texte tapé après `@` (peut contenir des espaces —
    ///   ex. « Marie Dup ») et doit renvoyer les candidats déjà filtrés
    ///   (nom, insensible casse/accents), triés (épinglés d'abord, puis
    ///   alphabétique) et purgés des collaborateurs archivés — cette closure
    ///   est le point où la requête part vers SwiftData, que ce module ne
    ///   connaît pas.
    /// - `create`, optionnelle, reçoit le nom tapé quand l'utilisateur valide
    ///   l'entrée « Créer "…" » (affichée uniquement en l'absence de
    ///   correspondance exacte, voir `MentionCatalog.rows`) et doit créer et
    ///   renvoyer le collaborateur correspondant, ou `nil` pour refuser — rien
    ///   n'est alors inséré. Omise (`nil`, le défaut), l'entrée « Créer … »
    ///   n'est jamais proposée : sélectionner la seule entrée disponible
    ///   n'aurait aucun effet, donc `MentionCatalog.rows` continue à
    ///   l'afficher mais rien ne se passe si l'utilisateur la choisit —
    ///   préférer omettre `search` plutôt que `create` seul si les mentions
    ///   ne doivent pas être proposées du tout.
    func markdownMentions(
        search: @escaping (String) -> [MentionCandidate],
        create: ((String) -> MentionCandidate?)? = nil
    ) -> Self {
        var copy = self
        copy.mentionSearch = search
        copy.mentionCreate = create
        return copy
    }

    /// Route un lien cliqué (ex. mention `onetoone://collaborator/<uuid>`,
    /// voir `MentionCatalog.collaboratorID(from:)`) vers `handler`, appelé
    /// avec l'`URL` du lien. Renvoyer `true` marque le clic comme pris en
    /// charge ; renvoyer `false` (ou omettre ce modificateur — `nil` est le
    /// défaut) laisse le lien s'ouvrir normalement par le système, seul
    /// chemin pertinent pour un lien externe (`https://`, `mailto:`…). Ce
    /// module ne connaît ni les modèles de l'app ni comment ouvrir une fiche
    /// collaborateur : `handler` est le point où cette résolution a lieu,
    /// côté appelant — voir `EditorTextView.clicked(onLink:at:)`.
    func markdownLinks(handler: @escaping (URL) -> Bool) -> Self {
        var copy = self
        copy.linkHandler = handler
        return copy
    }
}
