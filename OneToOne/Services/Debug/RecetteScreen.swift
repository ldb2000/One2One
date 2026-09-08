import Foundation

/// Les écrans de la refonte qu'une recette visuelle sait ouvrir sans clic —
/// le vocabulaire de `ONETOONE_SEED_DEMO_SCREEN`, et le code des captures de
/// `docs/superpowers/specs/refonte-2026-09/ecrans/`.
///
/// **Un seul crochet de recette.** Les lots 11 et 12 en avaient chacun câblé
/// un, dans le même `ContentView` : `ONETOONE_SEED_DEMO_SCREEN=2a` pour la
/// séance, `ONETOONE_SEED_OPEN=1to1` pour la préparation. Deux variables pour
/// le même besoin — désigner l'écran à photographier — dont l'une ne savait
/// pas choisir le mode et l'autre ne savait pas choisir la réunion. Il n'en
/// reste qu'une, et elle nomme l'écran.
///
/// Pur et `CaseIterable` exprès : c'est la table que le test parcourt, et
/// c'est elle qui garantit qu'aucun code n'ouvre la mauvaise réunion ou le
/// mauvais mode.
enum RecetteScreen: String, CaseIterable, Sendable {

    /// `1a-cockpit.png` — la réunion de projet en séance.
    case cockpit = "1a"
    /// `1b-espaces-kpi.png` — la même réunion, barre d'espaces et indicateurs.
    case espaces = "1b"
    /// `1c-poste-de-pilotage.png` — la même réunion en mode Relire.
    case posteDePilotage = "1c"
    /// `2a-1to1-manager-seance.png` — l'entretien mené, en séance.
    case oneOnOneSession = "2a"
    /// `2b-1to1-manager-preparation.png` — le même entretien, en préparation.
    case oneOnOnePreparation = "2b"
    /// `3a-tiroir-ressources.png` — la réunion de démonstration, tiroir ouvert.
    case tiroirRessources = "3a"
    /// `3b-fiche-projet.png` — la même réunion, fiche projet en panneau.
    case ficheProjet = "3b"
    /// `4a-capture-selecteur.png` — la même réunion, sélecteur de capture.
    case captureSelecteur = "4a"
    /// `6a-atelier-planche.png` — la réunion d'atelier et sa planche.
    case atelierPlanche = "6a"

    /// La réunion que l'écran demande. Trois seulement : le jeu de
    /// démonstration en porte trois, pas neuf.
    enum Cible: Equatable, Sendable {
        /// La réunion `[P25_110]` de `1a-cockpit.png`.
        case demonstration
        /// La dernière séance du fil 1:1 **mené** (Laurent NOMINÉ).
        case entretienMene
        /// La réunion d'atelier de `6a-atelier-planche.png`.
        case atelier
    }

    var cible: Cible {
        switch self {
        case .cockpit, .espaces, .posteDePilotage,
             .tiroirRessources, .ficheProjet, .captureSelecteur:
            return .demonstration
        case .oneOnOneSession, .oneOnOnePreparation:
            return .entretienMene
        case .atelierPlanche:
            return .atelier
        }
    }

    /// Le mode d'ouverture. Il est **écrit dans les réglages mémorisés** avant
    /// l'ouverture (`MeetingScreenModel.modeKey`) : c'est le seul moyen de
    /// l'imposer sans clic, et le seul qui survive au fait que
    /// `MeetingScreenModel.attach` relit `UserDefaults`.
    var mode: MeetingScreenModel.Mode {
        switch self {
        case .posteDePilotage:      return .review
        case .oneOnOnePreparation:  return .prepare
        case .cockpit, .espaces, .oneOnOneSession,
             .tiroirRessources, .ficheProjet, .captureSelecteur, .atelierPlanche:
            return .live
        }
    }

    /// Le code lu dans l'environnement, ou `nil` — auquel cas la recette
    /// ouvre le cockpit comme elle l'a toujours fait, sans imposer de mode.
    static func from(environment value: String?) -> RecetteScreen? {
        guard let value, !value.isEmpty else { return nil }
        return RecetteScreen(rawValue: value.lowercased())
    }
}
