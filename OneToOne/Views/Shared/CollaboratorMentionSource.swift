import SwiftData

/// Fabrique les closures de recherche/création de collaborateurs pour
/// `MarkdownTextEditor.markdownMentions(search:create:)`, réutilisée par tous
/// les points d'entrée qui éditent une note markdown (`MarkdownNoteEditor`,
/// `MarkdownEditorView` dans `EditableTextField.swift`) — même requête, même
/// tri, même politique de création partout où l'on peut mentionner un
/// collaborateur, plutôt qu'une réimplémentation par appelant.
///
/// C'est ici, côté vue, que la contrainte d'architecture de
/// `OneToOne/Markdown/` (pas de SwiftData) est respectée : ce fichier
/// convertit entre `Collaborator` (SwiftData) et `MentionCandidate`
/// (structure plate du module markdown).
enum CollaboratorMentionSource {

    /// Filtre `collaborators` (chargés par l'appelant via un `@Query`,
    /// typiquement `#Predicate<Collaborator> { !$0.isArchived }` — les
    /// archivés sont donc déjà exclus avant d'arriver ici) par nom,
    /// insensible à la casse et aux accents via `slashSearchNormalized`
    /// (repli du menu `/`, réutilisé tel quel plutôt que réécrit — voir
    /// `SlashCommand.swift`). `CollaboratorMatcher` (`Services/
    /// CollaboratorMatcher.swift`) n'est **pas** réutilisé ici : il résout un
    /// nom en un candidat unique par égalité exacte normalisée (pour
    /// rattacher un nom extrait par un LLM à un `Collaborator`), un problème
    /// différent d'un filtrage incrémental multi-résultats à la frappe — le
    /// réutiliser aurait forcé soit à dupliquer sa logique de repli sous un
    /// nom trompeur, soit à l'assouplir au risque de régresser son usage
    /// actuel.
    ///
    /// Tri : épinglés d'abord (`pinLevel` décroissant), puis alphabétique
    /// (`localizedCaseInsensitiveCompare`) — même tri que `SearchPopover.
    /// runSearch` et `OwnerPickerMenu` (favoris avant les autres), les deux
    /// précédents du projet pour une liste de collaborateurs recherchée par
    /// texte ; retenu plutôt qu'un tri par fréquence de mention (évoqué par
    /// la spec) qui demanderait de compter les mentions existantes, hors
    /// périmètre de cette tâche.
    ///
    /// Plafonné à 8 résultats : `MentionPanel` affiche une liste plate sans
    /// défilement (comme `SlashPanel`) — au-delà, l'utilisateur affine sa
    /// requête plutôt que de faire défiler un panneau surdimensionné.
    static func search(_ query: String, in collaborators: [Collaborator]) -> [MentionCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmed.isEmpty
            ? collaborators
            : collaborators.filter { $0.name.slashSearchNormalized.contains(trimmed.slashSearchNormalized) }
        return matching
            .sorted { lhs, rhs in
                if lhs.pinLevel != rhs.pinLevel { return lhs.pinLevel > rhs.pinLevel }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(8)
            .map { MentionCandidate(id: $0.ensuredStableID, name: $0.name, role: $0.role) }
    }

    /// Crée un collaborateur nommé `name` (rôle par défaut du modèle,
    /// « Architecte » — comme `OwnerPickerMenu.onCreate`/
    /// `AddCollaboratorSheet`, aucune des deux ne demande de rôle à la
    /// création rapide) et le renvoie ; `nil` si `name` est vide une fois
    /// trimé. Pas de confirmation avant l'insertion : suit la décision de la
    /// spec, cohérente avec les flux « + Ajouter » existants du projet, qui
    /// n'en ont pas non plus — l'entrée « Créer "…" » elle-même n'apparaît
    /// que sans correspondance exacte (`MentionCatalog.rows`), ce qui protège
    /// déjà de la création accidentelle d'un doublon exact.
    static func create(_ name: String, in context: ModelContext) -> MentionCandidate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collaborator = Collaborator(name: trimmed)
        context.insert(collaborator)
        try? context.save()
        return MentionCandidate(id: collaborator.ensuredStableID, name: collaborator.name, role: collaborator.role)
    }
}
