import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les règles d'édition rapide d'une carte d'action (spec §2.5) : « Une pilule
/// vide est une **invite** en `accent/action` (`＋ assigner`, `＋ échéance`) ;
/// renseignée elle passe en `accent/ok` ou neutre. Un clic ouvre un sélecteur
/// inline (pas de modale) ; `Tab` passe au champ suivant. »
///
/// Ce qui est testable ici, c'est ce qui décide de l'apparence et du parcours
/// clavier — pas le rendu. Le critère d'acceptation n° 3 du chantier 1
/// (« assigner responsable + échéance sans quitter le rail ni ouvrir de
/// modale ») a sa propre garde dans `ActionsRailNoModalTests`.
@Suite("Édition rapide d'une carte d'action")
@MainActor
struct ActionCardEditingTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func date(_ jour: Int, _ mois: Int, _ annee: Int) -> Date {
        calendrier.date(from: DateComponents(year: annee, month: mois, day: jour, hour: 10)) ?? .now
    }

    @Test("La charge se lit 30min, 1h30, 2h, 1j — jamais en minutes brutes")
    func chargeLabel() {
        #expect(ActionCardEditing.chargeLabel(30) == "30min")
        #expect(ActionCardEditing.chargeLabel(45) == "45min")
        #expect(ActionCardEditing.chargeLabel(60) == "1h")
        #expect(ActionCardEditing.chargeLabel(90) == "1h30")
        #expect(ActionCardEditing.chargeLabel(120) == "2h")
        // Une journée = 8 h de travail, pas 24 : la capture affiche « 1j »
        // pour la charge de « Chiffrer la fin de migration Marine ».
        #expect(ActionCardEditing.chargeLabel(480) == "1j")
        #expect(ActionCardEditing.chargeLabel(960) == "2j")
        // 10 h n'est pas un multiple de la journée : elle reste en heures.
        #expect(ActionCardEditing.chargeLabel(600) == "10h")
        #expect(ActionCardEditing.chargeLabel(0) == "")
        #expect(ActionCardEditing.chargeLabel(-30) == "")
    }

    @Test("Les charges proposées vont de la demi-heure à la journée")
    func chargesProposees() {
        #expect(ActionCardEditing.chargesProposees == [30, 60, 120, 240, 480])
        #expect(ActionCardEditing.chargesProposees.map(ActionCardEditing.chargeLabel)
                == ["30min", "1h", "2h", "4h", "1j"])
    }

    @Test("Tab fait le tour des trois champs et revient au premier")
    func tabCyclesThroughFields() {
        #expect(ActionCardEditing.suivant(.responsable) == .echeance)
        #expect(ActionCardEditing.suivant(.echeance) == .charge)
        #expect(ActionCardEditing.suivant(.charge) == .responsable)
        #expect(ActionCardEditing.Champ.allCases.count == 3)
    }

    @Test("Depuis un mercredi : Demain jeudi, Vendredi le 2, +1 sem. le 9")
    func shortcutsFromWednesday() {
        // 2 septembre 2026 est un mercredi.
        let raccourcis = ActionCardEditing.raccourcisEcheance(depuis: date(2, 9, 2026),
                                                              calendar: calendrier)
        #expect(raccourcis.map(\.libelle) == ["Demain", "Vendredi", "+1 sem."])
        #expect(calendrier.isDate(raccourcis[0].date, inSameDayAs: date(3, 9, 2026)))
        #expect(calendrier.isDate(raccourcis[1].date, inSameDayAs: date(4, 9, 2026)))
        #expect(calendrier.isDate(raccourcis[2].date, inSameDayAs: date(9, 9, 2026)))
    }

    @Test("Un vendredi, « Vendredi » désigne le vendredi suivant, jamais aujourd'hui")
    func fridayNeverMeansToday() {
        // 4 septembre 2026 est un vendredi.
        let raccourcis = ActionCardEditing.raccourcisEcheance(depuis: date(4, 9, 2026),
                                                              calendar: calendrier)
        // Une échéance « Vendredi » posée un vendredi et qui tombe le jour même
        // serait une échéance déjà passée à l'heure où on la pose.
        #expect(calendrier.isDate(raccourcis[1].date, inSameDayAs: date(11, 9, 2026)))
    }

    @Test("L'état de la pilule de responsable suit ce qui est renseigné")
    func ownerPillState() throws {
        let context = try makeContext()
        let sans = ActionTask(title: "Vérifier l'état des comptes GitLab")
        context.insert(sans)
        #expect(ActionCardEditing.etatResponsable(sans) == .invite)

        let porteur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(porteur)
        let avec = ActionTask(title: "Chiffrer la fin de migration Marine")
        avec.collaborator = porteur
        context.insert(avec)
        #expect(ActionCardEditing.etatResponsable(avec) == .renseignee)

        // Un nom que l'extraction n'a pas su relier : quelqu'un est nommé,
        // mais rien n'est confirmé — neutre, ni invite ni engagement.
        let flou = ActionTask(title: "Relancer Alexis pour l'estimation")
        flou.unresolvedAssigneeName = "Alexis"
        context.insert(flou)
        #expect(ActionCardEditing.etatResponsable(flou) == .neutre)
    }

    @Test("Le libellé du responsable montre la suggestion, puis le porteur")
    func ownerPillLabel() throws {
        let context = try makeContext()
        let yann = Collaborator(name: "Yann Ferré", role: "")
        context.insert(yann)
        let sans = ActionTask(title: "Vérifier l'état des comptes GitLab")
        context.insert(sans)

        #expect(ActionCardEditing.libelleResponsable(sans, suggestion: nil) == "＋ assigner")
        // La capture montre « ＋ Yann » : la suggestion s'affiche **dans**
        // l'invite, et un clic l'accepte.
        #expect(ActionCardEditing.libelleResponsable(sans, suggestion: yann) == "＋ Yann")

        sans.collaborator = yann
        // Renseignée, la pilule montre le prénom seul : 330 px ne tiennent pas
        // un nom complet à côté d'une échéance et d'une charge.
        #expect(ActionCardEditing.libelleResponsable(sans, suggestion: nil) == "Yann")
    }

    @Test("Une échéance de la semaine se nomme par son jour, au-delà par sa date")
    func dueDatePill() throws {
        let context = try makeContext()
        let t = ActionTask(title: "Clarifier la situation de facturation (40k)")
        context.insert(t)
        // Référence : mardi 8 septembre 2026.
        let reference = date(8, 9, 2026)
        #expect(ActionCardEditing.libelleEcheance(t, reference: reference,
                                                  calendar: calendrier) == "＋ échéance")

        t.dueDate = date(8, 9, 2026)
        #expect(ActionCardEditing.libelleEcheance(t, reference: reference,
                                                  calendar: calendrier) == "Aujourd'hui")
        t.dueDate = date(9, 9, 2026)
        #expect(ActionCardEditing.libelleEcheance(t, reference: reference,
                                                  calendar: calendrier) == "Demain")
        // La capture montre « Vendredi » : dans la semaine, on nomme le jour.
        t.dueDate = date(11, 9, 2026)
        #expect(ActionCardEditing.libelleEcheance(t, reference: reference,
                                                  calendar: calendrier) == "Vendredi")
        // Au-delà de six jours, la date reprend la main.
        t.dueDate = date(18, 9, 2026)
        #expect(ActionCardEditing.libelleEcheance(t, reference: reference,
                                                  calendar: calendrier) == "18 sept.")
        // Une échéance passée montre sa date : « Mardi » pour un mardi révolu
        // serait un piège.
        t.dueDate = date(1, 9, 2026)
        #expect(ActionCardEditing.libelleEcheance(t, reference: reference,
                                                  calendar: calendrier) == "1er sept.")
    }

    @Test("La pilule de source distingue une capture d'une phrase")
    func sourcePill() throws {
        let context = try makeContext()
        let t = ActionTask(title: "Vérifier l'état des comptes GitLab")
        context.insert(t)
        #expect(ActionCardEditing.libelleSource(t) == nil)

        t.sourceRef = SourceRef(kind: .transcript, stableID: UUID(), t: 252)
        #expect(ActionCardEditing.libelleSource(t) == "04:12 ↗")
        t.sourceRef = SourceRef(kind: .note, stableID: UUID(), t: 663)
        #expect(ActionCardEditing.libelleSource(t) == "11:03 ↗")
        t.sourceRef = SourceRef(kind: .capture, stableID: UUID(), t: 920)
        #expect(ActionCardEditing.libelleSource(t) == "◫ 15:20")
        // Une source sans instant ne peut replacer la lecture nulle part.
        t.sourceRef = SourceRef(kind: .capture, stableID: UUID(), t: nil)
        #expect(ActionCardEditing.libelleSource(t) == nil)
    }
}
