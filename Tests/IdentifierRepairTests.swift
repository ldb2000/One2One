import XCTest
@testable import OneToOne

/// Déduplication d'identifiants UUID.
///
/// Le piège SwiftData : un `UUID` non optionnel sur un `@Model` reçoit sa valeur à la
/// **migration**, pas à l'insertion — toutes les lignes migrées partagent alors le même
/// identifiant. On répare les données plutôt que de changer le schéma.
final class IdentifierRepairTests: XCTestCase {

    /// Objet minimal, sans SwiftData : c'est ce qui rend la règle testable seule.
    private final class Row {
        var id: UUID
        let label: String
        init(id: UUID, label: String) { self.id = id; self.label = label }
    }

    private func rows(_ pairs: [(UUID, String)]) -> [Row] {
        pairs.map { Row(id: $0.0, label: $0.1) }
    }

    func test_aucunDoublon_neRendRien() {
        let elements = rows([(UUID(), "a"), (UUID(), "b"), (UUID(), "c")])
        XCTAssertTrue(IdentifierRepair.duplicates(in: elements, identifier: \.id).isEmpty)
    }

    /// Le premier de chaque groupe est conservé : on ne réattribue que les suivants.
    func test_unGroupeDeTrois_rendLesDeuxDerniers() {
        let partage = UUID()
        let elements = rows([(partage, "a"), (partage, "b"), (partage, "c")])

        let aReattribuer = IdentifierRepair.duplicates(in: elements, identifier: \.id)

        XCTAssertEqual(aReattribuer.map(\.label), ["b", "c"])
    }

    /// Le cas réel après migration : toutes les lignes portent le même identifiant.
    func test_toutesLesLignesIdentiques_neConserveQueLaPremiere() {
        let partage = UUID()
        let elements = rows((0..<50).map { (partage, "l\($0)") })

        let aReattribuer = IdentifierRepair.duplicates(in: elements, identifier: \.id)

        XCTAssertEqual(aReattribuer.count, 49)
        XCTAssertFalse(aReattribuer.contains { $0.label == "l0" })
    }

    func test_plusieursGroupes_sontTraitesIndependamment() {
        let x = UUID(), y = UUID()
        let elements = rows([(x, "x1"), (y, "y1"), (x, "x2"), (UUID(), "seul"), (y, "y2")])

        let aReattribuer = IdentifierRepair.duplicates(in: elements, identifier: \.id)

        XCTAssertEqual(Set(aReattribuer.map(\.label)), ["x2", "y2"])
    }

    /// L'UUID tout à zéro est la valeur qu'une migration invente pour un champ non
    /// optionnel sans défaut : il doit être traité comme n'importe quel doublon.
    func test_lUUIDToutAZero_estUnDoublonCommeUnAutre() {
        let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let elements = rows([(zero, "a"), (zero, "b")])

        XCTAssertEqual(IdentifierRepair.duplicates(in: elements, identifier: \.id).map(\.label), ["b"])
    }

    func test_listeVide_neRendRien() {
        XCTAssertTrue(IdentifierRepair.duplicates(in: [Row](), identifier: \.id).isEmpty)
    }
}
