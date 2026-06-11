import Foundation
import SwiftData

/// Règle d'affectation « titre d'événement calendrier → projet » créée
/// manuellement depuis le panneau agenda. La clé de matching est le titre
/// normalisé (tokens minuscules sans diacritiques joints par espace), ce qui
/// fait qu'une règle s'applique à toutes les occurrences d'une réunion
/// récurrente, passées et futures.
///
/// Une règle peut aussi marquer un titre comme « Ignoré » (`isIgnored`) :
/// l'événement est alors exclu du décompte hebdomadaire (événements perso).
@Model
final class AgendaProjectRule {
    /// Clé de matching : `AgendaProjectResolver.normalizedKey(title)`.
    var normalizedTitleKey: String = ""
    /// Titre original tel qu'affiché dans l'agenda (pour l'UI de gestion).
    var displayTitle: String = ""
    /// true → événement exclu de l'agenda enrichi et du temps hebdo.
    var isIgnored: Bool = false
    /// Projet affecté. Inverse cascade côté `Project.agendaRules` : la règle
    /// est supprimée avec son projet. `nil` n'a de sens qu'avec `isIgnored`.
    var project: Project?
    var createdAt: Date = Date.now

    init(normalizedTitleKey: String = "",
         displayTitle: String = "",
         isIgnored: Bool = false,
         project: Project? = nil) {
        self.normalizedTitleKey = normalizedTitleKey
        self.displayTitle = displayTitle
        self.isIgnored = isIgnored
        self.project = project
        self.createdAt = Date.now
    }
}
