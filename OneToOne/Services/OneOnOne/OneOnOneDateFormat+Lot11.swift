import Foundation

/// Les deux écritures de date que la capture 2a ajoute aux quatre du lot 10 :
/// le **jour de la semaine** d'une échéance proche (`Vendredi`) et le jour en
/// mois complet de l'en-tête d'entretien (`4 septembre`).
///
/// Par extension, dans un fichier à part : `OneOnOneDateFormat.swift`
/// appartient au lot 10 et les lots se développent en parallèle. La raison
/// d'être du type ne change pas — les écritures de date du domaine 1:1 restent
/// **au même endroit**, plutôt que reconstruites dans chaque vue.
extension OneOnOneDateFormat {

    /// `Vendredi` — le jour de la semaine d'une échéance de la semaine en
    /// cours (pilule d'échéance du rail, capture 2a).
    ///
    /// Première lettre en majuscule : `DateFormatter` rend `vendredi` en
    /// français, et la pilule de la capture porte une capitale. La conversion
    /// est faite sur la première lettre seule (`localizedCapitalized`
    /// majusculerait aussi les mots composés d'une locale tierce).
    static func weekday(_ date: Date) -> String {
        let brut = formattedForOneOnOne(date, "EEEE")
        guard let premiere = brut.first else { return brut }
        return String(premiere).uppercased() + brut.dropFirst()
    }

    /// `4 septembre` — l'en-tête d'entretien de la barre du haut. Sans année :
    /// la capture n'en montre pas, et un entretien se situe dans l'année en
    /// cours.
    static func dayFullMonth(_ date: Date) -> String {
        formattedForOneOnOne(date, "d MMMM")
    }

    /// Même fabrique que celle du lot 10, recopiée parce qu'elle y est
    /// `private` — la rendre `internal` modifierait un fichier d'un autre lot.
    /// **Locale forcée `fr_FR`** : un poste réglé en anglais afficherait
    /// `Friday` au milieu de libellés français.
    private static func formattedForOneOnOne(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
