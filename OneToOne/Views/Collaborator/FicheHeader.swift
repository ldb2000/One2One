import Foundation

/// Un compteur de l'en-tête : sa valeur, son libellé, et ce qu'il vaut.
struct FicheCounter: Equatable {
    enum Level { case neutre, attention, alerte }
    let value: String
    let label: String
    let level: Level
}

/// Ce que l'en-tête d'une fiche mesure.
///
/// **La cadence tranche.** Choisir un rythme de tête-à-tête pour quelqu'un,
/// c'est déclarer qu'on le suit ; c'est alors le retard, les engagements et la
/// dette qui comptent. Sans cadence, la personne est un collègue qu'on croise
/// en comité : l'en-tête montre ce qui existe — échanges, réunions, décisions.
///
/// Mesuré le 2026-08-13 sur le store réel : 8 collaborateurs sur 366 ont eu un
/// 1:1, 349 apparaissent dans une réunion. Servir les compteurs de suivi
/// partout afficherait « — 0 0 0 » en gros sur 341 fiches, à l'endroit le plus
/// visible de l'écran, pendant que le fil dessous porte trente lignes.
enum FicheHeader {

    static func isFollowed(_ collaborator: Collaborator) -> Bool {
        collaborator.oneToOneCadence != .aucune
    }

    static func counters(for collaborator: Collaborator, now: Date) -> [FicheCounter] {
        let ouvertes = collaborator.assignedTasks.filter { !$0.isCompleted }
        let compteurOuvertes = FicheCounter(value: "\(ouvertes.count)",
                                            label: "ouvertes", level: .neutre)

        guard isFollowed(collaborator) else { return croises(collaborator, now, compteurOuvertes) }

        let enRetard = ouvertes.filter { ($0.dueDate ?? .distantFuture) < now }.count
        let engagements = EngagementLedger.pending(for: collaborator).count
        return [
            FicheCounter(value: semaines(OneToOneRhythm.weeksSinceLast(for: collaborator, now: now)),
                         label: "dernier 1:1",
                         level: OneToOneRhythm.isLate(for: collaborator, now: now) ? .attention : .neutre),
            FicheCounter(value: "\(enRetard)", label: "en retard",
                         level: enRetard > 0 ? .alerte : .neutre),
            compteurOuvertes,
            // Seuil bas, et c'est voulu : ce compteur mesure une confiance,
            // pas une charge. « ouvertes » reste neutre à dix.
            FicheCounter(value: "\(engagements)", label: "engagements",
                         level: EngagementLedger.level(count: engagements) == .alerte ? .alerte : .neutre)
        ]
    }

    private static func croises(_ collaborator: Collaborator, _ now: Date,
                                _ ouvertes: FicheCounter) -> [FicheCounter] {
        let tenues = MeetingStatsScope.held(collaborator.meetings).filter { $0.date <= now }
        let dernier = tenues.map(\.date).max()
        let decisions = tenues.reduce(0) { $0 + $1.decisionEntries.count }
        return [
            FicheCounter(value: semaines(dernier.map { Int(now.timeIntervalSince($0) / (7 * 86_400)) }),
                         label: "dernier échange", level: .neutre),
            FicheCounter(value: "\(tenues.count)", label: "réunions", level: .neutre),
            FicheCounter(value: "\(decisions)", label: "décisions", level: .neutre),
            ouvertes
        ]
    }

    private static func semaines(_ n: Int?) -> String {
        guard let n else { return "—" }
        return "\(n) sem."
    }
}
