import Foundation

/// Les écritures de date que les **écrans** 1:1 ajoutent aux quatre du lot 10 :
/// le jour de la semaine d'une échéance imminente (`Vendredi`), le jour en mois
/// complet de l'en-tête d'entretien (`4 septembre`), et la règle qui choisit
/// entre les deux.
///
/// Par extension, dans un fichier à part : `OneOnOneDateFormat.swift` appartient
/// au lot 10, et la raison d'être du type ne change pas — les écritures de date
/// du domaine 1:1 restent **au même endroit**, plutôt que reconstruites dans
/// chaque vue.
///
/// **Un seul fichier pour les deux écrans.** Les lots 11 (séance, capture 2a) et
/// 12 (préparation, capture 2b) avaient chacun écrit son extension
/// (`+Lot11`, `+Prep`), avec deux `weekday(_:)` et **deux règles**
/// incompatibles pour choisir le jour de la semaine : la semaine calendaire
/// d'un côté, une fenêtre de sept jours de l'autre. Le critère d'acceptation du
/// chantier 2 demande qu'un engagement se lise pareil en 2a et en 2b : c'est
/// donc une seule règle, et c'est la **fenêtre de sept jours**, celle que
/// `ActionCard.libelleEcheance` (lot 3) applique déjà aux échéances d'action.
extension OneOnOneDateFormat {

    /// Fenêtre en jours à l'intérieur de laquelle une échéance s'écrit en jour
    /// de la semaine. Sept jours exactement : au huitième, deux dates
    /// porteraient le même nom de jour et on ne saurait plus laquelle est
    /// laquelle.
    static let weekdayWindowDays = 7

    /// `Vendredi` — le jour de la semaine d'une échéance imminente.
    ///
    /// Première lettre en majuscule : `DateFormatter` rend `vendredi` en
    /// français, et les pilules des captures portent une capitale. La
    /// conversion est faite sur la première lettre seule
    /// (`localizedCapitalized` majusculerait aussi les mots composés d'une
    /// locale tierce).
    static func weekday(_ date: Date) -> String {
        let brut = formattedForOneOnOneViews(date, "EEEE")
        guard let premiere = brut.first else { return brut }
        return String(premiere).uppercased() + brut.dropFirst()
    }

    /// `4 septembre` — l'en-tête d'entretien de la barre du haut. Sans année :
    /// la capture n'en montre pas, et un entretien se situe dans l'année en
    /// cours.
    static func dayFullMonth(_ date: Date) -> String {
        formattedForOneOnOneViews(date, "d MMMM")
    }

    /// Vrai quand `date` tombe dans les sept jours qui suivent `now`, bornes
    /// comprises pour le jour même et exclues au septième.
    static func isWithinWeekdayWindow(_ date: Date, now: Date) -> Bool {
        let calendrier = Calendar(identifier: .gregorian)
        let jours = calendrier.dateComponents([.day],
                                              from: calendrier.startOfDay(for: now),
                                              to: calendrier.startOfDay(for: date)).day ?? 0
        return jours >= 0 && jours < weekdayWindowDays
    }

    /// L'écriture d'une échéance : le jour de la semaine si elle est
    /// imminente, `11 sept.` sinon.
    ///
    /// La **seule** règle du domaine, appelée par la pilule d'échéance du rail
    /// de séance (`CommitmentsRailModel.duePill`) comme par la colonne
    /// `ÉCHÉANCE` du tableau de préparation (`CommitmentsTableModel.dueLabel`).
    static func dueDate(_ date: Date, now: Date) -> String {
        isWithinWeekdayWindow(date, now: now) ? weekday(date) : dayMonth(date)
    }

    /// Même fabrique que celle du lot 10, recopiée parce qu'elle y est
    /// `private` — la rendre `internal` modifierait un fichier d'un autre lot.
    /// **Locale forcée `fr_FR`** : un poste réglé en anglais afficherait
    /// `Friday` au milieu de libellés français.
    private static func formattedForOneOnOneViews(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
