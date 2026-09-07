import Foundation

/// Les trois écritures de date du domaine 1:1, au même endroit.
///
/// Les captures 2a, 2b, 5a et 5b mélangent trois formats — `→ 18/09`,
/// `21 août`, `4 sept. 2026` — et les rendent côte à côte dans la même colonne.
/// Chaque vue qui construirait son propre `DateFormatter` finirait par en
/// afficher un quatrième.
///
/// **Locale forcée en `fr_FR`** : l'app est en français (le programme met la
/// localisation hors périmètre), et un poste réglé en anglais afficherait
/// `Jul 10` au milieu de libellés français.
enum OneOnOneDateFormat {

    private static let locale = Locale(identifier: "fr_FR")

    /// `18/09` — la cible d'un report d'ordre du jour.
    static func shortSlashed(_ date: Date) -> String {
        formatted(date, "dd/MM")
    }

    /// `10 juil.` — la date d'une demande, d'un engagement pris.
    static func dayMonth(_ date: Date) -> String {
        formatted(date, "d MMM")
    }

    /// `4 sept. 2026` — l'en-tête d'un entretien, le titre d'un récap.
    static func dayMonthYear(_ date: Date) -> String {
        formatted(date, "d MMM yyyy")
    }

    /// `2026-09-04` — le nom d'un fichier du dossier annuel. Trié
    /// lexicographiquement, donc chronologiquement.
    static func isoDay(_ date: Date) -> String {
        formatted(date, "yyyy-MM-dd")
    }

    private static func formatted(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
