import Foundation
import SwiftData

/// L'état d'**écran** du domaine 1:1 — ce qui n'est pas une donnée d'entretien.
///
/// Y compris la confirmation d'escalade (D9 : « confirmation explicite à la
/// première utilisation par réunion ») : c'est une confirmation d'interface,
/// pas un fait de l'entretien. La mettre en base ferait apparaître dans un
/// backup, et demain dans un rapport, la trace d'un clic sur un dialogue.
///
/// Porté par `MeetingScreenModel.oneOnOne`, une instance par écran de réunion.
@Observable
@MainActor
final class OneOnOneScreenState {

    /// Filtre du tableau `Engagements réciproques` (capture 2b). `nil` = le
    /// segment `Les deux`, l'état par défaut.
    var commitmentSideFilter: OneOnOneSide?

    /// Fil affiché, quand l'écran en propose plusieurs (`Mes 1:1`).
    var selectedThreadID: UUID?

    /// Réunions pour lesquelles l'escalade a déjà été confirmée.
    private(set) var escalationConfirmedMeetingIDs: Set<UUID> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persists: Bool

    /// - Parameter persistsAcrossLaunches: `false` en test, pour que deux
    ///   suites ne se transmettent pas des confirmations par
    ///   `UserDefaults.standard`.
    init(defaults: UserDefaults = .standard, persistsAcrossLaunches: Bool = true) {
        self.defaults = defaults
        self.persists = persistsAcrossLaunches
        if persistsAcrossLaunches {
            let memorisees = defaults.stringArray(forKey: Self.escalationKey) ?? []
            escalationConfirmedMeetingIDs = Set(memorisees.compactMap(UUID.init(uuidString:)))
        }
    }

    /// Clé de l'état de confirmation, telle que le programme la nomme
    /// (`screen.oneOnOne.escalationConfirmed`).
    static let escalationKey = "onetoone.screen.oneOnOne.escalationConfirmed"

    // MARK: - Escalade (D9)

    func isEscalationConfirmed(for meeting: Meeting) -> Bool {
        escalationConfirmedMeetingIDs.contains(meeting.ensuredStableID)
    }

    /// Vrai tant que l'utilisateur n'a pas confirmé pour **cette** séance.
    /// La confirmation est par réunion : une escalade décidée en juin ne vaut
    /// pas autorisation tacite en septembre.
    func needsEscalationConfirmation(for meeting: Meeting) -> Bool {
        !isEscalationConfirmed(for: meeting)
    }

    func confirmEscalation(for meeting: Meeting) {
        escalationConfirmedMeetingIDs.insert(meeting.ensuredStableID)
        guard persists else { return }
        defaults.set(escalationConfirmedMeetingIDs.map(\.uuidString),
                     forKey: Self.escalationKey)
    }

    // MARK: - Lot 12 : écran de préparation (2b)
    //
    // Ajouté **en fin de type** : les lots 11 à 14 complètent tous cette
    // classe, et l'insertion au milieu est ce qui a produit six conflits à
    // l'intégration de la vague précédente.

    /// Le bouton `Historique` de l'en-tête a déplié la carte `HISTORIQUE` sur
    /// tout le fil, au lieu des quatre dernières séances.
    ///
    /// Non persisté, comme le panneau de fiche projet du lot 9 : une carte
    /// dépliée est un geste, pas un réglage.
    var prepHistoryExpanded = false
}
