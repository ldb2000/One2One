import Testing
import Foundation
@testable import OneToOne

/// Couvre `AgentWorkspacePlan` — la construction du dossier de travail que
/// l'agent explorera. C'est une fonction pure : elle prend des DTO et rend une
/// liste de fichiers, sans toucher au disque ni à SwiftData.
///
/// Ce que l'agent ne doit jamais voir (audio, transcription brute, autres
/// projets) n'est pas vérifié ici par un test : `AgentWorkspaceInput` n'a
/// simplement aucun champ pour le porter. C'est le compilateur qui tient la
/// garantie, pas une assertion.
struct AgentWorkspacePlanTests {

    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    private func input(
        request: String = "Rédige le mail de relance.",
        expectedFormat: String? = nil,
        project: AgentWorkspaceInput.Project? = nil,
        collaborator: AgentWorkspaceInput.Collaborator? = nil,
        meetings: [AgentWorkspaceInput.Meeting] = [],
        mails: [AgentWorkspaceInput.Mail] = [],
        alerts: [AgentWorkspaceInput.Alert] = []
    ) -> AgentWorkspaceInput {
        AgentWorkspaceInput(
            action: .init(
                title: "Relancer Dupont sur le budget",
                request: request,
                dueDate: date("2026-08-15T09:00:00Z"),
                isUrgent: true,
                isImportant: false,
                audience: "Moi",
                comments: ["Vu en comité le 3 août"]
            ),
            expectedFormat: expectedFormat,
            project: project,
            collaborator: collaborator,
            meetings: meetings,
            mails: mails,
            alerts: alerts
        )
    }

    private func plan(_ input: AgentWorkspaceInput) -> [AgentWorkspaceFile] {
        AgentWorkspacePlan.plan(for: input, timeZone: utc)
    }

    private func file(_ files: [AgentWorkspaceFile], _ path: String) -> AgentWorkspaceFile? {
        files.first { $0.path == path }
    }

    // MARK: - Le socle

    @Test func alwaysWritesTheBriefAndTheSystemPrompt() {
        let paths = plan(input()).map(\.path)

        #expect(paths.contains("BRIEF.md"))
        #expect(paths.contains("AGENT.md"))
    }

    @Test func writesNothingElseWhenThereIsNoContext() {
        #expect(plan(input()).map(\.path).sorted() == ["AGENT.md", "BRIEF.md"])
    }

    @Test func declaresTheFoldersTheAgentWillFill() {
        #expect(AgentWorkspacePlan.directories == ["contexte", "echange", "livrables"])
    }

    // MARK: - Le brief

    @Test func theBriefCarriesTheRequestAndTheAction() {
        let brief = try! #require(file(plan(input()), "BRIEF.md")).contents

        #expect(brief.contains("Rédige le mail de relance."))
        #expect(brief.contains("Relancer Dupont sur le budget"))
        #expect(brief.contains("2026-08-15"))
        #expect(brief.contains("Vu en comité le 3 août"))
    }

    @Test func theBriefNamesTheExpectedFormatWhenOneIsImposed() {
        let brief = try! #require(file(plan(input(expectedFormat: "docx")), "BRIEF.md")).contents
        #expect(brief.contains("docx"))
    }

    @Test func theBriefLeavesTheFormatOpenByDefault() {
        let brief = try! #require(file(plan(input()), "BRIEF.md")).contents
        #expect(brief.lowercased().contains("au choix"))
    }

    // MARK: - Le prompt système

    @Test func theSystemPromptStatesTheEndOfTurnContract() {
        let agent = try! #require(file(plan(input()), "AGENT.md")).contents

        #expect(agent.contains("etat.json"))
        #expect(agent.contains("\"question\""))
        #expect(agent.contains("\"livrable\""))
        #expect(agent.contains("\"bloque\""))
        #expect(agent.contains("echange/question.md"))
    }

    @Test func theSystemPromptExplainsHowToProduceOfficeFiles() {
        let agent = try! #require(file(plan(input()), "AGENT.md")).contents

        #expect(agent.contains("uv run"))
        #expect(agent.contains("python-docx"))
        #expect(agent.contains("livrables/"))
    }

    // MARK: - Le contexte

    @Test func writesTheProjectSheetOnlyWhenThereIsAProject() {
        #expect(file(plan(input()), "contexte/projet.md") == nil)

        let withProject = plan(input(project: .init(
            name: "Refonte SI", phase: "Cadrage", sponsor: "Martin", entity: "DSI",
            summary: "Remplacement du socle applicatif."
        )))
        let sheet = try! #require(file(withProject, "contexte/projet.md")).contents

        #expect(sheet.contains("Refonte SI"))
        #expect(sheet.contains("Cadrage"))
        #expect(sheet.contains("Martin"))
        #expect(sheet.contains("Remplacement du socle applicatif."))
    }

    @Test func writesTheCollaboratorSheetOnlyWhenThereIsOne() {
        #expect(file(plan(input()), "contexte/collaborateur.md") == nil)

        let withCollaborator = plan(input(collaborator: .init(
            name: "Claire Dupont", role: "Architecte", notes: "Prend le lead sur le socle."
        )))
        let sheet = try! #require(file(withCollaborator, "contexte/collaborateur.md")).contents

        #expect(sheet.contains("Claire Dupont"))
        #expect(sheet.contains("Architecte"))
    }

