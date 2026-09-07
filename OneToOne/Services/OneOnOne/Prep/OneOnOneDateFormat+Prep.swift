import Foundation

/// La quatrième écriture de date du domaine, celle que l'écran de préparation
/// ajoute : le **jour de la semaine** d'une échéance imminente.
///
/// La capture 2b écrit `Vendredi` dans la colonne `ÉCHÉANCE` quand la date
/// tombe dans les jours qui viennent, et `11 sept.` au-delà. Une date proche
/// s'appréhende par son jour, pas par son numéro : « vendredi » se situe sans
/// calcul, « 5 sept. » demande de compter.
///
/// Extension et non modification d'`OneOnOneDateFormat` : le lot 10 possède ce
/// fichier, et sa règle — un seul endroit nomme un format — est respectée
/// puisque le format reste dans le même type.
extension OneOnOneDateFormat {

    /// Fenêtre en jours à l'intérieur de laquelle une échéance s'écrit en jour
    /// de la semaine. Sept jours exactement : au huitième, deux dates
    /// porteraient le même nom de jour et on ne saurait plus laquelle est
    /// laquelle.
    static let weekdayWindowDays = 7

    /// `Vendredi` — le jour de la semaine, initiale en majuscule.
    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE"
        let brut = formatter.string(from: date)
        guard let premiere = brut.first else { return brut }
        return premiere.uppercased() + brut.dropFirst()
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
    static func dueDate(_ date: Date, now: Date) -> String {
        isWithinWeekdayWindow(date, now: now) ? weekday(date) : dayMonth(date)
    }
}
