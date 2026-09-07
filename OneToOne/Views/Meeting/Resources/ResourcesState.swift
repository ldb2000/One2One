import Foundation
import Observation

/// L'état d'écran du tiroir Ressources et de la zone « À l'écran »
/// (spec §4.1, §4.2 ; capture `3a-tiroir-ressources.png`).
///
/// Vit à côté de `MeetingScreenModel` — une seule ligne y ajoute
/// `var resources = ResourcesState()` — et non dedans : le tiroir est une
/// surface superposée, il n'a pas à faire grossir le modèle de l'écran de
/// réunion, et le lot 6 doit pouvoir être relu sans traverser 350 lignes
/// d'état voisin.
///
/// **Rien n'est persisté.** Le tiroir ouvert, le filtre choisi et la pièce à
/// l'écran sont des intentions du moment : retrouver un partage actif trois
/// jours plus tard annoncerait aux participants un document que personne ne
/// regarde. Les seules valeurs durables du lot — l'épinglage et les trois
/// cases du pied — vivent en base.
@MainActor
@Observable
final class ResourcesState {

    // MARK: - Le tiroir

    /// Le tiroir de 396 px est déplié **au-dessus** de la colonne principale,
    /// qui reste interactive (spec §4.1 : « se superpose sans démonter la
    /// séance »).
    var isDrawerOpen = false

    /// Le filtre actif de l'en-tête.
    var filter: ResourcesFilter = .seance

    // MARK: - Partage à l'écran

    /// La ressource présentée aux participants, `nil` quand rien n'est partagé.
    ///
    /// Un identifiant et non l'objet : `ResourceItem` est une valeur reconstruite
    /// à chaque rendu, et retenir une copie périmée ferait afficher l'ancien nom
    /// d'une pièce qu'on vient de relier.
    private(set) var presentedResourceID: UUID?

    /// La page affichée de la pièce présentée (1-indexée, `p. 2` sur la
    /// capture). Toujours ramenée à 1 quand on change de document.
    private(set) var presentedPage = 1

    /// Le calque d'annotation est ouvert par-dessus l'aperçu.
    var isAnnotating = false

    // MARK: - Import

    /// Un import est en cours (copie + extraction + indexation).
    var isImporting = false

    /// Message d'erreur du dernier import, `nil` si tout va bien. Effacé au
    /// début de chaque tentative : un message qu'on n'efface jamais finit par
    /// décrire un incident résolu depuis longtemps.
    var importError: String?

    /// La pièce orpheline dont on cherche le fichier (invite « relier »).
    var relinkTargetID: UUID?

    // MARK: - Ouvertures

    /// Déplie le tiroir sur un filtre donné.
    ///
    /// Idempotent sur le filtre : rouvrir le tiroir sur « Captures » alors
    /// qu'il est déjà ouvert change le filtre — c'est ce que fait le bouton
    /// `Capture` de la barre du haut, et laisser le filtre précédent
    /// donnerait l'impression que le bouton n'a rien fait.
    func open(filter nouveau: ResourcesFilter? = nil) {
        if let nouveau { filter = nouveau }
        isDrawerOpen = true
    }

    func close() {
        isDrawerOpen = false
    }

    func toggle() {
        isDrawerOpen ? close() : open()
    }

    /// Ce qu'un **dépôt de fichiers** change dans l'état d'écran : le tiroir
    /// s'ouvre sur « Cette séance », et rien d'autre.
    ///
    /// Critère d'acceptation n° 1 du chantier 3 — « déposer un fichier pendant
    /// la séance ne provoque aucun changement d'écran ni perte de focus de
    /// saisie ». La règle est nommée ici, et non dispersée dans le `onDrop` de
    /// la vue, pour qu'un test puisse la tenir : c'est précisément le genre de
    /// régression qu'une ligne `screen.space = .resources` ajoutée « pour
    /// montrer le résultat » introduirait sans que rien ne le signale.
    ///
    /// - Returns: `false` si le dépôt était vide (aucun fichier reconnu) — le
    ///   tiroir reste alors dans l'état où il était.
    @discardableResult
    func acceptDrop(itemCount: Int) -> Bool {
        guard itemCount > 0 else { return false }
        importError = nil
        open(filter: .seance)
        return true
    }

    /// Ce qu'un **collage** (`⌘⇧V`) change : même règle que le dépôt, sur le
    /// filtre correspondant à ce qui a été collé.
    @discardableResult
    func acceptPaste(_ nature: ResourceItem.Nature) -> Bool {
        importError = nil
        open(filter: nature == .lien ? .liens : .seance)
        return true
    }

    // MARK: - Partage

    /// Met une ressource à l'écran des participants. Change toujours de page :
    /// on ne reprend pas un document à la page 2 d'un autre.
    func present(_ id: UUID) {
        presentedResourceID = id
        presentedPage = 1
        isAnnotating = false
    }

    /// `Arrêter le partage`. La pilule de la barre du haut disparaît alors —
    /// pas d'état grisé (spec §4.2).
    func stopPresenting() {
        presentedResourceID = nil
        presentedPage = 1
        isAnnotating = false
    }

    var isPresenting: Bool { presentedResourceID != nil }

    /// Change de page, borné à `1…pageCount`. Refuse plutôt que de dépasser :
    /// une page 0 ou une page 12 sur un document de 3 pages afficherait un
    /// aperçu vide aux participants.
    func goToPage(_ page: Int, pageCount: Int) {
        guard pageCount > 0 else { presentedPage = 1; return }
        presentedPage = max(1, min(page, pageCount))
    }
}