    @Test func writesTheAlertsOnlyWhenThereAreSome() {
        #expect(file(plan(input()), "contexte/alertes.md") == nil)

        let withAlerts = plan(input(alerts: [
            .init(title: "Budget non arbitré", severity: "Élevé", detail: "Attente du sponsor.")
        ]))
        let sheet = try! #require(file(withAlerts, "contexte/alertes.md")).contents

        #expect(sheet.contains("Budget non arbitré"))
        #expect(sheet.contains("Élevé"))
    }

    // MARK: - Réunions

    @Test func writesOneFilePerMeetingNumberedMostRecentFirst() {
        let files = plan(input(meetings: [
            .init(title: "Comité de pilotage", date: date("2026-07-01T09:00:00Z"), report: "Ancien"),
            .init(title: "Point budget", date: date("2026-08-03T09:00:00Z"), report: "Récent")
        ]))
        let paths = files.map(\.path).filter { $0.hasPrefix("contexte/reunions/") }

        #expect(paths == ["contexte/reunions/001-point-budget.md",
                          "contexte/reunions/002-comite-de-pilotage.md"])
    }

    @Test func theMeetingFileCarriesItsDateAndReport() {
        let files = plan(input(meetings: [
            .init(title: "Point budget", date: date("2026-08-03T09:00:00Z"), report: "Le budget glisse.")
        ]))
        let contents = try! #require(file(files, "contexte/reunions/001-point-budget.md")).contents

        #expect(contents.contains("2026-08-03"))
        #expect(contents.contains("Le budget glisse."))
    }

    @Test func keepsOnlyTheTenMostRecentMeetings() {
        let meetings = (1...15).map {
            AgentWorkspaceInput.Meeting(
                title: "Réunion \($0)",
                date: date(String(format: "2026-08-%02dT09:00:00Z", $0)),
                report: "…"
            )
        }
        let paths = plan(input(meetings: meetings)).map(\.path).filter { $0.contains("/reunions/") }

        #expect(paths.count == AgentWorkspacePlan.maxMeetings)
        #expect(paths.first == "contexte/reunions/001-reunion-15.md")
    }

    @Test func buildsASafeFileNameFromAnAwkwardTitle() {
        let files = plan(input(meetings: [
            .init(title: "Revue N°3 : budget / RH (2026)", date: date("2026-08-03T09:00:00Z"), report: "…")
        ]))

        #expect(files.map(\.path).contains("contexte/reunions/001-revue-n-3-budget-rh-2026.md"))
    }

    @Test func fallsBackToAPlaceholderWhenTheTitleHasNoUsableCharacter() {
        let files = plan(input(meetings: [
            .init(title: "??? !!!", date: date("2026-08-03T09:00:00Z"), report: "…")
        ]))

        #expect(files.map(\.path).contains("contexte/reunions/001-sans-titre.md"))
    }

    // MARK: - Mails

    @Test func writesOneFilePerMailNumberedMostRecentFirst() {
        let files = plan(input(mails: [
            .init(subject: "Devis", date: date("2026-07-01T09:00:00Z"), sender: "a@x.fr", body: "…"),
            .init(subject: "Relance devis", date: date("2026-08-01T09:00:00Z"), sender: "b@x.fr", body: "…")
        ]))
        let paths = files.map(\.path).filter { $0.hasPrefix("contexte/mails/") }

        #expect(paths == ["contexte/mails/001-relance-devis.md", "contexte/mails/002-devis.md"])
    }

    @Test func keepsOnlyTheTwentyMostRecentMails() {
        let mails = (1...25).map {
            AgentWorkspaceInput.Mail(
                subject: "Mail \($0)",
                date: date(String(format: "2026-08-%02dT09:00:00Z", $0)),
                sender: "a@x.fr",
                body: "…"
            )
        }
        let paths = plan(input(mails: mails)).map(\.path).filter { $0.contains("/mails/") }

        #expect(paths.count == AgentWorkspacePlan.maxMails)
    }

    // MARK: - Troncature

    @Test func truncatesADocumentThatIsTooLongAndSaysSo() {
        let long = String(repeating: "a", count: AgentWorkspacePlan.maxCharactersPerDocument + 500)
        let files = plan(input(meetings: [
            .init(title: "Longue", date: date("2026-08-03T09:00:00Z"), report: long)
        ]))
        let contents = try! #require(file(files, "contexte/reunions/001-longue.md")).contents

        #expect(contents.count < long.count)
        #expect(contents.contains("tronqué"))
    }

    @Test func leavesAShortDocumentIntact() {
        let files = plan(input(meetings: [
            .init(title: "Courte", date: date("2026-08-03T09:00:00Z"), report: "Trois lignes.")
        ]))
        let contents = try! #require(file(files, "contexte/reunions/001-courte.md")).contents

        #expect(contents.contains("tronqué") == false)
    }
}
