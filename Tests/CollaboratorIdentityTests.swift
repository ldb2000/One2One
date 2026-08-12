import Testing
import Foundation
@testable import OneToOne

/// « L'email n'apparaît pas dans le sous-titre d'identité ni dans le champ
/// Poste / Rôle. » — critère d'acceptation de la spec.
///
/// Ce n'est pas qu'une règle d'affichage : **38 fiches sur 366 portent une
/// adresse dans leur champ `role`**, dont 21 où le rôle *est* l'adresse. Un
/// import d'annuaire a rempli le mauvais champ. L'écran refuse de l'afficher
/// comme un poste ; nettoyer les données reste un geste distinct.
@Suite("Identité — un rôle n'est pas une adresse mail")
struct CollaboratorIdentityTests {

    @Test("Une adresse dans le champ rôle ne s'affiche pas comme un poste")
    func emailInRoleIsNotShown() {
        #expect(CollaboratorIdentity.displayRole("nicolas.paoli@april.com") == "")
        #expect(CollaboratorIdentity.displayRole("  Laurent.DEBERTI@april.com ") == "")
    }

    @Test("Un vrai poste passe, même s'il contient un tiret ou une virgule")
    func realRolesPassThrough() {
        #expect(CollaboratorIdentity.displayRole("Architecte Cloud & Cyber") == "Architecte Cloud & Cyber")
        #expect(CollaboratorIdentity.displayRole("Architecte solution — Ad-hoc") == "Architecte solution — Ad-hoc")
        #expect(CollaboratorIdentity.displayRole("") == "")
    }

    /// Le sous-titre de l'en-tête : rôle · entité · projets, sans trou ni
    /// séparateur orphelin quand un morceau manque.
    @Test("Le sous-titre saute les morceaux absents sans laisser de séparateur")
    func subtitleSkipsMissingParts() {
        #expect(CollaboratorIdentity.subtitle(role: "Architecte", entity: "Plateformes", projects: 11)
                == "Architecte · Plateformes · 11 projets")
        #expect(CollaboratorIdentity.subtitle(role: "nicolas@april.com", entity: nil, projects: 0)
                == "")
        #expect(CollaboratorIdentity.subtitle(role: "", entity: "Plateformes", projects: 1)
                == "Plateformes · 1 projet")
    }
}
