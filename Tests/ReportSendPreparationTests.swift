import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les trois cases du pied `À L'ENVOI DU RAPPORT` (spec §4.1), exécutées **au
/// moment de l'envoi** et pas à la génération : générer est un geste qu'on
/// répète pour ajuster un gabarit, et verser des pièces dans la fiche projet à
/// chaque essai la remplirait de doublons.
@Suite("À l'envoi du rapport — les trois cases du pied du tiroir")
@MainActor
struct ReportSendPreparationTests {

    private func contexte() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: cfg))
    }

    private func dossierTemporaire() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "lot15-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fichier(_ nom: String, dans dossier: URL) throws -> URL {
        let url = dossier.appending(path: nom)
        try Data("contenu".utf8).write(to: url)
        return url
    }

    @Test("Les pièces épinglées partent en annexe, et seulement si la case est cochée")
    func annexesPiecesEpinglees() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let source = try fichier("Chiffrage.xlsx", dans: racine)

        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        var options = AttachmentReportOptions.defaults
        #expect(ReportSendPreparation.annexPaths(for: reunion, options: options)
                == [source.path])
        options.attachPinned = false
        #expect(ReportSendPreparation.annexPaths(for: reunion, options: options).isEmpty)
    }

    @Test("Une pièce épinglée dont le fichier a disparu n'est pas jointe")
    func annexeFichierAbsent() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/inexistant-lot15.xlsx"))
        piece.pinnedAtT = 10
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()
        #expect(ReportSendPreparation.annexPaths(for: reunion,
                                                 options: .defaults).isEmpty)
    }

    @Test("Les destinataires sont les participants présents, quand la case est cochée")
    func destinatairesPresents() throws {
        let ctx = try contexte()
        let presente = Collaborator(name: "Marine LEROY")
        presente.email = "marine.leroy@exemple.fr"
        let refusee = Collaborator(name: "Zied B")
        refusee.email = "zied.b@exemple.fr"
        let enAttente = Collaborator(name: "Nicolas H")
        enAttente.email = "nicolas.h@exemple.fr"
        let sansMail = Collaborator(name: "Sans Mail")
        ctx.insert(presente); ctx.insert(refusee)
        ctx.insert(enAttente); ctx.insert(sansMail)

        let reunion = Meeting(title: "Revue", date: Date())
        reunion.participants = [presente, refusee, enAttente, sansMail]
        ctx.insert(reunion)
        try ctx.save()
        reunion.setParticipantStatus(.refused, for: refusee)
        reunion.setParticipantStatus(.pending, for: enAttente)

        var options = AttachmentReportOptions.defaults
        #expect(ReportSendPreparation.recipients(for: reunion, options: options)
                == ["marine.leroy@exemple.fr"])
        // Décocher, c'est dire « j'adresse le message moi-même ».
        options.grantAccessToParticipants = false
        #expect(ReportSendPreparation.recipients(for: reunion, options: options).isEmpty)
    }

    @Test("Le versement copie dans les documents du projet et laisse l'original intact")
    func versementProjet() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let source = try fichier("Chiffrage.xlsx", dans: racine)

        let projet = Project(code: "P25_110", name: "Marine", domain: "Assurance",
                             phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.project = projet
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        var options = AttachmentReportOptions.defaults
        options.pushToProject = true
        let copies = ReportSendPreparation.pushToProject(reunion, options: options,
                                                          base: racine)
        #expect(copies.count == 1)
        #expect(FileManager.default.fileExists(atPath: copies[0].path))
        // « Copie, jamais référence » (D5) : l'original ne bouge pas.
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(copies[0].path.contains("projects/P25_110"))
        #expect(projet.attachments.contains { $0.fileName == "Chiffrage.xlsx" })

        // Idempotent : verser deux fois ne crée pas deux `ProjectAttachment`.
        _ = ReportSendPreparation.pushToProject(reunion, options: options, base: racine)
        #expect(projet.attachments.filter { $0.fileName == "Chiffrage.xlsx" }.count == 1)
    }

    @Test("Case décochée, rien n'est versé")
    func versementDecoche() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let source = try fichier("Chiffrage.xlsx", dans: racine)
        let projet = Project(code: "P25_110", name: "Marine", domain: "A", phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.project = projet
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 1
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        #expect(ReportSendPreparation.pushToProject(reunion,
                                                     options: .defaults,
                                                     base: racine).isEmpty)
        #expect(projet.attachments.isEmpty)
    }

    @Test("Sans projet rattaché, le versement ne fait rien plutôt que d'échouer")
    func versementSansProjet() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let source = try fichier("Chiffrage.xlsx", dans: racine)
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 1
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        var options = AttachmentReportOptions.defaults
        options.pushToProject = true
        #expect(ReportSendPreparation.pushToProject(reunion, options: options,
                                                     base: racine).isEmpty)
    }

    @Test("Le plan d'envoi rassemble les trois cases d'un coup")
    func planComplet() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: racine) }
        let source = try fichier("Chiffrage.xlsx", dans: racine)

        let presente = Collaborator(name: "Marine LEROY")
        presente.email = "marine.leroy@exemple.fr"
        ctx.insert(presente)
        let projet = Project(code: "P25_110", name: "Marine", domain: "A", phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.project = projet
        reunion.participants = [presente]
        var options = reunion.reportAttachmentOptions
        options.pushToProject = true
        reunion.reportAttachmentOptions = options
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        let plan = ReportSendPreparation.prepare(reunion, base: racine)
        #expect(plan.attachmentPaths == [source.path])
        #expect(plan.recipients == ["marine.leroy@exemple.fr"])
        #expect(plan.projectCopies.count == 1)
    }
}
