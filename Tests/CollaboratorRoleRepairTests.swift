import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// « Si un rôle porte une adresse email, alors ce n'est pas un rôle. Le rôle
/// devient "Néant", et le champ email doit contenir l'email. » — règle de
/// l'auteur, 2026-08-13.
///
/// Origine : une ancienne version de l'import calendrier écrivait l'adresse de
/// l'invité dans `role` (`Collaborator(name:role: attendee.email ?? …)`,
/// commit 2cb5bf4 du 24 avril). 38 fiches ad hoc en portent la trace, dont
/// **16 où le champ `email` est vide** : pour celles-là, l'adresse n'existe
/// que dans `role`, et la vider la détruirait.
@Suite("Rôle pollué par une adresse — déplacer, jamais effacer")
struct CollaboratorRoleRepairTests {

    @Test("Une adresse dans le rôle, sans email : elle est déplacée, pas perdue")
    func addressMovesWhenEmailIsEmpty() {
        let repare = CollaboratorIdentity.repaired(role: "Malak.MAHMOUN@april.com", email: "")
        #expect(repare.email == "Malak.MAHMOUN@april.com")
        #expect(repare.role == "Néant")
    }

    @Test("Une adresse en double : le rôle devient Néant, l'email ne bouge pas")
    func duplicateAddressJustClearsTheRole() {
        let repare = CollaboratorIdentity.repaired(role: "nicolas.paoli@april.com",
                                                   email: "nicolas.paoli@april.com")
        #expect(repare.email == "nicolas.paoli@april.com")
        #expect(repare.role == "Néant")
    }

    /// Le cas qui n'existe pas dans le store d'aujourd'hui mais qui existera
    /// un jour : deux adresses différentes. Celle du champ email fait foi —
    /// c'est le champ prévu pour elle.
    @Test("Deux adresses différentes : celle du champ email l'emporte")
    func existingEmailWins() {
        let repare = CollaboratorIdentity.repaired(role: "ancien@april.com",
                                                   email: "nouveau@april.com")
        #expect(repare.email == "nouveau@april.com")
        #expect(repare.role == "Néant")
    }

    @Test("Un vrai rôle n'est pas touché")
    func realRoleIsLeftAlone() {
        let repare = CollaboratorIdentity.repaired(role: "Architecte Cloud & Cyber",
                                                   email: "jean@april.com")
        #expect(repare.role == "Architecte Cloud & Cyber")
        #expect(repare.email == "jean@april.com")
    }

    /// La réparation passe au démarrage, à chaque lancement : elle doit être
    /// sans effet la deuxième fois.
    @Test("Réparer deux fois donne le même résultat")
    func repairIsIdempotent() {
        let une = CollaboratorIdentity.repaired(role: "clara@april.com", email: "")
        let deux = CollaboratorIdentity.repaired(role: une.role, email: une.email)
        #expect(deux.role == une.role)
        #expect(deux.email == une.email)
    }

    @Test("La réparation s'applique à tout l'annuaire, et dit combien de fiches elle a touchées")
    func repairSweepsTheDirectory() throws {
        let context = ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
        let pollue = Collaborator(name: "MAHMOUN Malak", role: "Malak.MAHMOUN@april.com")
        let double = Collaborator(name: "PAOLI Nicolas", role: "n.paoli@april.com")
        double.email = "n.paoli@april.com"
        let sain = Collaborator(name: "FAYE Jean", role: "Architecte")
        for c in [pollue, double, sain] { context.insert(c) }

        let touchees = CollaboratorIdentity.repairRoles(in: context)

        #expect(touchees == 2)
        #expect(pollue.email == "Malak.MAHMOUN@april.com")
        #expect(pollue.role == "Néant")
        #expect(double.role == "Néant")
        #expect(sain.role == "Architecte")
        #expect(CollaboratorIdentity.repairRoles(in: context) == 0, "seconde passe sans effet")
    }
}
