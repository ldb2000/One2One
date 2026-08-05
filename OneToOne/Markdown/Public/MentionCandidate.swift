import Foundation

/// Un collaborateur proposable par le panneau de mention `@`
/// (`MentionController`/`MentionPanel`), sans dépendance à SwiftData — voir
/// la contrainte d'architecture de `OneToOne/Markdown/` (le module ne connaît
/// pas SwiftData, cf. `CLAUDE.md`). C'est le type de closure exposé par
/// `MarkdownTextEditor.markdownMentions(search:create:)` : la couche vue
/// convertit un `Collaborator` (SwiftData) en `MentionCandidate` pour la
/// recherche, et inversement à la création.
///
/// `id` doit être `Collaborator.ensuredStableID` (jamais `Collaborator.stableID`
/// directement) — ce dernier est `Optional` et peut être `nil` pour un
/// collaborateur créé avant l'ajout du champ (caveat de migration SwiftData,
/// voir `Collaborator.ensuredStableID` dans `Models/OtherModels.swift`) ;
/// `ensuredStableID` backfille un identifiant stable dans ce cas plutôt que
/// de planter au cast optionnel.
public struct MentionCandidate: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let role: String

    public init(id: UUID, name: String, role: String) {
        self.id = id
        self.name = name
        self.role = role
    }
}
