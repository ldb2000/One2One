import Foundation

/// Un engagement pris en tête-à-tête et **non soldé** : une décision actée ou
/// une action née pendant l'entretien, qui n'a été ni cochée ni explicitement
/// reprise depuis.
struct Engagement: Identifiable {
    /// D'où vient l'engagement — et donc où le solder. Une décision n'a
    /// d'identité que son rang dans sa réunion.
    enum Origin {
        case decision(Meeting, index: Int)
        case action(ActionTask)
    }

    /// Rang de sortie, stable : la date de la réunion puis l'ordre de saisie.
    let id: String
    let origin: Origin
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
                                                      origin: .decision(meeting, index: index),
                                                      text: entry.text,
                                                      date: meeting.date)))
            }
            // Cochée (`isCompleted`) ou explicitement reprise
            // (`engagementSettledAt`) : les deux causes de solde que la
            // définition nomme.
            for task in meeting.tasks
            where !task.isCompleted && task.engagementSettledAt == nil {
                found.append((found.count, Engagement(id: "\(key)#t\(task.persistentModelID)",
                                                      origin: .action(task),
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

    /// Solde un engagement : il cesse de compter.
    ///
    /// **Ce n'est pas cocher.** Solder une action, c'est dire « c'est repris,
    /// ce n'est plus une promesse en l'air » — la tâche reste ouverte dans le
    /// backlog, et le compteur « ouvertes » continue de la compter. Les deux
    /// mesurent des choses différentes.
    ///
    /// Sans effet sur un engagement déjà soldé : le premier solde fait foi.
    static func settle(_ engagement: Engagement, on date: Date = Date()) {
        switch engagement.origin {
        case let .decision(meeting, index):
            guard meeting.decisionEntries.indices.contains(index),
                  meeting.decisionEntries[index].settledAt == nil else { return }
            meeting.settleDecision(at: index, on: date)
        case let .action(task):
            guard task.engagementSettledAt == nil else { return }
            task.engagementSettledAt = date
        }
    }

    static func level(count: Int) -> EngagementLevel {
        count > 3 ? .alerte : .calme
    }
}
