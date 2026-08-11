import Testing
import SwiftData
@testable import OneToOne

/// Garde-fou de la suppression décidée dans
/// `docs/adr/2026-08-11-suppression-du-modele-interview.md`. Le 1:1 est un
/// `Meeting` de kind `.oneToOne`, et lui seul : un second modèle d'entretien
/// obligerait chaque calcul de la fiche collaborateur — retard depuis le
/// dernier 1:1, compteurs, graphe d'écart — à choisir lequel compter.
///
/// Le test lit les **noms** d'entités plutôt que les types : il compile aussi
/// bien avant qu'après la suppression, donc il échoue pour la bonne raison.
@Suite("Schéma — plus aucun modèle d'entretien")
struct SchemaWithoutInterviewTests {

    @Test("Ni Interview ni InterviewAttachment ne sont dans le schéma courant")
    func schemaCarriesNoInterview() {
        let names = Set(Schema(CurrentSchema.models).entities.map(\.name))
        #expect(!names.contains("Interview"))
        #expect(!names.contains("InterviewAttachment"))
    }
}
