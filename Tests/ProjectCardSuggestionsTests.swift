import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Client factice : aucun test de ce lot ne touche le réseau, MLX ou une
/// session graphique (programme §8).
private struct StubAIClient: AIClientProtocol {
    let response: String
    let throwError: Bool
    /// Vrai dès qu'une requête a été envoyée : sert à prouver qu'un endpoint
    /// non configuré n'appelle rien.
    final class Journal: @unchecked Sendable { var appels = 0 }
    let journal = Journal()

    init(_ response: String, throwError: Bool = false) {
        self.response = response
        self.throwError = throwError
    }

    func send(prompt: String, settings: AppSettings) async throws -> String {
        journal.appels += 1
        if throwError {
            throw NSError(domain: "stub", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "stub"])
        }
        return response
    }
}

@Suite("Fiche projet — suggestions de l'assistant")
@MainActor
struct ProjectCardSuggestionsTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    /// Réglages avec un endpoint utilisable : sans modèle choisi, le service
    /// ne demande rien.
    private func makeSettings() -> AppSettings {
        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        return reglages
    }

    private let reponseValide = """
    {"updates":[
      {"field":"budgetSpent","label":"Budget consommé","current":"40 000 €",
       "proposed":"48 000 €","evidence":"15:20 40k engagés, rien de finalisé"},
      {"field":"milestoneState","label":"jalon Marine","current":"en cours",
       "proposed":"bloqué","evidence":"11:03 le partenaire finalise lui-même"}
    ]}
    """

    // MARK: - Parsing

    @Test("Une réponse valide donne une proposition par entrée")
    func parsesValidResponse() {
        let updates = ProjectCardSuggestions.parse(reponseValide)
        #expect(updates.count == 2)
        #expect(updates[0].field == .budgetSpent)
        #expect(updates[0].current == "40 000 €")
        #expect(updates[0].proposed == "48 000 €")
        #expect(updates[0].evidence == "15:20 40k engagés, rien de finalisé")
        #expect(updates[1].field == .milestoneState)
        #expect(updates[1].label == "jalon Marine")
    }

    /// Les modèles enrobent volontiers leur JSON dans un bloc markdown, même
    /// quand on le leur interdit. `AIReportService` a la même tolérance.
    @Test("Un bloc ```json est retiré avant l'analyse")
    func stripsCodeFence() {
        let enrobe = "```json\n\(reponseValide)\n```"
        #expect(ProjectCardSuggestions.parse(enrobe).count == 2)
    }

    @Test("Une liste vide ne propose rien, sans erreur")
    func emptyUpdates() {
        #expect(ProjectCardSuggestions.parse(#"{"updates":[]}"#).isEmpty)
        #expect(ProjectCardSuggestions.parse("{}").isEmpty)
    }

    /// Une réponse inexploitable ne doit **jamais** lever : l'encart de
    /// suggestions disparaît, et c'est tout. Une exception ferait remonter une
    /// erreur technique dans une réunion en cours.
    @Test("Un JSON malformé ne propose rien et ne lève pas")
    func malformedResponse() {
        #expect(ProjectCardSuggestions.parse("").isEmpty)
        #expect(ProjectCardSuggestions.parse("désolé, je ne peux pas").isEmpty)
        #expect(ProjectCardSuggestions.parse(#"{"updates":[{"field":}]}"#).isEmpty)
        #expect(ProjectCardSuggestions.parse("[1,2,3]").isEmpty)
    }

    @Test("Un champ inconnu est écarté, les autres sont conservés")
    func unknownFieldIsDropped() {
        let melange = """
        {"updates":[
          {"field":"phaseDuProjet","label":"x","current":"a","proposed":"b","evidence":"—"},
          {"field":"status","label":"Statut du projet","current":"À surveiller",
           "proposed":"En risque","evidence":"07:48 timing à définir"}
        ]}
        """
        let updates = ProjectCardSuggestions.parse(melange)
        #expect(updates.count == 1)
        #expect(updates[0].field == .status)
    }

    @Test("Une proposition sans valeur proposée est écartée")
    func emptyProposalIsDropped() {
        let vide = """
        {"updates":[{"field":"risk","label":"","current":"","proposed":"  ","evidence":""}]}
        """
        #expect(ProjectCardSuggestions.parse(vide).isEmpty)
    }

    @Test("Une réponse bavarde est tronquée à la limite")
    func tooManyUpdatesAreTruncated() {
        let lignes = (0..<20).map { index in
            """
            {"field":"risk","label":"r\(index)","current":"a","proposed":"b\(index)","evidence":"—"}
            """
        }
        let bavard = "{\"updates\":[\(lignes.joined(separator: ","))]}"
        #expect(ProjectCardSuggestions.parse(bavard).count == ProjectCardSuggestions.maxUpdates)
    }

    @Test("Chaque proposition a une identité distincte pour la feuille de diff")
    func updatesHaveDistinctIdentities() {
        let updates = ProjectCardSuggestions.parse(reponseValide)
        #expect(Set(updates.map(\.id)).count == updates.count)
    }

    // MARK: - Endpoint

    @Test("Sans modèle choisi, l'endpoint n'est pas configuré")
    func endpointNotConfiguredWithoutModel() {
        let vierge = AppSettings()
        vierge.modelName = ""
        #expect(ProjectCardSuggestions.isEndpointConfigured(vierge) == false)
        #expect(ProjectCardSuggestions.isEndpointConfigured(makeSettings()))
    }

    /// Sans endpoint : pas d'encart, **pas d'erreur**, et surtout aucun appel.
    @Test("Sans endpoint configuré, rien n'est demandé et rien n'est proposé")
    func noEndpointMeansNoCall() async throws {
        let context = ModelContext(try makeContainer())
        let (reunion, projet) = seedMeeting(context)
        let client = StubAIClient(reponseValide)
        let vierge = AppSettings()
        vierge.modelName = ""

        let updates = await ProjectCardSuggestions.suggest(
            meeting: reunion,
            card: ProjectCardBuilder.build(project: projet, meetings: [reunion]),
            settings: vierge,
            client: client
        )
        #expect(updates.isEmpty)
        #expect(client.journal.appels == 0)
    }

    @Test("Un client qui échoue ne propose rien et ne lève pas")
    func failingClientIsSilent() async throws {
        let context = ModelContext(try makeContainer())
        let (reunion, projet) = seedMeeting(context)
        let updates = await ProjectCardSuggestions.suggest(
            meeting: reunion,
            card: ProjectCardBuilder.build(project: projet, meetings: [reunion]),
            settings: makeSettings(),
            client: StubAIClient("", throwError: true)
        )
        #expect(updates.isEmpty)
    }

    /// Sans notes ni décisions, il n'y a rien à déduire : on n'interroge pas
    /// le modèle pour lui faire inventer des mises à jour.
    @Test("Une réunion sans matière ne déclenche aucun appel")
    func emptyMeetingMeansNoCall() async throws {
        let context = ModelContext(try makeContainer())
        let reunion = Meeting(title: "Vide", date: Date(), notes: "")
        context.insert(reunion)
        let projet = Project(code: "P1", name: "P", domain: "d", phase: "p")
        context.insert(projet)
        reunion.project = projet

        let client = StubAIClient(reponseValide)
        let updates = await ProjectCardSuggestions.suggest(
            meeting: reunion,
            card: ProjectCardBuilder.build(project: projet, meetings: [reunion]),
            settings: makeSettings(),
            client: client
        )
        #expect(updates.isEmpty)
        #expect(client.journal.appels == 0)
    }

    // MARK: - Critère chantier 3 n° 4, versant assistant

    /// **Le test du critère.** L'assistant propose, l'utilisateur dispose : ni
    /// `suggest` ni `accept` ne touchent `Project`. Seul le brouillon change,
    /// et il faudra encore `Enregistrer` pour que le store bouge.
    @Test("Ni suggérer ni accepter n'écrit dans le modèle")
    func suggestingAndAcceptingNeverWriteToTheModel() async throws {
        let context = ModelContext(try makeContainer())
        let (reunion, projet) = seedMeeting(context)
        let carte = ProjectCardBuilder.build(project: projet, meetings: [reunion])

        let updates = await ProjectCardSuggestions.suggest(
            meeting: reunion,
            card: carte,
            settings: makeSettings(),
            client: StubAIClient(reponseValide)
        )
        #expect(updates.count == 2)

        // Après la suggestion : le projet est intact.
        #expect(projet.budgetCons == 40_000)
        #expect(projet.status == "Yellow")

        // Après l'acceptation : le brouillon change, le projet non.
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let accepte = ProjectCardSuggestions.accept(updates[0], in: &brouillon)
        #expect(accepte)
        #expect(brouillon.budgetSpent == 48_000)
        #expect(projet.budgetCons == 40_000)
        #expect(try context.fetch(FetchDescriptor<Project>()).first?.budgetCons == 40_000)
    }

    @Test("Accepter un statut réécrit le brouillon, pas le projet")
    func acceptingStatusUpdatesDraftOnly() throws {
        let context = ModelContext(try makeContainer())
        let (_, projet) = seedMeeting(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let proposition = ProjectCardUpdate(field: .status,
                                            label: "Statut du projet",
                                            current: "À surveiller",
                                            proposed: "En risque",
                                            evidence: "07:48")
        #expect(ProjectCardSuggestions.accept(proposition, in: &brouillon))
        #expect(brouillon.status == .risk)
        #expect(projet.status == "Yellow")
    }

    @Test("Accepter un jalon marque le jalon nommé comme bloqué")
    func acceptingMilestoneStateMarksTheNamedMilestone() throws {
        let context = ModelContext(try makeContainer())
        let (_, projet) = seedMeeting(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let proposition = ProjectCardUpdate(field: .milestoneState,
                                            label: "jalon Marine",
                                            current: "en cours",
                                            proposed: "bloqué",
                                            evidence: "11:03")
        #expect(ProjectCardSuggestions.accept(proposition, in: &brouillon))
        let marine = try #require(brouillon.milestones.first { $0.label.contains("Marine") })
        #expect(marine.state == .late)
        #expect(projet.milestones.first { $0.label.contains("Marine") }?.state == .planned)
    }

    @Test("Accepter un risque ajoute une ligne au brouillon")
    func acceptingRiskAddsADraftRow() throws {
        let context = ModelContext(try makeContainer())
        let (_, projet) = seedMeeting(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let avant = brouillon.risks.count
        let proposition = ProjectCardUpdate(field: .risk,
                                            label: "Chiffrage non validé",
                                            current: "—",
                                            proposed: "Chiffrage du reste à faire non validé",
                                            evidence: "15:20")
        #expect(ProjectCardSuggestions.accept(proposition, in: &brouillon))
        #expect(brouillon.risks.count == avant + 1)
        #expect(brouillon.risks.last?.existing == nil)
        #expect(projet.alerts.count == 1)
    }

    /// Une proposition inapplicable — un jalon qui n'existe pas, un montant
    /// illisible — est refusée plutôt que devinée : `accept` rend `false` et
    /// l'interface garde la ligne pour que l'utilisateur tranche à la main.
    @Test("Une proposition inapplicable est refusée, pas devinée")
    func inapplicableUpdateIsRefused() throws {
        let context = ModelContext(try makeContainer())
        let (_, projet) = seedMeeting(context)
        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let temoin = brouillon

        let jalonInconnu = ProjectCardUpdate(field: .milestoneState, label: "jalon Fantôme",
                                             current: "", proposed: "bloqué", evidence: "")
        #expect(ProjectCardSuggestions.accept(jalonInconnu, in: &brouillon) == false)

        let montantIllisible = ProjectCardUpdate(field: .budgetSpent, label: "Budget consommé",
                                                 current: "40 000 €", proposed: "beaucoup plus",
                                                 evidence: "")
        #expect(ProjectCardSuggestions.accept(montantIllisible, in: &brouillon) == false)
        #expect(brouillon == temoin)
    }

    // MARK: - Encart

    @Test("L'encart énumère les mises à jour comme sur la capture")
    func summaryMatchesCapture() {
        let updates = ProjectCardSuggestions.parse(reponseValide)
        #expect(ProjectCardSuggestions.summary(updates)
                == "L'assistant propose 2 mises à jour depuis cette séance : "
                 + "Budget consommé et jalon Marine.")
    }

    @Test("Une seule mise à jour se dit au singulier")
    func summarySingular() {
        let une = [ProjectCardUpdate(field: .status, label: "Statut du projet",
                                     current: "a", proposed: "b", evidence: "")]
        #expect(ProjectCardSuggestions.summary(une)
                == "L'assistant propose 1 mise à jour depuis cette séance : Statut du projet.")
    }

    @Test("Sans proposition, il n'y a pas d'encart")
    func summaryIsEmptyWithoutUpdates() {
        #expect(ProjectCardSuggestions.summary([]).isEmpty)
    }

    // MARK: - Source

    /// Les notes et décisions **de la séance**, pas la transcription entière :
    /// la spec §4.3 parle des mises à jour « déduites de la séance ».
    @Test("La source réunit les notes horodatées, les notes libres et les décisions")
    func sourceTextGathersNotesAndDecisions() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, _) = seedMeeting(context)
        let source = ProjectCardSuggestions.sourceText(meeting: reunion)
        #expect(source.contains("40k engagés"))
        #expect(source.contains("Le partenaire finalise"))
    }

    @Test("La source est tronquée pour ne pas faire exploser le prompt")
    func sourceTextIsTruncated() throws {
        let context = ModelContext(try makeContainer())
        let reunion = Meeting(title: "Longue", date: Date(), notes: "")
        reunion.liveNotes = String(repeating: "a", count: 20_000)
        context.insert(reunion)
        #expect(ProjectCardSuggestions.sourceText(meeting: reunion).count
                <= ProjectCardSuggestions.maxSourceCharacters)
    }

    /// Le prompt doit contenir l'état courant, sinon le modèle propose des
    /// « mises à jour » identiques à ce qui est déjà écrit.
    @Test("Le prompt rappelle l'état courant et impose le schéma")
    func promptCarriesCurrentState() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, projet) = seedMeeting(context)
        let carte = ProjectCardBuilder.build(project: projet, meetings: [reunion])
        let prompt = ProjectCardSuggestions.buildPrompt(source: "40k engagés", card: carte)

        #expect(prompt.contains("À surveiller"))
        #expect(prompt.contains("Migration Marine"))
        #expect(prompt.contains("budgetSpent"))
        #expect(prompt.contains("milestoneState"))
        #expect(prompt.contains("evidence"))
        #expect(prompt.contains("40k engagés"))
    }

    // MARK: - Fixture

    /// La réunion et le projet de la capture 3b, réduits à ce que les tests
    /// exigent.
    private func seedMeeting(_ context: ModelContext) -> (Meeting, Project) {
        let projet = Project(code: "P25_110",
                             name: "S/D — Modernisation CI/CD",
                             domain: "S/D",
                             phase: "Réalisation",
                             status: "Yellow")
        projet.budgetCons = 40_000
        projet.budgetInit = 61_000
        context.insert(projet)

        let jalon = ProjectMilestone(label: "Migration Marine — chiffrage à valider",
                                     state: .planned, order: 0)
        context.insert(jalon)
        jalon.project = projet

        let alerte = ProjectAlert(title: "Corruption base de données", severity: "Critique")
        context.insert(alerte)
        alerte.project = projet

        let reunion = Meeting(title: "[P25_110] Partage statut final", date: Date(), notes: "")
        reunion.liveNotes = "**15:20** 40k engagés, rien de finalisé."
        reunion.decisions = ["Le partenaire finalise lui-même la migration"]
        context.insert(reunion)
        reunion.project = projet

        try? context.save()
        return (reunion, projet)
    }
}
