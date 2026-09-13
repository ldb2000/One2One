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
    /// `5a-1to1-collaborateur-seance.png` — l'entretien **subi**, en séance.
    case collaboratorSession = "5a"
    /// `5b-1to1-collaborateur-preparation.png` — le même entretien, en
    /// préparation : la carte étroite de la veille.
    case collaboratorPreparation = "5b"
    /// `3a-tiroir-ressources.png` — la réunion de démonstration, tiroir ouvert.
    case tiroirRessources = "3a"
    /// `3b-fiche-projet.png` — la même réunion, fiche projet en panneau.
    case ficheProjet = "3b"
    /// `4a-capture-selecteur.png` — la même réunion, sélecteur de capture.
    case captureSelecteur = "4a"
    /// `6a-atelier-planche.png` — la réunion d'atelier et sa planche.
    case atelierPlanche = "6a"
    /// `6b-atelier-planche-de-seance.png` — le même atelier en mode Relire.
    case atelierPlancheDeSeance = "6b"

    // MARK: Refonte de la gestion des projets (décision D6)
    //
    // **Préfixe `p`.** Les codes `1a`, `1c`, `2a` et `2b` de la maquette des
    // projets percutent quatre écrans de réunion déjà photographiables
    // (constat §2.4 de la spec). Les six écrans de ce chantier portent donc le
    // préfixe `p` — la regex du script accepte `[0-9a-z]*`.

    /// `2b-sidebar-variante-arbre-replie.png` — la barre latérale avec la
    /// section « Projets » et l'arbre par entité replié.
    case sectionProjets = "p2b"
    /// `1a-portfolio.png` — le tableau du portefeuille.
    case portefeuille = "p1a"
    /// `1c-palette-cmdk.png` — la palette `⌘K` ouverte sur « ged ».
    case palette = "p1c"
    /// `1d-ecran-projet-pilotage.png` — l'écran projet, onglet Pilotage.
    case ecranProjet = "p1d"
    /// `1f-vue-a-risque.png` — les projets groupés par motif.
    case aRisque = "p1f"
    /// `2a-sidebar-section-projets.png` — la barre latérale sans l'arbre par
    /// entité (bascule finale du chantier).
    case sectionProjetsFinale = "p2a"

    /// Ce que l'écran demande d'ouvrir : une réunion (les trois du jeu de
    /// démonstration, plus l'atelier) ou la **fenêtre principale** à une route
    /// donnée.
    enum Cible: Equatable, Sendable {
        /// La réunion `[P25_110]` de `1a-cockpit.png`.
        case demonstration
        /// La dernière séance du fil 1:1 **mené** (Laurent NOMINÉ).
        case entretienMene
        /// La dernière séance du fil 1:1 **subi** (Yann PENVEN me manage).
        case entretienSubi
        /// La réunion d'atelier de `6a-atelier-planche.png`.
        case atelier
        /// La fenêtre principale, à cette route (décision **D0** — sans le
        /// routeur, aucun de ces six écrans ne serait atteignable sans clic).
        /// **Aucune fenêtre de réunion n'est ouverte** dans ce cas.
        case fenetrePrincipale(MainRoute)
    }

    var cible: Cible {
        switch self {
        case .cockpit, .espaces, .posteDePilotage,
             .tiroirRessources, .ficheProjet, .captureSelecteur:
            return .demonstration
        case .oneOnOneSession, .oneOnOnePreparation:
            return .entretienMene
        case .collaboratorSession, .collaboratorPreparation:
            return .entretienSubi
        case .atelierPlanche, .atelierPlancheDeSeance:
            return .atelier

        // Les deux variantes de barre latérale et le portefeuille se
        // photographient sur le même écran : c'est la barre qui change entre
        // `p2b` et `p2a`, pas la colonne de détail.
        case .sectionProjets, .portefeuille, .palette, .sectionProjetsFinale:
            return .fenetrePrincipale(.portfolio)
        case .ecranProjet:
            // L'identifiant est **constant** — la table est statique, elle ne
            // peut pas lire un UUID tiré au sort au moment du semis.
            return .fenetrePrincipale(
                .project(RefonteDemoSeed.portfolioFocusProjectStableID, .pilotage))
        case .aRisque:
            return .fenetrePrincipale(.atRisk)
        }
    }

    /// Le terme que la palette doit porter à son ouverture, ou `nil`.
    ///
    /// Seul `p1c` en a un : « ged », qui trouve « ASP – Installation nouvelle
    /// GED » (actif) et « RH – Migration GED documentaire » (archivé) dans le
    /// portefeuille de démonstration. Ici et non dans la vue : la palette
    /// n'existe pas encore (lot 3), et le routeur sait déjà porter le terme.
    var termeDePalette: String? {
        self == .palette ? RefonteDemoSeed.portfolioPaletteQuery : nil
    }

    /// Le mode d'ouverture. Il est **écrit dans les réglages mémorisés** avant
    /// l'ouverture (`MeetingScreenModel.modeKey`) : c'est le seul moyen de
    /// l'imposer sans clic, et le seul qui survive au fait que
    /// `MeetingScreenModel.attach` relit `UserDefaults`.
    var mode: MeetingScreenModel.Mode {
        switch self {
        case .posteDePilotage,
             .atelierPlancheDeSeance:
            return .review
        case .oneOnOnePreparation,
             .collaboratorPreparation:
            return .prepare
        case .cockpit, .espaces, .oneOnOneSession, .collaboratorSession,
             .tiroirRessources, .ficheProjet, .captureSelecteur, .atelierPlanche:
            return .live
        // Un écran de la fenêtre principale n'ouvre **aucune** réunion : son
        // mode ne sert à rien. `.prepare` est rendu parce que la propriété doit
        // être totale, pas parce que ces écrans préparent quoi que ce soit.
        case .sectionProjets, .portefeuille, .palette, .ecranProjet,
             .aRisque, .sectionProjetsFinale:
            return .prepare
        }
    }

    /// Le code lu dans l'environnement, ou `nil` — auquel cas la recette
    /// ouvre le cockpit comme elle l'a toujours fait, sans imposer de mode.
    static func from(environment value: String?) -> RecetteScreen? {
        guard let value, !value.isEmpty else { return nil }
        return RecetteScreen(rawValue: value.lowercased())
    }
}
