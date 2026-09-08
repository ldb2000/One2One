import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les groupes du rail d'actions (spec §2.5) : « `À ASSIGNER` (barre gauche
/// `accent/report`) → `MES ACTIONS` → `REPORTÉES DU <date>` (compact, une ligne
/// par action) ».
///
/// Le calcul est extrait de la vue : c'est l'ordre des groupes, l'exclusion des
/// actions closes et le regroupement par date d'origine qui doivent être justes,
/// et rien de tout cela ne se vérifie dans un rendu.
@Suite("Groupes du rail d'actions")
@MainActor
struct ActionsRailGroupingTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Calendrier stable : les tests ne doivent pas dépendre du fuseau du poste.
    private var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func date(_ jour: Int, _ mois: Int, _ annee: Int) -> Date {
        calendrier.date(from: DateComponents(year: annee, month: mois, day: jour, hour: 9)) ?? .now
    }

    @Test("L'ordre des groupes est celui de la spec, les reportées en dernier")
    func groupOrder() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final", date: date(4, 9, 2026))
        let origine = Meeting(title: "COSUI hebdo", date: date(1, 9, 2026))
        context.insert(reunion); context.insert(origine)
        let porteur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(porteur)

        let aAssigner = ActionTask(title: "Vérifier l'état des comptes GitLab")
        aAssigner.destinataire = .collaborateur
        let mienne = ActionTask(title: "Chiffrer la fin de migration Marine")
        mienne.destinataire = .moi
        let deleguee = ActionTask(title: "Synchroniser les pipelines")
        deleguee.destinataire = .collaborateur
        deleguee.collaborator = porteur
        let reportee = ActionTask(title: "Préparer gitlab.rb et valider les flux")
        reportee.destinataire = .collaborateur
        reportee.carriedFromMeeting = origine
        reportee.deferralCount = 1
        for (index, t) in [aAssigner, mienne, deleguee, reportee].enumerated() {
            t.sortOrder = index
            context.insert(t)
            t.meeting = reunion
        }

        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks, calendar: calendrier)
        #expect(groupes.map(\.identite) == [.aAssigner, .mesActions, .deleguees,
                                            .reportees(origine.date)])
        #expect(groupes[0].libelle == "À assigner — 1")
        #expect(groupes[1].libelle == "Mes actions — 1")
        #expect(groupes[2].libelle == "Déléguées — 1")
        #expect(groupes[3].libelle == "Reportées du 1er sept. — 1")
        // Les reportées se rendent en lignes compactes, les autres en cartes.
        #expect(groupes[0].rendu == .cartes)
        #expect(groupes[3].rendu == .lignes)
    }

    @Test("Une action cochée quitte les groupes d'Actions")
    func doneIsHidden() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let ouverte = ActionTask(title: "Ouverte")
        ouverte.destinataire = .moi
        let close = ActionTask(title: "Close")
        close.destinataire = .moi
        close.isCompleted = true
        let abandonnee = ActionTask(title: "Abandonnée")
        abandonnee.destinataire = .moi
        abandonnee.status = .dropped
        for t in [ouverte, close, abandonnee] { context.insert(t); t.meeting = reunion }

        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks, calendar: calendrier)
        #expect(groupes.count == 1)
        #expect(groupes[0].actions.map(\.title) == ["Ouverte"])
    }

    @Test("Le report l'emporte sur « à assigner » : une action n'apparaît qu'une fois")
    func carriedWinsOverUnassigned() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: date(4, 9, 2026))
        let origine = Meeting(title: "COSUI hebdo", date: date(1, 9, 2026))
        context.insert(reunion); context.insert(origine)
        let t = ActionTask(title: "Relancer Alexis/Jeff pour l'estimation")
        t.destinataire = .collaborateur          // sans porteur : « à assigner »
        t.carriedFromMeeting = origine           // mais reportée
        context.insert(t); t.meeting = reunion

        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks, calendar: calendrier)
        #expect(groupes.count == 1)
        #expect(groupes[0].identite == .reportees(origine.date))
    }

    @Test("Deux réunions d'origine font deux groupes, du plus récent au plus ancien")
    func carriedGroupedByDate() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: date(4, 9, 2026))
        let sept = Meeting(title: "COSUI du 1er", date: date(1, 9, 2026))
        let aout = Meeting(title: "Gouvernance", date: date(31, 8, 2026))
        context.insert(reunion); context.insert(sept); context.insert(aout)
        for (titre, origine) in [("Récente", sept), ("Ancienne", aout)] {
            let t = ActionTask(title: titre)
            t.carriedFromMeeting = origine
            context.insert(t); t.meeting = reunion
        }
        // Une reportée sans réunion d'origine : `deferralCount` seul suffit.
        let orpheline = ActionTask(title: "Sans origine")
        orpheline.deferralCount = 2
        context.insert(orpheline); orpheline.meeting = reunion

        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks, calendar: calendrier)
        #expect(groupes.map(\.identite) == [.reportees(sept.date),
                                            .reportees(aout.date),
                                            .reportees(nil)])
        #expect(groupes[2].libelle == "Reportées — 1")
    }

    @Test("Le tri interne suit sortOrder : c'est lui qui met une action neuve en tête")
    func sortOrderFirst() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let ancienne = ActionTask(title: "Ancienne", dueDate: date(1, 9, 2026))
        ancienne.sortOrder = 0
        let neuve = ActionTask(title: "Neuve", dueDate: date(30, 9, 2026))
        neuve.sortOrder = -1                     // le plancher du composeur
        for t in [ancienne, neuve] { t.destinataire = .moi; context.insert(t); t.meeting = reunion }

        let groupes = ActionsRailGrouping.groupes(for: reunion.tasks, calendar: calendrier)
        #expect(groupes[0].actions.map(\.title) == ["Neuve", "Ancienne"])
    }

    @Test("Un nom de responsable non résolu compte comme un porteur")
    func unresolvedNameIsAnOwner() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: .now)
        context.insert(reunion)
        let t = ActionTask(title: "Relancer Alexis pour l'estimation")
        t.destinataire = .collaborateur
        t.unresolvedAssigneeName = "Alexis"
        context.insert(t); t.meeting = reunion
        // Même règle que `MeetingKPIBuilder` : sinon le rail et la carte
        // ACTIONS du bandeau afficheraient deux nombres différents.
        #expect(ActionsRailGrouping.groupes(for: reunion.tasks,
                                            calendar: calendrier)[0].identite == .deleguees)
    }

    @Test("La date d'un groupe de reportées porte l'ordinal du premier du mois")
    func ordinalDate() {
        #expect(ActionsRailGrouping.dateOrdinale(date(1, 9, 2026), calendar: calendrier) == "1er sept.")
        #expect(ActionsRailGrouping.dateOrdinale(date(11, 9, 2026), calendar: calendrier) == "11 sept.")
        #expect(ActionsRailGrouping.dateOrdinale(date(31, 8, 2026), calendar: calendrier) == "31 août")
    }

    @Test("L'historique liste les closes et les reportées, avec leur date")
    func historique() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL", date: date(4, 9, 2026))
        let origine = Meeting(title: "COSUI hebdo", date: date(1, 9, 2026))
        context.insert(reunion); context.insert(origine)

        let close = ActionTask(title: "Close")
        close.isCompleted = true
        close.completedAt = date(4, 9, 2026)
        let abandonnee = ActionTask(title: "Abandonnée")
        abandonnee.status = .dropped
        let reportee = ActionTask(title: "Reportée")
        reportee.carriedFromMeeting = origine
        let ouverte = ActionTask(title: "Ouverte")
        ouverte.destinataire = .moi
        for t in [close, abandonnee, reportee, ouverte] { context.insert(t); t.meeting = reunion }

        let entrees = ActionsRailGrouping.historique(for: reunion.tasks)
        #expect(entrees.map(\.titre).sorted() == ["Abandonnée", "Close", "Reportée"])
        let closeEntree = try #require(entrees.first { $0.titre == "Close" })
        #expect(closeEntree.motif == .close)
        #expect(closeEntree.date == date(4, 9, 2026))
        let reporteeEntree = try #require(entrees.first { $0.titre == "Reportée" })
        #expect(reporteeEntree.motif == .reportee)
        #expect(reporteeEntree.date == origine.date)
    }
}
