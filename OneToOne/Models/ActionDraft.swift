import Foundation

/// Une action **proposée** mais pas encore créée : le titre nettoyé d'une
/// phrase, sa chaîne de citation et le responsable que la suggestion a trouvé.
///
/// C'est le contrat entre la colonne de transcription (spec §2.4 : « ouvre le
/// composeur d'action prérempli ») et le composeur du rail (spec §2.5) : la
/// première le pose dans `MeetingScreenModel.pendingActionDraft`, le second le
/// consomme et le remet à `nil`. Un brouillon, pas une action : rien n'est
/// écrit en base tant que `⌘⏎` n'a pas été frappé.
///
/// Non `Sendable` : `Collaborator` est un `@Model`, donc lié au contexte
/// principal. Ce type ne traverse aucune frontière de concurrence — il vit le
/// temps d'un aller-retour entre deux vues du même écran.
@MainActor
struct ActionDraft {

    /// Le titre prérempli. Vide, le composeur ne crée rien.
    var title: String

    /// D'où vient la proposition (segment de transcription, note, capture).
    var sourceRef: SourceRef?

    /// Le responsable suggéré par `OwnerSuggestion`, `nil` si aucune règle
    /// n'a conclu.
    var suggestedOwner: Collaborator?

    init(title: String, sourceRef: SourceRef? = nil, suggestedOwner: Collaborator? = nil) {
        self.title = title
        self.sourceRef = sourceRef
        self.suggestedOwner = suggestedOwner
    }
}
