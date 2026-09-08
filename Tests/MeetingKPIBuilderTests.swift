import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le bandeau de quatre indicateurs (spec §2.3). Le calcul est extrait de la
/// vue : c'est lui qui doit être juste, et c'est lui qui est vérifiable.
///
/// Les chiffres de référence sont ceux de la capture `1a-cockpit.png` :
/// PRÉSENCE 100 % 6/6, ACTIONS 12 · 9 non assignées, DÉCISIONS 3 · dont 1
/// budget, RISQUES 5 · 2 critiques.
@Suite("Bandeau d'indicateurs — calcul")
@MainActor
struct MeetingKPIBuilderTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("Les initiales sont celles de la capture : PY, NL, LD")
    func initials() {
        // La capture montre `PY` en première pastille : sur un prénom
        // composé, le tiret est un séparateur de mots — les deux initiales
        // viennent du prénom, pas du nom de famille.
        #expect(MeetingKPIBuilder.initials("Pierre-Yves Nallet") == "PY")
        #expect(MeetingKPIBuilder.initials("Nathalie Lefèvre") == "NL")
        #expect(MeetingKPIBuilder.initials("Laurent Deberti") == "LD")
        // Un prénom seul donne ses deux premières lettres, pas une seule :
        // une pastille d'une lettre est illisible à 19 px.
        #expect(MeetingKPIBuilder.initials("Laurent") == "LA")
        // Prénom composé : les deux initiales du composé, pas celles du nom.
        #expect(MeetingKPIBuilder.initials("Pierre-Yves") == "PY")
        #expect(MeetingKPIBuilder.initials("") == "?")
        #expect(MeetingKPIBuilder.initials("   ") == "?")
    }

    @Test("Six présents sur six font 100 % et six pastilles")
    func presence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        for nom in ["Pierre-Yves Nallet", "Nathalie Lefèvre", "Cédric Payet",
                    "Lucas Sylvain", "Camille Aubert", "Laurent Deberti"] {
            let c = Collaborator(name: nom, role: "Architecte")
            context.insert(c)
            reunion.participants.append(c)
            reunion.setParticipantStatus(.present, for: c)
        }
        let presence = MeetingKPIBuilder.build(meeting: reunion).presence
        #expect(presence.total == 6)
        #expect(presence.present == 6)
        #expect(presence.percent == 100)
        // Ordre par nom : Camille Aubert, Cédric Payet, Laurent Deberti,
        // Lucas Sylvain, Nathalie Lefèvre, Pierre-Yves Nallet. La capture ne
        // fixe pas d'ordre significatif ; SwiftData n'en garantit aucun pour
        // une relation « à plusieurs », d'où ce tri stable.
        #expect(presence.initials == ["CA", "CP", "LD", "LS", "NL", "PY"])
    }

    @Test("Un refus fait tomber le pourcentage sans changer le total")
    func presenceWithRefusal() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let a = Collaborator(name: "Anne Berger", role: "")
        let b = Collaborator(name: "Bruno Colin", role: "")
        context.insert(a); context.insert(b)
        reunion.participants = [a, b]
        reunion.setParticipantStatus(.present, for: a)
        reunion.setParticipantStatus(.refused, for: b)
        let presence = MeetingKPIBuilder.build(meeting: reunion).presence
        #expect(presence.total == 2)
        #expect(presence.present == 1)
        #expect(presence.percent == 50)
    }

    @Test("Actions : total, non assignées, part faite")
    func actions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let porteur = Collaborator(name: "Sylvain Roche", role: "")
        context.insert(porteur)

        let a = ActionTask(title: "Vérifier l'état des comptes GitLab")
        let b = ActionTask(title: "Clarifier la situation de facturation")
        let c = ActionTask(title: "Chiffrer la fin de migration")
        let d = ActionTask(title: "Reprendre le cadrage réseau")
        c.collaborator = porteur
        b.isCompleted = true
        d.status = .dropped
        for t in [a, b, c, d] { context.insert(t); t.meeting = reunion }

        let k = MeetingKPIBuilder.build(meeting: reunion).actions
        // `d` est abandonnée : elle a quitté le tableau, le rail et le
        // portefeuille (cf. `MeetingActionCounts`).
        #expect(k.total == 3)
        // Seule `a` est **ouverte** sans responsable. `b` est faite : une
        // action close ne porte plus de dette d'assignation, et l'annoncer en
        // rouge au-dessus d'un tableau qui ne la montre plus est le défaut du
        // 8 septembre 2026.
        #expect(k.unassigned == 1)
        #expect(k.done == 1)
        #expect(abs(k.doneFraction - 1.0 / 3.0) < 0.0001)
    }

    @Test("Un nom de responsable non résolu compte comme assigné")
    func unresolvedAssigneeCountsAsAssigned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        // `unresolvedAssigneeName` est renseigné quand le rapport nomme
        // quelqu'un que la base ne connaît pas : l'action **a** un porteur,
        // elle n'est pas « à assigner ».
        let t = ActionTask(title: "Relancer Alexis pour l'estimation")
        t.unresolvedAssigneeName = "Alexis"
        context.insert(t); t.meeting = reunion
        #expect(MeetingKPIBuilder.build(meeting: reunion).actions.unassigned == 0)

        let vide = ActionTask(title: "Sans porteur")
        vide.unresolvedAssigneeName = "   "      // blanc = pas un porteur
        context.insert(vide); vide.meeting = reunion
        #expect(MeetingKPIBuilder.build(meeting: reunion).actions.unassigned == 1)
    }

    @Test("Décisions : compte, première en clair, mention budget")
    func decisions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        reunion.decisions = [
            "Le partenaire finalise lui-même la migration (Olivier Freund)",
            "Budget révisé à 40k sur le reste à faire",
            "Formation Admin planifiée en octobre"
        ]
        let k = MeetingKPIBuilder.build(meeting: reunion).decisions
        #expect(k.count == 3)
        #expect(k.first == "Le partenaire finalise lui-même la migration (Olivier Freund)")
        #expect(k.budgetCount == 1)
    }

    @Test("« budget » est reconnu sans casse ni accent")
    func budgetDetection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        reunion.decisions = ["BUDGET gelé", "Rebudgétisation du lot 2", "Rien à voir"]
        #expect(MeetingKPIBuilder.build(meeting: reunion).decisions.budgetCount == 2)
    }

    @Test("Risques : niveaux du plus grave, surplus au-delà de huit points")
    func risks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        for (titre, gravite) in [("1", "Critique"), ("2", "Critique"), ("3", "Modéré"),
                                 ("4", "Faible"), ("5", "Élevé")] {
            let a = ProjectAlert(title: titre, severity: gravite)
            context.insert(a); a.meeting = reunion
        }
        let k = MeetingKPIBuilder.build(meeting: reunion).risks
        #expect(k.count == 5)
        #expect(k.criticalCount == 2)
        #expect(k.levels == [.critique, .critique, .eleve, .modere, .faible])
        #expect(k.overflow == 0)

        for i in 6...12 {
            let a = ProjectAlert(title: "\(i)", severity: "Faible")
            context.insert(a); a.meeting = reunion
        }
        let gros = MeetingKPIBuilder.build(meeting: reunion).risks
        #expect(gros.count == 12)
        #expect(gros.levels.count == MeetingKPIBuilder.maxRiskDots)
        #expect(gros.overflow == 12 - MeetingKPIBuilder.maxRiskDots)
    }

    @Test("Un risque résolu ne compte plus")
    func resolvedRiskIsExcluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let ouvert = ProjectAlert(title: "ouvert", severity: "Critique")
        let ferme = ProjectAlert(title: "fermé", severity: "Critique")
        ferme.isResolved = true
        for a in [ouvert, ferme] { context.insert(a); a.meeting = reunion }
        let k = MeetingKPIBuilder.build(meeting: reunion).risks
        #expect(k.count == 1)
        #expect(k.criticalCount == 1)
    }

    @Test("Une gravité inconnue retombe sur « modéré » plutôt que de disparaître")
    func unknownSeverity() {
        #expect(MeetingKPIBuilder.level(fromSeverity: "Critique") == .critique)
        #expect(MeetingKPIBuilder.level(fromSeverity: "Élevé") == .eleve)
        #expect(MeetingKPIBuilder.level(fromSeverity: "Eleve") == .eleve)
        #expect(MeetingKPIBuilder.level(fromSeverity: "Modéré") == .modere)
        #expect(MeetingKPIBuilder.level(fromSeverity: "Faible") == .faible)
        #expect(MeetingKPIBuilder.level(fromSeverity: "n'importe quoi") == .modere)
    }

    @Test("Une réunion vide rend des compteurs à zéro, pas un état invalide")
    func emptyMeeting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "Vide", date: .now)
        context.insert(reunion)
        let k = MeetingKPIBuilder.build(meeting: reunion)
        #expect(k.presence.total == 0 && k.presence.percent == 0 && k.presence.initials.isEmpty)
        #expect(k.actions.total == 0 && k.actions.doneFraction == 0)
        #expect(k.decisions.count == 0 && k.decisions.first == nil)
        #expect(k.risks.count == 0 && k.risks.levels.isEmpty && k.risks.overflow == 0)
    }
}
