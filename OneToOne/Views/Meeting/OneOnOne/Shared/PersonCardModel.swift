import Foundation

/// Les libellés de la carte personne du 1:1 (capture 2a : `Laurent NOMINÉ`,
/// `Ingénieur CI/CD · dans l'équipe depuis 3 ans`, `DERNIER 1:1 21 août · il y
/// a 2 sem.`, `RYTHME Toutes les 2 sem.`) — **pur**.
///
/// Les deux métriques viennent du fil et de l'annuaire, jamais d'un calcul
/// refait dans la vue : la capture 2b affiche les mêmes, et deux calculs
/// finiraient par deux valeurs.
@MainActor
enum PersonCardModel {

    /// Le nom qu'affichent les deux en-têtes faute de collaborateur rattaché
    /// au fil : un entretien sans personne n'est pas un entretien, et le dire
    /// vaut mieux qu'un vide.
    static let fallbackName = "Sans interlocuteur"

    /// Nom affiché en tête de carte.
    static func name(of thread: OneOnOneThread) -> String {
        let nom = (thread.collaborator?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return nom.isEmpty ? fallbackName : nom
    }

    static func initials(of thread: OneOnOneThread) -> String {
        let nom = name(of: thread)
        return nom == fallbackName ? "?" : AvatarPalette.initials(for: nom)
    }

    /// Le rôle affichable de la personne du fil.
    ///
    /// « Néant » est la valeur que `CollaboratorIdentity` met dans une fiche
    /// dont le champ rôle portait une adresse : l'afficher serait pire que de
    /// ne rien afficher. Une seule définition, appelée par la carte personne
    /// (capture 2a) **et** par l'en-tête de préparation (capture 2b), qui
    /// avait recopié le filtre.
    static func role(of thread: OneOnOneThread) -> String {
        let role = (thread.collaborator?.role ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return role == CollaboratorIdentity.roleNeant ? "" : role
    }

    /// `Ingénieur CI/CD · dans l'équipe depuis 3 ans`.
    static func roleLine(of thread: OneOnOneThread, now: Date) -> String {
        OneOnOneSeniority.roleLine(role: role(of: thread),
                                   joinedAt: thread.collaborator?.joinedAt,
                                   now: now)
    }

    /// `21 août · il y a 2 sem.` — la date du **1:1 précédent** du fil et son
    /// ancienneté en semaines.
    ///
    /// La séance ouverte ne compte pas : « dernier 1:1 » désigne celui d'avant,
    /// et afficher la date du jour dirait « il y a 0 sem. » sur chaque écran.
    /// `Premier entretien` quand il n'y en a pas eu : c'est une information, pas
    /// un manque.
    static func lastMeetingLabel(of thread: OneOnOneThread, now: Date) -> String {
        let tenues = OneOnOneThreadStore.meetings(of: thread, now: now)
        guard let precedent = tenues.dropLast().last?.date else { return "Premier entretien" }
        let semaines = Int(now.timeIntervalSince(precedent) / (7 * 86_400))
        let anciennete = semaines <= 0 ? "cette semaine" : "il y a \(semaines) sem."
        return "\(OneOnOneDateFormat.dayMonth(precedent)) · \(anciennete)"
    }

    /// `Toutes les 2 sem.` — la cadence convenue, abrégée pour une colonne de
    /// 300 px (`OneToOneCadence.label` écrit « Toutes les 2 semaines », qui
    /// passe à la ligne sous la métrique voisine).
    static func rhythmLabel(of thread: OneOnOneThread) -> String {
        switch thread.cadenceDays {
        case 7:            return "Hebdomadaire"
        case 14:           return "Toutes les 2 sem."
        case 30:           return "Mensuel"
        case 91:           return "Trimestriel"
        case let jours where jours > 0: return "Tous les \(jours) j."
        default:           return "Aucun rythme convenu"
        }
    }

    /// Les deux intitulés de métrique, tels que la capture les écrit.
    static let lastMeetingTitle = "DERNIER 1:1"
    static let rhythmTitle = "RYTHME"
}
