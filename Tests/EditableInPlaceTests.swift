import Testing
import Foundation
import AppKit
import SwiftUI
@testable import OneToOne

/// L'édition in-place de la refonte des projets (décision **D9**).
///
/// Ce qu'un test peut tenir sans session graphique : les deux règles pures
/// (normalisation, « faut-il écrire ? »), les libellés, les mesures, et le
/// fait que les deux `NSViewRepresentable` reçoivent bien une fonte Plex —
/// le piège de la refonte réunion, où un `.font()` SwiftUI posé sur un
/// `NSTextField` n'avait aucun effet (constat §2.14).
@Suite("Édition in-place — le champ actif au clic")
@MainActor
struct EditableInPlaceTests {

    private func modificateur(valeur: String,
                              mode: EditableInPlace<Text>.Mode = .ligne,
                              onValider: @escaping (String) -> Void = { _ in })
        -> EditableInPlace<Text> {
        EditableInPlace(valeur: valeur, placeholder: "Valeur", mode: mode,
                        onValider: onValider) { Text(valeur) }
    }

    // MARK: - Libellés et mesures

    @Test("Les libellés disent les trois gestes du contrat D9")
    func libelles() {
        #expect(EditableInPlace<Text>.aide == "Cliquer pour éditer")
        #expect(EditableInPlace<Text>.indiceLigne == "⏎ pour valider · esc pour annuler")
        #expect(EditableInPlace<Text>.indiceParagraphe == "⌘⏎ pour valider · esc pour annuler")
    }

    /// L'indication est en `inkMuted` : jamais sous 11,5 pt (§1.2 des
    /// contraintes globales).
    @Test("L'indication reste au-dessus du plancher d'inkMuted")
    func taillesDeLIndication() {
        #expect(EditableInPlace<Text>.tailleIndice >= 11.5)
    }

    @Test("Les hauteurs de champ sont celles de la conception")
    func hauteurs() {
        #expect(EditableInPlace<Text>.hauteurLigne == 22)
        #expect(EditableInPlace<Text>.hauteurParagraphe == 96)
    }

    // MARK: - Les deux règles pures

    @Test("La saisie est rognée de ses espaces de bord")
    func normalisation() {
        #expect(EditableInPlace<Text>.normalise("  Périmètre  ") == "Périmètre")
        #expect(EditableInPlace<Text>.normalise("\n\tPérimètre\n") == "Périmètre")
        #expect(EditableInPlace<Text>.normalise("   ").isEmpty)
    }

    /// Un `⏎` sur un champ qu'on n'a pas touché ne doit ni sauver, ni faire
    /// apparaître une bannière d'annulation qui n'annulerait rien.
    @Test("Une saisie inchangée ne déclenche aucune écriture")
    func riennEcritSansChangement() {
        #expect(!EditableInPlace<Text>.doitValider(saisie: "Périmètre", valeur: "Périmètre"))
        #expect(!EditableInPlace<Text>.doitValider(saisie: "  Périmètre ", valeur: "Périmètre"))
        #expect(EditableInPlace<Text>.doitValider(saisie: "Autre", valeur: "Périmètre"))
        // Vider un champ **est** un changement : c'est ainsi qu'on retire une
        // description de risque.
        #expect(EditableInPlace<Text>.doitValider(saisie: "", valeur: "Périmètre"))
    }

    // MARK: - Construction

    @Test("Le modificateur se construit dans ses deux modes")
    func construction() {
        #expect(modificateur(valeur: "Nom").mode == .ligne)
        #expect(modificateur(valeur: "Texte", mode: .paragraphe).mode == .paragraphe)
        #expect(modificateur(valeur: "Nom").placeholder == "Valeur")
    }

    @Test("La fonte par défaut est une fonte Plex, pas la fonte système")
    func fonteParDefaut() {
        let fonte = modificateur(valeur: "Nom").fonte
        #expect(fonte == NSFont.plexSans(13))
        #expect(fonte.pointSize == 13)
    }

    // MARK: - Ce que les deux champs AppKit acceptent désormais

    /// Le comportement **historique** est préservé : sans rappel, `⏎` et `esc`
    /// passent au responder suivant — c'est ce qui laisse `.onExitCommand` du
    /// panneau de fiche projet fermer celui-ci.
    @Test("Sans rappel, le champ ne consomme ni ⏎ ni esc")
    func comportementHistorique() {
        var texte = ""
        let champ = EditableTextField(placeholder: "P",
                                      text: Binding(get: { texte }, set: { texte = $0 }))
        #expect(champ.onSubmit == nil)
        #expect(champ.onCancel == nil)
        let editeur = EditableTextEditor(text: Binding(get: { texte }, set: { texte = $0 }))
        #expect(editeur.onSubmit == nil)
        #expect(editeur.onCancel == nil)
        #expect(editeur.font == nil)
        #expect(!editeur.transparent)
    }

    @Test("Les deux rappels arrivent bien au coordinateur")
    func rappelsCables() {
        var valide = false
        var annule = false
        var texte = "a"
        let liaison = Binding(get: { texte }, set: { texte = $0 })

        let champ = EditableTextField(placeholder: "P", text: liaison,
                                      onSubmit: { valide = true },
                                      onCancel: { annule = true })
        let coordinateur = champ.makeCoordinator()
        coordinateur.onSubmit?()
        coordinateur.onCancel?()
        #expect(valide)
        #expect(annule)

        valide = false
        annule = false
        let editeur = EditableTextEditor(text: liaison,
                                         onSubmit: { valide = true },
                                         onCancel: { annule = true })
        let coordinateurTexte = editeur.makeCoordinator()
        coordinateurTexte.onSubmit?()
        coordinateurTexte.onCancel?()
        #expect(valide)
        #expect(annule)
    }

    /// `configure` est la partie testable de `EditableTextField` : elle pose
    /// la fonte sur le `NSTextField`, ce qu'un `.font()` SwiftUI ne fait pas.
    @Test("Le champ d'une ligne porte la fonte Plex qu'on lui donne")
    func fontePoseeSurLeChamp() {
        var texte = "Périmètre"
        let champ = EditableTextField(placeholder: "P",
                                      text: Binding(get: { texte }, set: { texte = $0 }),
                                      style: .plain,
                                      font: .plexSans(13))
        let natif = NSTextField()
        champ.configure(natif)
        #expect(natif.font == NSFont.plexSans(13))
        #expect(!natif.isBezeled)
        #expect(!natif.isBordered)
    }
}
