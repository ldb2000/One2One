import Foundation

/// L'écriture de date que la capture 5a ajoute aux six des lots 10 et 11 : le
/// **premier du mois avec son ordinal** (`1er sept.`).
///
/// Par extension, dans un fichier à part, comme au lot 11 :
/// `OneOnOneDateFormat.swift` appartient au lot 10 et les lots se développent
/// en parallèle. La raison d'être du type ne change pas — les écritures de date
/// du domaine 1:1 restent **au même endroit**, plutôt que reconstruites dans
/// chaque vue.
extension OneOnOneDateFormat {

    /// `1er sept.` le premier du mois, `29 août` les autres jours.
    ///
    /// `DateFormatter` ne sait pas rendre l'ordinal français : le gabarit
    /// `d MMM` donne « 1 sept. », qui se lit mal au milieu d'une phrase
    /// (« Réunion du 1 sept. »). Seul le premier prend un ordinal en français ;
    /// « 2ème sept. » n'existe pas, d'où le cas unique et non une table.
    static func dayMonthOrdinal(_ date: Date) -> String {
        let jour = Calendar(identifier: .gregorian).component(.day, from: date)
        guard jour == 1 else { return dayMonth(date) }
        return "1er " + dayMonth(date).split(separator: " ").dropFirst().joined(separator: " ")
    }
}
