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
}
