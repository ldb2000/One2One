import Testing
import Foundation
@testable import OneToOne

/// Les six commandes du composeur en 1:1 (spec §1.4 ; captures 2a
/// `/engagement /feedback /privé` et 5a `/promesse /demande /preuve`).
///
/// Le parseur de base (`NoteCommandParser`, lot 2) sait déjà produire les
/// **natures de note** ; ce qu'il ne sait pas faire, c'est produire un
/// `Commitment` ou un `AgendaItem`. C'est tout l'objet de cette extension.
@Suite("Commandes 1:1 — les six commandes du composeur (spec §1.4, §3.3, §6.2)")
struct NoteCommandOneOnOneTests {

    // MARK: - Engagements

    @Test("/engagement crée un engagement porté par mon côté")
    func engagementPourMoi() {
        let manager = NoteCommandParser.parseOneOnOne("/engagement Arbitrer renfort ou décalage du Webcast",
                                                       role: .manager)
        #expect(manager.oneOnOnePill == .engagement)
        let engagement = try? #require(manager.commitment)
        #expect(engagement?.text == "Arbitrer renfort ou décalage du Webcast")
        #expect(engagement?.ownerSide == .manager)
        // Un engagement n'est pas une note : le fil le range dans sa colonne.
        #expect(manager.note == nil)
        #expect(manager.agenda == nil)

        let collab = NoteCommandParser.parseOneOnOne("/engagement Cadrer la formation Admin",
                                                      role: .collaborator)
        #expect(collab.commitment?.ownerSide == .collaborator)
    }

    @Test("/promesse crée un engagement porté par le manager, quel que soit mon rôle")
    func promesseToujoursCoteManager() {
        for role in OneOnOneSide.allCases {
            let parsed = NoteCommandParser.parseOneOnOne("/promesse Grille de compensation des astreintes",
                                                          role: role)
            #expect(parsed.basePill == .promise)
            #expect(parsed.commitment?.ownerSide == .manager)
            #expect(parsed.commitment?.text == "Grille de compensation des astreintes")
            // Elle laisse aussi une trace dans les notes de la séance : c'est
            // ce qui a été dit, à l'instant où ça a été dit.
            #expect(parsed.note?.kind == .promise)
        }
    }

    // MARK: - Feedback

    @Test("/feedback prend le côté de sa section")
    func feedbackParSection() {
        let donne = NoteCommandParser.parseOneOnOne("/feedback Présentation COSUI très claire",
                                                     role: .manager, section: .given)
        #expect(donne.note?.kind == .feedback)
        #expect(donne.note?.authorSide == .me)

        let recu = NoteCommandParser.parseOneOnOne("/feedback Les arbitrages budget arrivent trop tard",
                                                    role: .manager, section: .received)
        #expect(recu.note?.authorSide == .collaborator)

        // Côté collaborateur, celui qui me parle est mon manager.
        let recuParLeCollab = NoteCommandParser.parseOneOnOne("/feedback Retour positif sur le COSUI",
                                                               role: .collaborator, section: .received)
        #expect(recuParLeCollab.note?.authorSide == .manager)
    }

    // MARK: - Privé

    @Test("/privé rend la ligne privée")
    func priveRendPrive() {
        let parsed = NoteCommandParser.parseOneOnOne("/privé Risque de départ si la mobilité n'avance pas",
                                                      role: .manager)
        #expect(parsed.basePill == .secret)
        #expect(parsed.note?.kind == .note)
        #expect(parsed.note?.visibility == .private)
        #expect(parsed.togglesPrivacy)
    }

    // MARK: - Demandes et preuves

    @Test("/demande crée une note et un sujet de type demande")
    func demandeCreeUnSujet() {
        let parsed = NoteCommandParser.parseOneOnOne("/demande Mobilité vers l'architecture",
                                                      role: .collaborator)
        #expect(parsed.basePill == .request)
        #expect(parsed.note?.kind == .request)
        let sujet = try? #require(parsed.agenda)
        #expect(sujet?.kind == .request)
        #expect(sujet?.text == "Mobilité vers l'architecture")
        #expect(sujet?.addedBySide == .collaborator)
        // Le collaborateur garde ses lignes pour lui par défaut (spec §6.1).
        #expect(sujet?.visibility == .private)
        #expect(parsed.note?.visibility == .private)
    }

    @Test("/preuve crée une note de preuve")
    func preuveCreeUneNote() {
        let parsed = NoteCommandParser.parseOneOnOne("/preuve Base PostgreSQL dédiée préparée",
                                                      role: .collaborator)
        #expect(parsed.basePill == .proof)
        #expect(parsed.note?.kind == .proof)
        #expect(parsed.commitment == nil)
        #expect(parsed.agenda == nil)
    }

