import Foundation

/// Rappel associable à une date insérée depuis l'entrée « Date » du menu
/// `/`. Cinq choix, repris de `docs/superpowers/specs/2026-08-05-dates-et-rappels.md`
/// (chantier 2 : popover d'édition).
///
/// **Purement informatif pour l'instant** : rien ne planifie ni ne déclenche
/// ces rappels (chantier 3 de la même spec, « rappels réellement
/// déclenchés » — hors périmètre de ce sélecteur, coût élevé, dépend d'un
/// modèle de données). `SlashDatePickerPresenter` le remonte quand même dans
/// `SlashDateSelection` : la donnée est saisie et conservée par l'appelant,
/// à charge pour un futur chantier de la stocker et de la déclencher.
enum DateReminder: CaseIterable, Hashable {
    case none
    case sameDayAt9
    case dayBefore
    case twoDaysBefore
    case oneWeekBefore

    /// Libellé français affiché dans le menu « Rappel » du popover.
    var label: String {
        switch self {
        case .none: return "Aucun"
        case .sameDayAt9: return "Le jour même à 9 h"
        case .dayBefore: return "La veille"
        case .twoDaysBefore: return "2 jours avant"
        case .oneWeekBefore: return "1 semaine avant"
        }
    }
}

/// Résultat renvoyé par le sélecteur de date (`SlashController.presentDatePicker`)
/// quand l'utilisateur valide (bouton « Insérer »). Côté closure de
/// complétion, `nil` signifie annulation — voir la doc de la propriété
/// `presentDatePicker` sur `SlashController` pour ce que l'appelant doit
/// alors faire (rien : ni insertion, ni mutation du texte).
struct SlashDateSelection: Equatable {
    /// Date choisie dans le calendrier. Porte aussi l'heure choisie si
    /// `includesTime` est vrai ; sinon son composant heure est présent (la
    /// valeur `Date` a toujours une heure) mais **non significatif** —
    /// `SlashController.insertDate` ne l'émet pas dans le texte inséré tant
    /// que `includesTime` est faux.
    let date: Date

    /// Vrai si la bascule « Inclure l'heure » était activée à la
    /// validation. Détermine si `SlashController.insertDate` ajoute l'heure
    /// au texte inséré.
    let includesTime: Bool

    /// Rappel choisi dans le menu du même nom — voir la doc de `DateReminder`
    /// pour ce qu'il implique (ou plutôt : n'implique pas encore).
    let reminder: DateReminder

    init(date: Date, includesTime: Bool, reminder: DateReminder) {
        self.date = date
        self.includesTime = includesTime
        self.reminder = reminder
    }
}
