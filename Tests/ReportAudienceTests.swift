import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'audience d'un rapport se déduit du **gabarit choisi**, pas du seul type de
/// réunion : générer une note d'escalade depuis un 1:1 doit emporter les lignes
/// escaladées et laisser celles qui n'étaient que partagées.
@Suite("Audience du rapport — une par catégorie de gabarit")
struct ReportAudienceTests {

    @Test("La table catégorie → audience est exhaustive et sans surprise")
    func tableExhaustive() {
        let attendu: [ReportTemplateKind: Audience] = [
            .general: .projectTeam,
            .oneToOne: .collaborator,
            .manager: .manager,
            .copil: .projectTeam,
            .cosui: .projectTeam,
            .codir: .projectTeam,
            .preparation: .projectTeam,
            .restitution: .projectTeam,
            .workshop: .projectTeam,
            .metier: .projectTeam,
            .initiative: .projectTeam,
            .custom: .projectTeam,
            .escalade: .hr
        ]
        // Toute catégorie ajoutée sans décision d'audience fait tomber ce test.
        #expect(Set(attendu.keys) == Set(ReportTemplateKind.allCases))
        for (kind, audience) in attendu {
            #expect(kind.audience == audience, "\(kind.rawValue)")
        }
    }

    @Test("Sans gabarit, l'audience retombe sur le type de réunion")
    @MainActor
    func sansGabarit() {
        let reunion = Meeting(title: "1:1", date: Date())
        reunion.kind = .oneToOne
        #expect(ReportAudience.forTemplate(nil, meeting: reunion) == .collaborator)
        reunion.kind = .workshop
        #expect(ReportAudience.forTemplate(nil, meeting: reunion) == .projectTeam)
    }

    @Test("Le gabarit d'escalade parle aux RH, même sur un 1:1")
    @MainActor
    func gabaritEscalade() {
        let reunion = Meeting(title: "1:1", date: Date())
        reunion.kind = .oneToOne
        let gabarit = ReportTemplate(name: "Escalade", kind: .escalade)
        #expect(ReportAudience.forTemplate(gabarit, meeting: reunion) == .hr)
    }

    /// Bout en bout, par gabarit : le prompt et le HTML doivent tous deux
    /// dériver l'audience du gabarit. Avant le câblage, ce test échoue — les
    /// deux la déduisaient du `MeetingKind`, et une ligne `escalated` d'un 1:1
    /// était écartée jusque dans l'export Escalade.
    @Test("Une ligne escaladée sort dans l'export Escalade et nulle part ailleurs")
    @MainActor
    func ligneEscaladeeSeulementEnEscalade() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: cfg)
        let ctx = ModelContext(container)

        let personne = Collaborator(name: "Marine LEROY")
        ctx.insert(personne)
        let reunion = Meeting(title: "1:1 Marine", date: Date())
        reunion.kind = .oneToOne
        reunion.participants = [personne]
        reunion.summary = "## Sujets\n\nLa séance a porté sur la charge."
        ctx.insert(reunion)

        let privee = MeetingNote(t: 60, text: "DOUTE PERSONNEL", visibility: .private)
        privee.meeting = reunion
        let escaladee = MeetingNote(t: 120, text: "SIGNAL RH", visibility: .escalated)
        escaladee.meeting = reunion
        let partagee = MeetingNote(t: 180, text: "POINT PARTAGE", visibility: .shared)
        partagee.meeting = reunion
        ctx.insert(privee); ctx.insert(escaladee); ctx.insert(partagee)
        try ctx.save()

        let collab = ReportTemplate(name: "1:1 Collaborateur", kind: .oneToOne)
        let escalade = ReportTemplate(name: "Escalade", kind: .escalade)
        ctx.insert(collab); ctx.insert(escalade)
        try ctx.save()

        let htmlCollab = ReportHTMLBuilder.build(meeting: reunion, template: collab,
                                                 includeTranscript: false)
        #expect(!htmlCollab.contains("DOUTE PERSONNEL"))
        #expect(!htmlCollab.contains("SIGNAL RH"))
        #expect(htmlCollab.contains("POINT PARTAGE"))

        let htmlEscalade = ReportHTMLBuilder.build(meeting: reunion, template: escalade,
                                                   includeTranscript: false)
        #expect(!htmlEscalade.contains("DOUTE PERSONNEL"))
        #expect(htmlEscalade.contains("SIGNAL RH"))
        #expect(!htmlEscalade.contains("POINT PARTAGE"))

        let promptCollab = AIReportService.assembleTemplatePrompt(meeting: reunion, in: ctx,
                                                                  template: collab)
        #expect(!promptCollab.contains("DOUTE PERSONNEL"))
        #expect(!promptCollab.contains("SIGNAL RH"))
        let promptEscalade = AIReportService.assembleTemplatePrompt(meeting: reunion, in: ctx,
                                                                    template: escalade)
        #expect(!promptEscalade.contains("DOUTE PERSONNEL"))
        #expect(promptEscalade.contains("SIGNAL RH"))
    }
}