    // MARK: - Robustesse de la reconnaissance

    @Test("Accents et casse sont ignorés")
    func accentsEtCasse() {
        for ecriture in ["/privé", "/prive", "/PRIVÉ", "/Prive", "/private"] {
            let parsed = NoteCommandParser.parseOneOnOne("\(ecriture) Ligne", role: .manager)
            #expect(parsed.note?.visibility == .private, "\(ecriture) doit être reconnu")
        }
        for ecriture in ["/engagement", "/ENGAGEMENT", "/Engagement"] {
            let parsed = NoteCommandParser.parseOneOnOne("\(ecriture) Ligne", role: .manager)
            #expect(parsed.commitment != nil, "\(ecriture) doit être reconnu")
        }
        for ecriture in ["/demande", "/DEMANDE", "/request"] {
            let parsed = NoteCommandParser.parseOneOnOne("\(ecriture) Ligne", role: .collaborator)
            #expect(parsed.agenda?.kind == .request, "\(ecriture) doit être reconnu")
        }
    }

    @Test("Une commande inconnue reste du texte")
    func commandeInconnue() {
        let parsed = NoteCommandParser.parseOneOnOne("/engagemnt Arbitrer le renfort", role: .manager)
        #expect(parsed.basePill == nil)
        #expect(parsed.oneOnOnePill == nil)
        #expect(parsed.commitment == nil)
        // La ligne n'est ni mangée ni tronquée : elle part telle qu'elle a été
        // tapée, barre oblique comprise.
        #expect(parsed.note?.text == "/engagemnt Arbitrer le renfort")
        #expect(parsed.note?.kind == .note)
    }

    @Test("Une ligne libre devient une note du côté de sa section")
    func ligneLibre() {
        let parsed = NoteCommandParser.parseOneOnOne("Deux migrations en parallèle + astreinte",
                                                      role: .manager, section: .received)
        #expect(parsed.note?.kind == .note)
        #expect(parsed.note?.text == "Deux migrations en parallèle + astreinte")
        #expect(parsed.note?.authorSide == .collaborator)
    }

    @Test("Une commande sans texte ne produit rien")
    func commandeSansTexte() {
        for ligne in ["/engagement", "/engagement   ", "/promesse", "/demande", "/privé"] {
            let parsed = NoteCommandParser.parseOneOnOne(ligne, role: .manager)
            #expect(parsed.note == nil, "« \(ligne) » ne doit créer aucune note")
            #expect(parsed.commitment == nil, "« \(ligne) » ne doit créer aucun engagement")
            #expect(parsed.agenda == nil, "« \(ligne) » ne doit créer aucun sujet")
        }
    }

    @Test("/action reste la main du composeur du rail")
    func actionOuvreLeComposeur() {
        let parsed = NoteCommandParser.parseOneOnOne("/action Rappeler le prestataire", role: .manager)
        #expect(parsed.opensActionComposer)
        #expect(parsed.note == nil)
    }

    // MARK: - Catalogue

    @Test("Le catalogue dépend du type de réunion et du rôle")
    func catalogueParTypeEtRole() {
        #expect(NoteCommandCatalog.commands(for: .oneToOne, role: .manager).map(\.pill)
                == ["/engagement", "/feedback", "/privé"])
        #expect(NoteCommandCatalog.commands(for: .manager, role: .collaborator).map(\.pill)
                == ["/promesse", "/demande", "/preuve"])

        // Hors 1:1, les quatre pilules du lot 2, inchangées.
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(NoteCommandCatalog.commands(for: kind, role: nil).map(\.pill)
                    == NoteCommandParser.visiblePills.map(\.pill))
        }
    }

    @Test("Le rôle prime sur le type quand les deux sont connus")
    func roleQuiPrime() {
        // Un fil de rôle collaborateur ouvert sur une réunion enregistrée par
        // erreur en `.oneToOne` doit afficher les pilules du collaborateur :
        // c'est le rôle qui décide de ce que je peux écrire.
        #expect(NoteCommandCatalog.commands(for: .oneToOne, role: .collaborator).map(\.pill)
                == ["/promesse", "/demande", "/preuve"])
    }

    @Test("Sans rôle, un type 1:1 retombe sur le rôle qu'il implique")
    func roleDeduitDuType() {
        #expect(NoteCommandCatalog.commands(for: .oneToOne, role: nil).map(\.pill)
                == ["/engagement", "/feedback", "/privé"])
        #expect(NoteCommandCatalog.commands(for: .manager, role: nil).map(\.pill)
                == ["/promesse", "/demande", "/preuve"])
    }
}
