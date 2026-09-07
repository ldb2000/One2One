import Testing
import Foundation
@testable import OneToOne

/// L'état d'écran du tiroir Ressources.
///
/// Le test central est `depotNeChangeNiEspaceNiModeNiFocus` : **critère
/// d'acceptation n° 1 du chantier 3**. Il ne vérifie pas un calcul mais une
/// absence — que déposer un fichier ne déplace rien d'autre. C'est le genre de
/// propriété qu'une ligne ajoutée « pour montrer le résultat »
/// (`screen.space = .resources`) casse sans que rien ne le signale.
@Suite("Tiroir Ressources : l'état d'écran")
@MainActor
struct ResourcesStateTests {

    private func makeScreen() -> MeetingScreenModel {
        MeetingScreenModel(defaults: UserDefaults(
            suiteName: "onetoone.tests.resources.\(UUID().uuidString)")!)
    }

    // MARK: - Critère n° 1 du chantier 3

    @Test("Déposer un fichier ne change ni espace, ni mode, ni focus")
    func depotNeChangeNiEspaceNiModeNiFocus() {
        let screen = makeScreen()
        screen.space = .meeting
        screen.mode = .live
        screen.focusNoteComposer()
        let focusAvant = screen.noteComposerFocusToken
        screen.pendingNoteText = "Le chiffrage v3 annonce 21 000 €"

        let accepte = screen.resources.acceptDrop(itemCount: 2)

        #expect(accepte)
        #expect(screen.resources.isDrawerOpen)
        #expect(screen.resources.filter == .seance)
        // Rien d'autre n'a bougé : ni l'espace, ni le mode, ni le focus, ni la
        // note en cours de frappe.
        #expect(screen.space == .meeting)
        #expect(screen.mode == .live)
        #expect(screen.noteComposerFocusToken == focusAvant)
        #expect(screen.pendingNoteText == "Le chiffrage v3 annonce 21 000 €")
    }

    @Test("Ouvrir le tiroir ne change ni espace ni mode")
    func ouvertureNeChangeRien() {
        let screen = makeScreen()
        screen.space = .report
        screen.mode = .review
        screen.resources.open()
        #expect(screen.resources.isDrawerOpen)
        #expect(screen.space == .report)
        #expect(screen.mode == .review)
    }

    @Test("Un dépôt vide ne touche pas au tiroir")
    func depotVide() {
        let state = ResourcesState()
        #expect(!state.acceptDrop(itemCount: 0))
        #expect(!state.isDrawerOpen)
    }

    @Test("Un collage de lien ouvre le tiroir sur les liens")
    func collageDeLien() {
        let state = ResourcesState()
        state.filter = .projet
        #expect(state.acceptPaste(.lien))
        #expect(state.isDrawerOpen)
        #expect(state.filter == .liens)
    }

    @Test("Un collage d'image ouvre le tiroir sur la séance")
    func collageDImage() {
        let state = ResourcesState()
        state.filter = .projet
        #expect(state.acceptPaste(.fichier))
        #expect(state.filter == .seance)
    }

    // MARK: - Ouverture et filtre

    /// Le bouton `Capture` de la barre du haut ouvre le tiroir sur le filtre
    /// Captures, même s'il est déjà ouvert : laisser le filtre précédent
    /// donnerait l'impression que le bouton n'a rien fait.
    @Test("Rouvrir sur un autre filtre change le filtre")
    func reouvertureChangeLeFiltre() {
        let state = ResourcesState()
        state.open(filter: .seance)
        state.open(filter: .captures)
        #expect(state.isDrawerOpen)
        #expect(state.filter == .captures)
    }

    @Test("Ouvrir sans filtre garde celui qu'on avait")
    func ouvertureSansFiltre() {
        let state = ResourcesState()
        state.open(filter: .captures)
        state.close()
        state.open()
        #expect(state.filter == .captures)
    }

    @Test("La bascule ferme puis rouvre")
    func bascule() {
        let state = ResourcesState()
        state.toggle()
        #expect(state.isDrawerOpen)
        state.toggle()
        #expect(!state.isDrawerOpen)
    }

    // MARK: - Partage

    @Test("Changer de document repart de la première page")
    func changementDeDocument() {
        let state = ResourcesState()
        let a = UUID(), b = UUID()
        state.present(a)
        state.goToPage(3, pageCount: 5)
        #expect(state.presentedPage == 3)
        state.present(b)
        #expect(state.presentedResourceID == b)
        #expect(state.presentedPage == 1)
    }

    @Test("Arrêter le partage remet tout à zéro")
    func arretDuPartage() {
        let state = ResourcesState()
        state.present(UUID())
        state.goToPage(2, pageCount: 4)
        state.isAnnotating = true
        state.stopPresenting()
        #expect(!state.isPresenting)
        #expect(state.presentedResourceID == nil)
        #expect(state.presentedPage == 1)
        #expect(!state.isAnnotating)
    }

    /// Une page hors bornes afficherait un aperçu vide **aux participants** :
    /// on borne au lieu de suivre.
    @Test("La pagination est bornée")
    func paginationBornee() {
        let state = ResourcesState()
        state.present(UUID())
        state.goToPage(0, pageCount: 3)
        #expect(state.presentedPage == 1)
        state.goToPage(12, pageCount: 3)
        #expect(state.presentedPage == 3)
        state.goToPage(2, pageCount: 0)
        #expect(state.presentedPage == 1)
    }

    @Test("Annoter se referme au changement de document")
    func annotationRefermee() {
        let state = ResourcesState()
        state.present(UUID())
        state.isAnnotating = true
        state.present(UUID())
        #expect(!state.isAnnotating)
    }

    // MARK: - Options du pied

    @Test("Les deux premières cases sont cochées par défaut")
    func optionsParDefaut() {
        let options = AttachmentReportOptions.defaults
        #expect(options.attachPinned)
        #expect(options.grantAccessToParticipants)
        #expect(!options.pushToProject)
    }

    @Test("Les options font l'aller-retour par le JSON")
    func optionsAllerRetour() {
        var options = AttachmentReportOptions.defaults
        options.pushToProject = true
        options.grantAccessToParticipants = false
        #expect(AttachmentReportOptions.decode(options.encoded()) == options)
    }

    /// Un pied de tiroir sans cases serait un cul-de-sac, et une exception ici
    /// empêcherait d'ouvrir l'espace Ressources.
    @Test("Un JSON vide ou illisible retombe sur les défauts")
    func optionsJSONIllisible() {
        #expect(AttachmentReportOptions.decode("") == .defaults)
        #expect(AttachmentReportOptions.decode("{") == .defaults)
        #expect(AttachmentReportOptions.decode("null") == .defaults)
        #expect(AttachmentReportOptions.decode("[1,2,3]") == .defaults)
    }
}
