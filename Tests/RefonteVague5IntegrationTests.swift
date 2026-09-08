import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Ce que l'**intégration** de la vague 5 doit tenir, et qu'aucun lot seul ne
/// pouvait vérifier.
///
/// Les lots 7, 11, 12 et 16 ont été écrits en parallèle, sans se lire. Trois
/// familles de doublons en sont sorties — une table de teintes, une identité de
/// personne, une règle d'échéance — plus deux crochets de recette pour le même
/// besoin. Chacun se corrigeait dans son fichier ; ce qu'aucun test de lot ne
/// pouvait dire, c'est qu'il n'en reste **qu'une définition**. C'est le rôle de
/// ce fichier, et c'est pour cela qu'il ne porte pas de numéro de lot.
@Suite("Intégration vague 5 — une seule définition par règle")
@MainActor
struct RefonteVague5IntegrationTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }
    private static let jour: TimeInterval = 86_400

    private func contexte() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: - (a) Le moral : une seule table de teintes

    @Test("Séance et préparation colorent identiquement chacun des cinq crans")
    func teinteDuMoralPartagee() {
        for cran in MoodLevel.allCases {
            // `MoodScale` (2a) passe par `MoodScaleModel.tone`,
            // `MoodHistogram` (2b) par `MoodHistogramModel.tone` : les deux
            // doivent rendre la table du domaine, `OneOnOneMoodTone`.
            #expect(MoodScaleModel.tone(cran) == OneOnOneMoodTone.tone(cran))
            #expect(MoodHistogramModel.tone(for: cran) == OneOnOneMoodTone.tone(cran))
            #expect(MoodScaleModel.tone(cran) == MoodHistogramModel.tone(for: cran))
        }
        // Le cran qui divergeait : le lot 12 le voulait violet, le lot 11
        // vert. Une seule table, donc une seule réponse.
        #expect(MoodHistogramModel.tone(for: .bien) == .ok)
    }

    // MARK: - (b) L'identité : un seul nom, un seul rôle, un seul avatar

    @Test("L'en-tête de préparation lit la personne comme la carte de séance")
    func identitePartagee() throws {
        let context = try contexte()
        let fils = RefonteDemoSeed.seedLot12(in: context)
        _ = RefonteDemoSeed.seedLot11(in: context)
        let fil = fils.manager
        let seance = try #require(OneOnOneThreadStore.allMeetings(of: fil).last)

        let entete = PrepHeaderModel.build(meeting: seance, thread: fil)
        #expect(entete.name == PersonCardModel.name(of: fil))
        #expect(entete.initials == PersonCardModel.initials(of: fil))
        // Le rôle de la méta est celui de la carte personne, filtre « Néant »
        // compris — et non une seconde lecture du collaborateur.
        let role = PersonCardModel.role(of: fil)
        #expect(!role.isEmpty)
        #expect(entete.subtitle.hasPrefix(role))
        // Ce qui reste propre à 2b : l'ordinal de séance.
        #expect(entete.sessionNumber > 1)
        #expect(entete.subtitle.contains("\(PrepHeaderModel.ordinal(entete.sessionNumber)) 1:1"))
        // L'ancienneté se lit du même endroit que la carte de séance
        // (`OneOnOneSeniority`), même si la méta de 2b ne l'affiche pas.
        #expect(PrepHeaderModel.seniority(of: fil, now: Self.maintenant)
                == OneOnOneSeniority.label(joinedAt: fil.collaborator?.joinedAt,
                                           now: Self.maintenant))
    }

    @Test("Un fil sans personne dit la même chose des deux côtés")
    func identiteSansPersonne() throws {
        let context = try contexte()
        let fil = OneOnOneThread()
        context.insert(fil)
        let seance = Meeting(title: "Entretien orphelin", date: Self.maintenant, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)

        #expect(PersonCardModel.name(of: fil) == PersonCardModel.fallbackName)
        #expect(PersonCardModel.initials(of: fil) == "?")
        let entete = PrepHeaderModel.build(meeting: seance, thread: fil)
        #expect(entete.name == PersonCardModel.fallbackName)
        #expect(entete.initials == "?")
        #expect(PrepHeaderModel.fallbackName == PersonCardModel.fallbackName)
    }

    // MARK: - (c) L'engagement : une seule règle d'échéance

    @Test("Rail de séance et tableau de préparation datent une échéance pareil")
    func echeancePartagee() throws {
        let context = try contexte()
        let fils = RefonteDemoSeed.seedLot12(in: context)
        _ = RefonteDemoSeed.seedLot11(in: context)
        let fil = fils.manager

        for engagement in fil.commitments where engagement.state == .open {
            guard let echeance = engagement.dueAt else {
                #expect(CommitmentsRailModel.duePill(engagement, now: Self.maintenant) == nil)
                continue
            }
            let attendu = OneOnOneDateFormat.dueDate(echeance, now: Self.maintenant)
            #expect(CommitmentsRailModel.duePill(engagement, now: Self.maintenant) == attendu)
            // Le tableau de 2b écrit `En retard` pour une échéance passée, la
            // même date sinon : c'est la seule divergence, et elle est voulue
            // (une colonne de tableau peut porter un état, une pilule non).
            let colonne = CommitmentsTableModel.dueLabel(engagement, now: Self.maintenant)
            #expect(colonne.label == (echeance < Self.maintenant ? "En retard" : attendu))
        }
    }

    @Test("Le compteur de reports a un seul formatage, celui du registre")
    func reportsPartages() throws {
        let context = try contexte()
        let fils = RefonteDemoSeed.seedLot12(in: context)
        let fil = fils.manager
        let reporte = try #require(fil.commitments.first { $0.deferralCount > 0 })

        // Le rail (2a) et le tableau (2b) affichent tous deux
        // `CommitmentLedger.deferralLabel` : aucun des deux ne recompose la
        // chaîne « n× reporté ».
        let attendu = CommitmentLedger.deferralLabel(reporte)
        #expect(attendu == "2× reporté")
        let table = CommitmentsTableModel.build(fil, current: nil,
                                                filter: .both, now: Self.maintenant)
        let ligne = try #require(table.rows.first { $0.text == reporte.text })
        #expect(ligne.deferralLabel == attendu)
    }

    // MARK: - Une seule extension de format de date

    @Test("Les écritures de date des écrans 1:1 vivent dans un seul fichier")
    func formatsDeDateUniques() {
        let vendredi = Self.maintenant
        #expect(OneOnOneDateFormat.weekday(vendredi) == "Vendredi")
        #expect(OneOnOneDateFormat.dayFullMonth(vendredi) == "4 septembre")
        #expect(OneOnOneDateFormat.weekdayWindowDays == 7)
        #expect(OneOnOneDateFormat.isWithinWeekdayWindow(vendredi, now: vendredi))
        #expect(OneOnOneDateFormat.isWithinWeekdayWindow(
            vendredi.addingTimeInterval(6 * Self.jour), now: vendredi))
        #expect(!OneOnOneDateFormat.isWithinWeekdayWindow(
            vendredi.addingTimeInterval(7 * Self.jour), now: vendredi))
        // La fabrique et la règle rendent la même chose : `dueDate` n'a pas sa
        // propre écriture du jour.
        #expect(OneOnOneDateFormat.dueDate(vendredi, now: vendredi)
                == OneOnOneDateFormat.weekday(vendredi))
        #expect(OneOnOneDateFormat.dueDate(vendredi.addingTimeInterval(7 * Self.jour),
                                           now: vendredi)
                == OneOnOneDateFormat.dayMonth(vendredi.addingTimeInterval(7 * Self.jour)))
    }

    // MARK: - Le routage : quatre branches exclusives

    @Test("Atelier, 1:1 et disposition standard ne se disputent jamais un écran")
    func routageExclusif() {
        for kind in MeetingKind.allCases {
            for mode in MeetingScreenModel.Mode.allCases {
                let atelier = kind == .workshop && mode == .live
                let seance = MeetingSpaceRouting.usesOneOnOneManagerSession(kind: kind, mode: mode)
                let preparation = MeetingSpaceRouting.usesOneOnOnePreparation(kind: kind, mode: mode)
                // Lot 13 : la quatrième branche 1:1, celle de l'entretien subi.
                let subie = MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: kind,
                                                                                mode: mode)
                let relire = mode == .review
                let vraies = [atelier, seance, preparation, subie, relire].filter { $0 }.count
                #expect(vraies <= 1,
                        "\(kind) / \(mode) : \(vraies) branches de routage revendiquent l'écran")
            }
        }
    }

    // MARK: - Le crochet de recette : un seul, et dix codes

    @Test("Les dix codes d'écran désignent une réunion et un mode")
    func codesDeRecette() {
        // Dix depuis le lot 13, qui ajoute `5a` (l'entretien subi).
        #expect(RecetteScreen.allCases.count == 10)
        #expect(RecetteScreen.from(environment: nil) == nil)
        #expect(RecetteScreen.from(environment: "") == nil)
        #expect(RecetteScreen.from(environment: "1to1") == nil)
        #expect(RecetteScreen.from(environment: "2A") == .oneOnOneSession)

        let attendu: [(String, RecetteScreen.Cible, MeetingScreenModel.Mode)] = [
            ("1a", .demonstration, .live),
            ("1b", .demonstration, .live),
            ("1c", .demonstration, .review),
            ("2a", .entretienMene, .live),
            ("2b", .entretienMene, .prepare),
            ("3a", .demonstration, .live),
            ("3b", .demonstration, .live),
            ("4a", .demonstration, .live),
            ("5a", .entretienSubi, .live),
            ("6a", .atelier, .live)
        ]
        #expect(attendu.count == RecetteScreen.allCases.count)
        for (code, cible, mode) in attendu {
            let ecran = RecetteScreen.from(environment: code)
            #expect(ecran?.rawValue == code)
            #expect(ecran?.cible == cible)
            #expect(ecran?.mode == mode)
        }
    }

    // MARK: - Les semis de la vague cohabitent

    /// La liste reflète **les deux points d'entrée** — le menu
    /// (`MeetingCommands`) et le semis de recette (`OneToOneApp`) : lot 13
    /// depuis la vague 6, et `seedWorkshopComplete` à la place de
    /// `seedWorkshop` depuis le lot 17. Un semis appelé en production mais
    /// absent d'ici ne serait jamais vu cohabiter avec les autres.
    @Test("Les semis de la vague, ensemble et deux fois, ne dupliquent rien")
    func semisEnsemble() throws {
        let context = try contexte()
        // `seedWorkshopComplete` **écrit des fichiers** (les scènes des
        // planches, la pièce et la capture de la section `PIÈCES & CAPTURES`) :
        // le magasin et sa racine sont injectés dans un dossier temporaire,
        // sinon le test salirait le `recordings/` réel — même précaution que
        // `WorkshopSeedLot17Tests`.
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("semis-vague6-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        let magasin = BoardStore(recordingsRoot: racine)

        func semerTout() -> Meeting {
            let demonstration = RefonteDemoSeed.seedLot5(in: context)
            _ = RefonteDemoSeed.seedLot6(in: context)
            _ = RefonteDemoSeed.seedLot7(in: context)
            _ = RefonteDemoSeed.seedLot11(in: context)
            _ = RefonteDemoSeed.seedLot12(in: context)
            _ = RefonteDemoSeed.seedLot13(in: context)
            _ = RefonteDemoSeed.seedWorkshopComplete(in: context, store: magasin)
            return demonstration
        }

        _ = semerTout()
        let reunions = try context.fetch(FetchDescriptor<Meeting>()).count
        let engagements = try context.fetch(FetchDescriptor<Commitment>()).count
        let humeurs = try context.fetch(FetchDescriptor<MoodEntry>()).count
        let actions = try context.fetch(FetchDescriptor<ActionTask>()).count

        _ = semerTout()
        #expect(try context.fetch(FetchDescriptor<Meeting>()).count == reunions)
        #expect(try context.fetch(FetchDescriptor<Commitment>()).count == engagements)
        #expect(try context.fetch(FetchDescriptor<MoodEntry>()).count == humeurs)
        #expect(try context.fetch(FetchDescriptor<ActionTask>()).count == actions)
    }

    @Test("Le recalage des dates du lot 12 laisse la séance 2a cohérente")
    func recalageEtSeance2a() throws {
        let context = try contexte()
        // L'ordre du menu : le lot 11 puis le lot 12, donc le recalage des
        // dates passe **après** que le lot 11 a posé ses engagements.
        let seme = try #require(RefonteDemoSeed.seedLot11(in: context))
        _ = RefonteDemoSeed.seedLot12(in: context)
        let fil = seme.thread

        // La séance de la capture reste le 4 septembre, et reste la dernière.
        let seances = OneOnOneThreadStore.allMeetings(of: fil)
        #expect(seances.last?.persistentModelID == seme.meeting.persistentModelID)
        #expect(Calendar(identifier: .gregorian)
            .isDate(seme.meeting.date, inSameDayAs: Self.maintenant))

        // L'entretien précédent est à quinze jours : c'est la fenêtre de
        // `TENUS DEPUIS LE DERNIER 1:1`, et la ligne du lot 11 (soldée dix
        // jours avant la séance) doit y entrer.
        let precedent = try #require(OneOnOneThreadStore.previousMeeting(before: seme.meeting,
                                                                        in: fil))
        #expect(precedent.date < seme.meeting.date)
        let lignes = CommitmentsRailModel.ledgerLines(for: seme.meeting, in: fil,
                                                      ownerName: RefonteDemoSeed.sessionOwnerName,
                                                      now: Self.maintenant)
        #expect(lignes.contains { $0.text == "Accès environnement recette" })

        // Et l'histogramme de 2b garde les six dates de la maquette.
        let histogramme = MoodHistogramModel.build(fil, now: Self.maintenant)
        #expect(histogramme.bars.map(\.dateLabel)
                == ["12/06", "26/06", "10/07", "24/07", "21/08", "04/09"])
    }
}
