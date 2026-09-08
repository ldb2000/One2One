import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// « Transcrire + Rapport 1:1 » sur une réunion **sans fil `OneOnOneThread`
/// préexistant** — le cas du 2026-09-08, où l'utilisateur a importé un audio
/// sur une 1:1 toute neuve.
///
/// L'assemblage du prompt est la partie du flux qui touche au fil, aux
/// participants et aux engagements ; `AIReportService.assembleTemplatePrompt`
/// est extrait exprès pour être vérifiable sans réseau (cf. sa doc). Un fil
/// absent, un participant absent, un collaborateur nil : rien de tout cela ne
/// doit lever, ni rendre un prompt vide, ni laisser un `{{…}}` non résolu
/// partir vers le modèle.
@Suite("Rapport 1:1 sans fil préexistant")
@MainActor
struct RapportUnAUnSansFilTests {

    private func contexte() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: cfg))
        // Le gabarit `d2_oneToOne` du lot 15 doit être là : sans lui,
        // `defaultTemplate` rend nil et le prompt perd toute consigne 1:1.
        BuiltInTemplates.seedIfNeeded(in: ctx)
        try ctx.save()
        return ctx
    }

    private func reunion(in ctx: ModelContext, avecParticipant: Bool) throws -> Meeting {
        let r = Meeting(title: "1:1 Marc JACQUIER MJA/LDB", date: Date())
        r.kind = .oneToOne
        r.rawTranscript = "Bonjour Marc. Nous avons parlé de la grille d'astreinte."
        // `generateReport` refait cette fusion avant d'appeler le service ;
        // `{{transcript}}` lit `mergedTranscript` faute de segments.
        r.mergedTranscript = r.rawTranscript
        ctx.insert(r)
        if avecParticipant {
            let c = Collaborator(name: "Marc JACQUIER")
            ctx.insert(c)
            r.participants.append(c)
        }
        try ctx.save()
        return r
    }

    // MARK: - Le gabarit 1:1 est bien celui qui sert

    @Test("Le gabarit intégré d'une 1:1 est semé et porte le bon type")
    func gabaritParDefaut() throws {
        let ctx = try contexte()
        let gabarits = try ctx.fetch(FetchDescriptor<ReportTemplate>())
            .filter { $0.isBuiltIn && $0.kind == .oneToOne && !$0.isArchived }
        #expect(!gabarits.isEmpty,
                "Sans gabarit 1:1 intégré, le prompt part sans aucune consigne d'entretien")
    }

    // MARK: - Sans fil, sans participant

    @Test("Sans fil ni participant, les engagements sont vides et rien ne lève")
    func engagementsVidesSansFil() throws {
        let ctx = try contexte()
        let r = try reunion(in: ctx, avecParticipant: false)

        let entrees = ReportOptionalBlocks.commitments(of: r, in: ctx, audience: .collaborator)
        #expect(entrees.isEmpty)
        #expect(ReportOptionalBlocks.commitmentsMarkdown(entrees).isEmpty)
        // Le fil n'est pas créé au passage : la génération d'un rapport ne doit
        // rien écrire en base.
        #expect(OneOnOneThreadStore.thread(for: r, in: ctx) == nil)
    }

    @Test("Le prompt d'une 1:1 sans fil ni participant s'assemble et reste exploitable")
    func promptSansFilNiParticipant() throws {
        let ctx = try contexte()
        let r = try reunion(in: ctx, avecParticipant: false)

        let prompt = AIReportService.assembleTemplatePrompt(meeting: r, in: ctx)
        #expect(!prompt.isEmpty)
        #expect(prompt.contains("grille d'astreinte"), "La transcription doit être dans le prompt")
        #expect(!prompt.contains("{{"), "Aucun placeholder ne doit partir non résolu : \(prompt.prefix(400))")
    }

    @Test("Le prompt d'une 1:1 avec participant mais sans fil nomme la personne")
    func promptAvecParticipantSansFil() throws {
        let ctx = try contexte()
        let r = try reunion(in: ctx, avecParticipant: true)

        let prompt = AIReportService.assembleTemplatePrompt(meeting: r, in: ctx)
        #expect(prompt.contains("Marc JACQUIER"))
        #expect(!prompt.contains("{{"))
    }

    @Test("Le prompt tient aussi sans transcription — le flux transcrit d'abord")
    func promptSansTranscription() throws {
        let ctx = try contexte()
        let r = try reunion(in: ctx, avecParticipant: true)
        r.rawTranscript = ""
        r.mergedTranscript = ""
        try ctx.save()

        let prompt = AIReportService.assembleTemplatePrompt(meeting: r, in: ctx)
        #expect(!prompt.isEmpty)
        #expect(!prompt.contains("{{"))
    }

    // MARK: - L'erreur du modèle reste lisible

    /// Le second temps du bouton passe par `AIClient`. Quand l'endpoint n'est
    /// pas joignable, l'alerte affiche `error.localizedDescription` : la
    /// vérification porte donc sur les erreurs que ce chemin peut produire.
    @Test("Les erreurs de l'endpoint IA portent un message en français")
    func erreursEndpointLisibles() async {
        struct ClientEnPanne: AIClientProtocol {
            func send(prompt: String, settings: AppSettings) async throws -> String {
                throw AIEndpointError.missingModel
            }
        }
        let reglages = AppSettings()
        do {
            _ = try await ClientEnPanne().send(prompt: "peu importe", settings: reglages)
            Issue.record("Le double doit lever")
        } catch {
            let message = error.localizedDescription
            #expect(!message.isEmpty)
            #expect(!message.lowercased().contains("operation"),
                    "Message opaque remonté à l'utilisateur : \(message)")
        }
    }
}
