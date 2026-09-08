import Testing
import Foundation
@testable import OneToOne

/// Le dossier introduit par D5 (`recordings/<uuid>/documents/`) doit être
/// compté par l'écran Maintenance : le programme §2.4 point 6 l'exige pour
/// chaque nouvel emplacement de fichiers, et l'ADR
/// `2026-09-07-pieces-copiees-jamais-referencees.md` s'appuie dessus pour
/// assumer le doublement du disque (« l'écran Maintenance donne déjà le
/// chiffre »).
///
/// Le scan est testé isolément — sans base, sans `Application Support` réel :
/// c'est une lecture de dossier, elle n'a pas besoin du reste.
@Suite("Stockage : le dossier des pièces copiées")
struct StorageStatsDocumentsTests {

    private func makeRecordings() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func write(_ octets: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: octets).write(to: url)
    }

    @Test("Les pièces copiées sont comptées, réunion par réunion")
    func compte() throws {
        let recordings = try makeRecordings()
        defer { try? FileManager.default.removeItem(at: recordings) }
        try write(1_000, to: recordings.appendingPathComponent("A/documents/20260904-091500_a.pdf"))
        try write(2_000, to: recordings.appendingPathComponent("A/documents/20260904-091501_b.xlsx"))
        try write(3_000, to: recordings.appendingPathComponent("B/documents/20260904-092000_c.png"))

        let (octets, nombre) = StorageStatsService.documentsUsage(inRecordings: recordings)
        #expect(octets == 6_000)
        #expect(nombre == 3)
    }

    /// Les WAV vivent directement sous `recordings/<uuid>/` et les captures
    /// sous `slides/` : ni les uns ni les autres ne doivent tomber dans le
    /// compte des pièces, sinon la répartition de l'écran Maintenance
    /// double-compte.
    @Test("Ni les WAV ni les captures ne sont comptés")
    func pasDeDoubleCompte() throws {
        let recordings = try makeRecordings()
        defer { try? FileManager.default.removeItem(at: recordings) }
        try write(9_000, to: recordings.appendingPathComponent("A/seance.wav"))
        try write(8_000, to: recordings.appendingPathComponent("A/slides/001.png"))
        try write(1_500, to: recordings.appendingPathComponent("A/documents/20260904-091500_a.pdf"))

        let (octets, nombre) = StorageStatsService.documentsUsage(inRecordings: recordings)
        #expect(octets == 1_500)
        #expect(nombre == 1)
    }

    @Test("Un dossier recordings absent ne coûte rien")
    func dossierAbsent() {
        let fantome = URL(fileURLWithPath: "/tmp/onetoone-absent-\(UUID().uuidString)")
        let (octets, nombre) = StorageStatsService.documentsUsage(inRecordings: fantome)
        #expect(octets == 0)
        #expect(nombre == 0)
    }
}
