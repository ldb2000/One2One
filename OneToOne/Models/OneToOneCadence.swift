import Foundation

/// Rythme convenu des tête-à-tête avec un collaborateur.
///
/// C'est **un engagement de l'utilisateur, pas une supposition de l'app** :
/// le défaut est `aucune`. Un défaut actif déclarerait en retard, du jour au
/// lendemain, les centaines de fiches de l'annuaire — dont celles créées ad
/// hoc par un import calendrier et jamais revues.
enum OneToOneCadence: String, CaseIterable, Codable, Sendable {
    case aucune
    case hebdomadaire
    case bimensuelle
    case mensuelle
    case trimestrielle

    var label: String {
        switch self {
        case .aucune:        return "Aucun"
        case .hebdomadaire:  return "Hebdomadaire"
        case .bimensuelle:   return "Toutes les 2 semaines"
        case .mensuelle:     return "Mensuel"
        case .trimestrielle: return "Trimestriel"
        }
    }

    /// Période convenue, en jours. `nil` quand aucun rythme n'est convenu —
    /// et alors rien n'est jamais en retard.
    var periodInDays: Int? {
        switch self {
        case .aucune:        return nil
        case .hebdomadaire:  return 7
        case .bimensuelle:   return 14
        case .mensuelle:     return 30
        case .trimestrielle: return 91
        }
    }
}

/// Écart depuis le dernier tête-à-tête, et retard éventuel.
enum OneToOneRhythm {

    /// Les types de réunion qui remettent le compteur à zéro. Une réunion
    /// projet n'en est pas un : on s'y est vus, on ne s'est pas parlé.
    private static let faceToFace: Set<MeetingKind> = [.oneToOne, .manager]

    /// Date du dernier tête-à-tête tenu, `nil` s'il n'y en a jamais eu.
    static func lastFaceToFace(for collaborator: Collaborator, now: Date) -> Date? {
        collaborator.meetings
            .filter { faceToFace.contains($0.kind) && $0.date <= now }
            .map(\.date)
            .max()
    }

    /// Nombre de semaines entières écoulées depuis le dernier tête-à-tête.
    static func weeksSinceLast(for collaborator: Collaborator, now: Date) -> Int? {
        guard let last = lastFaceToFace(for: collaborator, now: now) else { return nil }
        return Int(now.timeIntervalSince(last) / (7 * 86_400))
    }

    /// Les écarts successifs, en semaines : entre deux tête-à-tête
    /// consécutifs, puis l'écart courant depuis le dernier.
    ///
    /// Remplace la heatmap de 52 semaines, vide à 90 % : un carré vide ne dit
    /// rien, alors que passer de 2 à 11 semaines d'écart est le signal du
    /// produit. Vide s'il n'y a jamais eu de tête-à-tête — il n'y a pas de
    /// rythme à tracer, il y en a un à commencer.
    static func gaps(for collaborator: Collaborator, now: Date) -> [Int] {
        let dates = collaborator.meetings
            .filter { faceToFace.contains($0.kind) && $0.date <= now }
            .map(\.date)
            .sorted()
        guard let dernier = dates.last else { return [] }

        var ecarts = zip(dates, dates.dropFirst()).map { precedent, suivant in
            Int(suivant.timeIntervalSince(precedent) / (7 * 86_400))
        }
        ecarts.append(Int(now.timeIntervalSince(dernier) / (7 * 86_400)))
        return ecarts
    }

    /// Gravité d'un écart, aux seuils de la spec.
    enum Severity { case neutre, attention, alerte }

    static func severity(ofGap semaines: Int) -> Severity {
        switch semaines {
        case ..<5: return .neutre
        case 5...7: return .attention
        default:   return .alerte
        }
    }

    /// Vrai quand l'écart dépasse la cadence convenue.
    ///
    /// Faux sans cadence — un écart n'est un retard que face à un rythme
    /// convenu. Faux aussi sans aucun tête-à-tête tenu : il n'y a pas de
    /// rythme à rattraper, il y en a un à commencer.
    static func isLate(for collaborator: Collaborator, now: Date) -> Bool {
        guard let period = collaborator.oneToOneCadence.periodInDays,
              let last = lastFaceToFace(for: collaborator, now: now)
        else { return false }
        return now.timeIntervalSince(last) > Double(period) * 86_400
    }
}
