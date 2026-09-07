import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les modèles de vue de l'écran de préparation 1:1 (capture 2b, spec §3.4).
///
/// Ils sont **purs** : c'est là que vivent les critères d'acceptation, parce
/// qu'une vue SwiftUI ne se teste pas et qu'un histogramme périmé ne se voit
/// pas à la relecture.
@Suite("Préparation 1:1 — modèles de vue (capture 2b, spec §3.4)")
@MainActor
struct ManagerPrepModelsTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }
    private static let jour: TimeInterval = 86_400

    private func semer() throws -> (fil: OneOnOneThread, context: ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let fils = RefonteDemoSeed.seedLot12(in: context)
        return (fils.manager, context)
    }

    private func filVide() throws -> (fil: OneOnOneThread,
                                      context: ModelContext,
                                      personne: Collaborator) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let personne = Collaborator(name: "Alice MARTIN", role: "Architecte")
        context.insert(personne)
        let fil = try #require(OneOnOneThreadStore.thread(for: personne, kind: .oneToOne,
                                                          in: context))
        return (fil, context, personne)
    }

    private func derniereSeance(_ fil: OneOnOneThread) throws -> Meeting {
        try #require(OneOnOneThreadStore.allMeetings(of: fil).last)
    }

    // MARK: - En-tête

    @Test("L'en-tête écrit « Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026 »")
    func enTeteDeLaCapture() throws {
        let (fil, _) = try semer()
        let seance = try derniereSeance(fil)
        let modele = PrepHeaderModel.build(meeting: seance, thread: fil)

        #expect(modele.name == "Laurent NOMINÉ")
        #expect(modele.initials == "LN")
        #expect(modele.sessionNumber == RefonteDemoSeed.managerThreadSessionCount)
        #expect(modele.subtitle == "Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026")
    }

    @Test("L'ordinal français distingue le premier des suivants")
    func ordinal() {
        #expect(PrepHeaderModel.ordinal(1) == "1ᵉʳ")
        #expect(PrepHeaderModel.ordinal(2) == "2ᵉ")
        #expect(PrepHeaderModel.ordinal(14) == "14ᵉ")
    }

    @Test("Un rôle « Néant » ne laisse pas de séparateur orphelin")
    func enTeteSansRole() throws {
        let (fil, context, personne) = try filVide()
        personne.role = CollaboratorIdentity.roleNeant
        let seance = Meeting(title: "1:1 Alice", date: Self.maintenant, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(personne)

        let modele = PrepHeaderModel.build(meeting: seance, thread: fil)
        #expect(modele.subtitle == "1ᵉʳ 1:1 · 4 sept. 2026")
        #expect(!modele.subtitle.hasPrefix(" · "))
    }

    // MARK: - Histogramme de moral (critère chantier 2 n° 3)

    @Test("L'histogramme rend les six barres et les dates de la capture")
    func histogrammeDeLaCapture() throws {
        let (fil, _) = try semer()
        let modele = MoodHistogramModel.build(fil, now: Self.maintenant)

        #expect(modele.bars.count == MoodTrend.historyLength)
        #expect(modele.bars.map(\.value) == RefonteDemoSeed.managerThreadMoods)
        #expect(modele.bars.map(\.dateLabel)
                == ["12/06", "26/06", "10/07", "24/07", "21/08", "04/09"])
        #expect(modele.bars.last?.isLast == true)
        #expect(modele.bars.dropLast().allSatisfy { !$0.isLast })
        #expect(modele.direction == .enBaisse)
        #expect(modele.trendLabel == "en baisse")
        #expect(modele.trendTone == .report)
        #expect(!modele.isEmpty)
    }

    @Test("La dernière barre prend la teinte de son cran")
    func teinteDesCrans() {
        #expect(MoodHistogramModel.tone(for: .difficile) == .report)
        #expect(MoodHistogramModel.tone(for: .sousTension) == .warn)
        // `Bien` est en `ok` et non en `oneOnOne` : la table du domaine est
        // celle du lot 11 (`OneOnOneMoodTone`) depuis l'intégration de la
        // vague 5, et c'est elle que colore aussi l'échelle de la séance.
        #expect(MoodHistogramModel.tone(for: .bien) == .ok)
        #expect(MoodHistogramModel.tone(for: .tresBien) == .ok)
        // Le jeu de la capture finit sur « Sous tension » : la dernière barre
        // est donc ambre, comme sur la maquette.
        #expect(MoodHistogramModel.tone(for: MoodLevel.clamped(
            RefonteDemoSeed.managerThreadMoods.last ?? 3)) == .warn)
    }

    /// **Critère d'acceptation du chantier 2, n° 3** : « le moral saisi en
    /// séance alimente immédiatement l'histogramme de préparation suivant. »
    @Test("Un moral saisi pour la séance courante apparaît aussitôt dans la série")
    func moralSaisiApparaitImmediatement() throws {
        let (fil, context, personne) = try filVide()
        var seances: [Meeting] = []
        for rang in 0..<3 {
            let seance = Meeting(title: "1:1 Alice \(rang)",
                                 date: Self.maintenant.addingTimeInterval(Double(rang - 2) * 14 * Self.jour),
                                 notes: "")
            seance.kind = .oneToOne
            context.insert(seance)
            seance.participants.append(personne)
            seances.append(seance)
        }
        for (rang, seance) in seances.enumerated() where rang < 2 {
            MoodTrend.record(4, for: seance, in: fil, in: context)
        }

        let avant = MoodHistogramModel.build(fil, now: Self.maintenant)
        #expect(avant.bars.count == 2)

        // La saisie de la séance courante, exactement comme la colonne
        // `① COMMENT ÇA VA` de la capture 2a l'écrit.
        MoodTrend.record(2, for: seances[2], in: fil, in: context)

        let apres = MoodHistogramModel.build(fil, now: Self.maintenant)
        #expect(apres.bars.count == 3)
        #expect(apres.bars.last?.value == 2)
        #expect(apres.bars.last?.isLast == true)
        #expect(apres.bars.last?.level == .sousTension)

        // Et une correction **remplace** la barre au lieu d'en ajouter une.
        MoodTrend.record(5, for: seances[2], in: fil, in: context)
        let corrige = MoodHistogramModel.build(fil, now: Self.maintenant)
        #expect(corrige.bars.count == 3)
        #expect(corrige.bars.last?.value == 5)
    }

    @Test("Un fil sans humeur affiche son invite, pas un cadre vide")
    func histogrammeVide() throws {
        let (fil, _, _) = try filVide()
        let modele = MoodHistogramModel.build(fil, now: Self.maintenant)
        #expect(modele.isEmpty)
        #expect(modele.trendLabel == nil)
        #expect(modele.explanation == nil)
    }

    // MARK: - Objectifs

    @Test("Les trois objectifs S2 sortent dans l'ordre, avec leur ton")
    func objectifsDeLaCapture() throws {
        let (fil, _) = try semer()
        let modele = ObjectivesCardModel.build(fil)

        #expect(modele.rows.map(\.label) == ["Industrialiser la CI/CD",
                                             "Monter en compétence archi",
                                             "Transmettre (formation Admin)"])
        #expect(modele.rows.map(\.progress) == [70, 25, 10])
        #expect(modele.rows.map(\.percentLabel) == ["70%", "25%", "10%"])
        // Spec §3.4 : < 30 % `warn`, < 70 % violet, ≥ 70 % `ok`. La maquette
        // colore la troisième barre en violet ; c'est la spec qui fait foi ici,
        // et `OneOnOneObjectiveTone` la porte depuis le lot 10.
        #expect(modele.rows.map(\.tone) == [.ok, .warn, .warn])
        #expect(modele.reviewLabel == "Revue prévue le 18 sept.")
    }

    @Test("Un objectif s'ajoute en fin d'ordre, borné, jamais vide")
    func ajoutDObjectif() throws {
        let (fil, context) = try semer()
        #expect(OneOnOnePrepStore.addObjective(label: "   ", in: fil, in: context) == nil)

        let ajoute = try #require(OneOnOnePrepStore.addObjective(label: "  Documenter le socle  ",
                                                                 progress: 140,
                                                                 in: fil, in: context))
        #expect(ajoute.label == "Documenter le socle")
        #expect(ajoute.clampedProgress == 100)
        #expect(ajoute.order == 3)
        // La date de revue est reprise : la carte n'affiche qu'une échéance, et
        // un objectif sans date ne doit pas la faire disparaître.
        #expect(ajoute.reviewAt != nil)
        #expect(ObjectivesCardModel.build(fil).reviewLabel == "Revue prévue le 18 sept.")
    }

    @Test("L'édition inline borne le pourcentage et refuse un libellé vide")
    func editionDObjectif() throws {
        let (fil, context) = try semer()
        let premier = try #require(OneOnOneObjectiveList.sorted(fil.objectives).first)

        OneOnOnePrepStore.update(premier, label: "  ", progress: -5, in: context)
        #expect(premier.label == "Industrialiser la CI/CD")
        #expect(premier.clampedProgress == 0)

        OneOnOnePrepStore.update(premier, progress: 42, in: context)
        #expect(premier.clampedProgress == 42)
        #expect(premier.tone == .oneOnOne)
    }

    @Test("Un fil sans objectif n'affiche ni ligne ni pied")
    func objectifsVides() throws {
        let (fil, _, _) = try filVide()
        let modele = ObjectivesCardModel.build(fil)
        #expect(modele.isEmpty)
        #expect(modele.reviewLabel == nil)
    }

    // MARK: - À ne pas oublier

    @Test("Les rappels gardent l'ordre des règles et leurs tons")
    func rappelsDansLOrdre() throws {
        let (fil, _) = try semer()
        let modele = PrepRemindersModel.build(fil, now: Self.maintenant)

        #expect(!modele.isEmpty)
        #expect(modele.reminders.first?.rule == .managerCommitmentLate)
        #expect(modele.reminders.first?.tone == .report)
        // L'ordre des règles est croissant : jamais une règle 2 avant une
        // règle 1.
        let rangs = modele.reminders.map(\.rule.rawValue)
        #expect(rangs == rangs.sorted())
        #expect(modele.isAgendaButtonEnabled)
    }

    @Test("Le bouton « Mettre à l'ordre du jour » se désactive une fois versé")
    func boutonDesactiveApresVersement() throws {
        let (fil, context) = try semer()
        let avant = PrepRemindersModel.build(fil, now: Self.maintenant)
        #expect(avant.isAgendaButtonEnabled)

        ReminderRules.toAgendaItems(avant.reminders, for: fil, role: .manager, in: context)

        let apres = PrepRemindersModel.build(fil, now: Self.maintenant)
        #expect(!apres.isAgendaButtonEnabled)
        #expect(ReminderRules.areAllOnAgenda(avant.reminders, in: fil))
    }

    @Test("Un fil sans rappel affiche son invite et un bouton inactif")
    func rappelsVides() throws {
        let (fil, _, _) = try filVide()
        let modele = PrepRemindersModel.build(fil, now: Self.maintenant)
        #expect(modele.isEmpty)
        #expect(!modele.isAgendaButtonEnabled)
    }

    // MARK: - Sujets récurrents

    @Test("Les chips de la capture sortent triées et colorées par famille")
    func sujetsRecurrents() throws {
        let (fil, _) = try semer()
        let modele = RecurringTopicsCardModel.build(fil, now: Self.maintenant)

        let libelles = modele.topics.map { RecurringTopicsBuilder.chipLabel($0) }
        #expect(libelles.first == "Charge de travail · 5")
        #expect(libelles.contains("Mobilité archi · 3"))
        // Décroissant, sans exception.
        let comptes = modele.topics.map(\.count)
        #expect(comptes == comptes.sorted(by: >))

        let charge = try #require(modele.topics.first { $0.family == .charge })
        #expect(RecurringTopicsCardModel.tone(of: charge) == .warn)
        let carriere = try #require(modele.topics.first { $0.family == .carriere })
        #expect(RecurringTopicsCardModel.tone(of: carriere) == .oneOnOne)
    }

    @Test("Un fil neuf n'affiche aucune chip mais une invite")
    func sujetsVides() throws {
        let (fil, _, _) = try filVide()
        #expect(RecurringTopicsCardModel.build(fil, now: Self.maintenant).isEmpty)
    }

    // MARK: - Historique

    @Test("L'historique montre les quatre dernières séances, la courante exclue")
    func historiqueDeLaCapture() throws {
        let (fil, _) = try semer()
        let courante = try derniereSeance(fil)
        let modele = ThreadHistoryModel.build(fil, current: courante, now: Self.maintenant)

        #expect(modele.rows.count == ThreadHistoryModel.visibleCount)
        #expect(modele.rows.map(\.dateLabel) == ["21 août", "24 juil.", "10 juil.", "26 juin"])
        #expect(modele.rows.map(\.summary) == [
            "Nexus repris · moral « Bien » · astreinte évoquée",
            "Charge signalée une 1re fois · grille d'astreinte promise",
            "Souhait de mobilité archi formulé",
            "Objectifs S2 posés"
        ])
        #expect(modele.rows.allSatisfy { !$0.isPlaceholder })
        #expect(!modele.rows.contains { $0.id == courante.persistentModelID })
    }

    @Test("Déplié, l'historique montre tout le fil sauf la séance courante")
    func historiqueDeplie() throws {
        let (fil, _) = try semer()
        let courante = try derniereSeance(fil)
        let modele = ThreadHistoryModel.build(fil, current: courante,
                                              now: Self.maintenant, limit: .max)
        #expect(modele.rows.count == RefonteDemoSeed.managerThreadSessionCount - 1)
    }

    @Test("Une séance sans rapport se résume par son moral et son premier sujet")
    func resumeReconstruit() throws {
        let (fil, context, personne) = try filVide()
        let seance = Meeting(title: "1:1 Alice",
                             date: Self.maintenant.addingTimeInterval(-14 * Self.jour),
                             notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(personne)
        MoodTrend.record(4, for: seance, in: fil, in: context)
        let note = MeetingNote(t: 0, text: "Charge sur la migration AP", kind: .note,
                              visibility: .shared)
        context.insert(note)
        note.meeting = seance
        let courante = Meeting(title: "1:1 Alice suivant", date: Self.maintenant, notes: "")
        courante.kind = .oneToOne
        context.insert(courante)
        courante.participants.append(personne)

        let modele = ThreadHistoryModel.build(fil, current: courante, now: Self.maintenant)
        #expect(modele.rows.count == 1)
        #expect(modele.rows[0].summary == "moral « Bien » · Charge sur la migration AP")
        #expect(!modele.rows[0].isPlaceholder)
    }

    @Test("Une séance vide devient une invite, jamais une ligne blanche")
    func resumeAbsent() throws {
        let (fil, context, personne) = try filVide()
        let seance = Meeting(title: "1:1 Alice",
                             date: Self.maintenant.addingTimeInterval(-14 * Self.jour),
                             notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(personne)

        let modele = ThreadHistoryModel.build(fil, current: nil, now: Self.maintenant)
        #expect(modele.rows.count == 1)
        #expect(modele.rows[0].isPlaceholder)
        #expect(modele.rows[0].summary == ThreadHistoryModel.placeholder)
    }

    @Test("Un premier entretien n'a pas d'historique")
    func historiqueVide() throws {
        let (fil, _, _) = try filVide()
        #expect(ThreadHistoryModel.build(fil, current: nil, now: Self.maintenant).isEmpty)
    }

    // MARK: - Semis du lot 12

    @Test("Semer le lot 12 deux fois ne duplique ni fil ni résumé")
    func semisIdempotent() throws {
        let (fil, context) = try semer()
        let seconds = RefonteDemoSeed.seedLot12(in: context)

        #expect(seconds.manager.persistentModelID == fil.persistentModelID)
        #expect(try context.fetch(FetchDescriptor<OneOnOneThread>()).count == 2)
        let courante = try derniereSeance(fil)
        #expect(ThreadHistoryModel.build(fil, current: courante,
                                         now: Self.maintenant).rows.count == 4)
    }

    /// Le recalage des dates est **assigné** et non décalé : semé deux fois, il
    /// ne recule pas le fil d'un mois. Sans cette garantie, un second clic sur
    /// l'item de menu de démonstration rendrait la recette incomparable à la
    /// maquette.
    @Test("Le recalage des dates du fil est idempotent et suit la capture")
    func datesDuFil() throws {
        let (fil, context) = try semer()

        func sixDernieres(_ fil: OneOnOneThread) -> [String] {
            MoodTrend.series(fil).map { OneOnOneDateFormat.shortSlashed($0.recordedAt) }
        }
        let attendues = ["12/06", "26/06", "10/07", "24/07", "21/08", "04/09"]
        #expect(sixDernieres(fil) == attendues)
        #expect(OneOnOneThreadStore.allMeetings(of: fil).count
                == RefonteDemoSeed.managerThreadSessionCount)

        RefonteDemoSeed.seedLot12(in: context)
        #expect(sixDernieres(fil) == attendues)
        #expect(OneOnOneThreadStore.allMeetings(of: fil).count
                == RefonteDemoSeed.managerThreadSessionCount)

        // La séance courante reste la quatorzième : le trou d'août ne change
        // pas le rang, il change l'écart.
        let courante = try derniereSeance(fil)
        #expect(OneOnOneThreadStore.sessionNumber(of: courante, in: fil)
                == RefonteDemoSeed.managerThreadSessionCount)
    }
}
