import Foundation

/// L'état de partage d'un document à l'écran, **dérivable sans le tiroir**.
///
/// Critère d'acceptation n° 2 du chantier 3 : « l'état de partage est lisible
/// depuis la barre du haut sans ouvrir le tiroir ». La pilule
/// `● Partage actif · 5 voient` doit donc se construire à partir de la réunion
/// et d'un identifiant de pièce, sans rien demander à la vue qui gère le
/// tiroir. Ce qui est ici est **pur** : deux entiers et un libellé.
enum MeetingSharingState {

    /// Nombre de participants présents, soi compris. C'est le chiffre du pied
    /// du tiroir (`Donner l'accès aux 6 participants`).
    @MainActor
    static func presentCount(for meeting: Meeting) -> Int {
        PresenceStats.compute(statuses: meeting.participants.map {
            meeting.participantStatus(for: $0)
        }).present
    }

    /// Nombre de personnes **qui voient** le document partagé : les présents
    /// moins soi.
    ///
    /// La capture `3a-tiroir-ressources.png` l'énonce sans ambiguïté : six
    /// présents au bandeau, `Partage actif · 5 voient` dans la barre, `l'accès
    /// aux 6 participants` au pied. On ne se compte pas parmi ceux à qui l'on
    /// montre quelque chose.
    ///
    /// Jamais négatif : une réunion sans participant enregistré (une note
    /// prise seul) affiche `0 voient` plutôt qu'un nombre absurde.
    static func viewerCount(presentCount: Int) -> Int {
        max(0, presentCount - 1)
    }

    /// Le libellé de la pilule, ou `nil` quand rien n'est partagé — la pilule
    /// **disparaît** alors, elle ne se grise pas (spec §4.2).
    static func pillLabel(isPresenting: Bool, presentCount: Int) -> String? {
        guard isPresenting else { return nil }
        let n = viewerCount(presentCount: presentCount)
        switch n {
        case 0:  return "● Partage actif"
        case 1:  return "● Partage actif · 1 voit"
        default: return "● Partage actif · \(n) voient"
        }
    }
}
