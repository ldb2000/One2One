import Foundation

/// Un engagement pris en tête-à-tête et **non soldé** : une décision actée ou
/// une action née pendant l'entretien, qui n'a été ni cochée ni explicitement
/// reprise depuis.
struct Engagement: Identifiable, Equatable {
    /// Rang de sortie, stable : la date de la réunion puis l'ordre de saisie.
    let id: String
    let text: String
    /// Date de la réunion où l'engagement a été pris — ce qui permet de dire
    /// depuis combien de temps il traîne.
    let date: Date
}

/// Niveau d'alerte du compteur d'engagements.
///
/// Le seuil est **bas**, et ce n'est pas une erreur : ce compteur mesure une
/// confiance, pas une charge. Deux promesses non tenues depuis six semaines
/// abîment plus la relation que dix actions en cours — d'où le rouge dès
/// quatre, quand le compteur « ouvertes » reste noir à dix.
enum EngagementLevel { case calme, alerte }

/// Ce qui a été promis de vive voix, devant quelqu'un, et qui traîne.
///
/// **À ne pas confondre avec le compteur « ouvertes »** de la même fiche.
/// Celui-là compte tout le backlog de la personne, quelle que soit son
/// origine ; celui-ci ne retient que ce qui a été promis en face à face. Deux
/// natures différentes : ils ne doivent partager ni fonction de calcul ni
/// seuil de couleur.
enum EngagementLedger {

    /// Les types de réunion où l'on se parle en face : c'est là, et là seul,
    /// qu'une promesse engage. Une décision de comité n'est pas un engagement
    /// personnel.
    private static let faceToFace: Set<MeetingKind> = [.oneToOne, .manager]

    /// Les engagements non soldés pris devant `collaborator`, du plus ancien
    /// au plus récent — l'ancienneté est le signal.
    static func pending(for collaborator: Collaborator) -> [Engagement] {
        var found: [(order: Int, engagement: Engagement)] = []

        for meeting in collaborator.meetings where faceToFace.contains(meeting.kind) {
            let key = String(describing: meeting.persistentModelID)

            for (index, entry) in meeting.decisionEntries.enumerated() where entry.settledAt == nil {
                found.append((found.count, Engagement(id: "\(key)#d\(index)",
                                                      text: entry.text,
                                                      date: meeting.date)))
            }
            // Cochée (`isCompleted`) ou explicitement reprise
            // (`engagementSettledAt`) : les deux causes de solde que la
            // définition nomme.
            for task in meeting.tasks
            where !task.isCompleted && task.engagementSettledAt == nil {
                found.append((found.count, Engagement(id: "\(key)#t\(task.persistentModelID)",
                                                      text: task.title,
                                                      date: meeting.date)))
            }
        }

        // Tri stable : `sorted` ne l'est pas, et deux engagements pris dans la
        // même réunion doivent sortir dans l'ordre où ils ont été saisis.
        return found
            .sorted { ($0.engagement.date, $0.order) < ($1.engagement.date, $1.order) }
            .map(\.engagement)
    }

    static func level(count: Int) -> EngagementLevel {
        count > 3 ? .alerte : .calme
    }
}
