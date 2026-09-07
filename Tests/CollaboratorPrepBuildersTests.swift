import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les trois blocs de la préparation en deux minutes du 1:1 **subi**
/// (capture 5b, spec §6.3), et le critère d'acceptation chantier 5 n° 4 :
/// « une promesse du manager non tenue remonte automatiquement à la
/// préparation suivante ».
///
/// Tout est **pur** : les trois modèles ne reçoivent qu'un fil et une horloge,
/// et c'est ce qui permet de vérifier `demain 14:00` sans attendre demain.
@Suite("Préparation 1:1 subi — les trois blocs (spec §6.3)")
@MainActor
struct CollaboratorPrepBuildersTests {

    /// Vendredi 4 septembre 2026, 9 h 15 — la date du jeu de démonstration.
    static var seedDate: Date { RefonteDemoSeed.oneOnOneSeedDate }
    private static let jour: TimeInterval = 86_400

    private func contexte() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Le fil « Yann PENVEN me manage » du jeu des lots 10 et 13, et sa séance.
    private func filDeDemonstration() throws -> (context: ModelContext,
                                                 thread: OneOnOneThread,
                                                 meeting: Meeting) {
        let context = try contexte()
        let seme = try #require(RefonteDemoSeed.seedLot13(in: context))
        return (context, seme.thread, seme.meeting)
    }

    /// Un fil neuf, sans rien : la matière des invites de vide.
    private func filNeuf(_ context: ModelContext) throws -> (OneOnOneThread, Meeting) {
        let personne = Collaborator(name: "Yann PENVEN", role: "Manager")
        context.insert(personne)
        let seance = Meeting(title: "1:1 avec Yann · 1", date: Self.seedDate, notes: "")
        seance.kind = .manager
        context.insert(seance)
        seance.participants.append(personne)
        let fil = try #require(OneOnOneThreadStore.thread(for: personne, kind: .manager,
                                                          in: context))
        try context.save()
        return (fil, seance)
    }

    // MARK: - RESTÉ SANS RÉPONSE (critère chantier 5 n° 4)

    @Test("Une promesse du manager non tenue remonte seule, avec son ancienneté")
    func promesseNonTenueRemonte() throws {
        let (_, fil, _) = try filDeDemonstration()
        let lignes = UnansweredItemsBuilder.build(fil, now: Self.seedDate)

        // Deux lignes, comme la capture : les trois sources se recoupent par
        // famille (mobilité d'un côté, astreintes de l'autre).
        #expect(lignes.count == 2)

        let astreintes = try #require(lignes.first { $0.source == .promise })
        // La promesse « Grille de compensation des astreintes » est ouverte,
        // échue depuis le 24 juillet et reportée deux fois : personne ne l'a
        // ressaisie, elle est là parce qu'elle n'a pas été tenue.
        #expect(astreintes.text == "Grille de compensation des astreintes promise, 2 reports")
        #expect(astreintes.sinceLabel == "depuis le 24 juil.")

        let mobilite = try #require(lignes.first { $0.source == .topic })
        #expect(mobilite.text.hasPrefix("Mobilité archi — "))
        #expect(mobilite.text.hasSuffix(" fois évoquée, jamais tranchée"))
        // La date vient de la demande du 10 juillet, que le regroupement a
        // fondue dans la ligne : c'est l'ancienneté du sujet qui plaide.
        #expect(mobilite.sinceLabel == "depuis le 10 juil.")

        // La plus vieille ligne d'abord.
        #expect(lignes.map(\.id) == [mobilite.id, astreintes.id])
    }

    @Test("Une promesse tenue ou à échoir ne remonte pas")
    func promesseTenueOuAEchoir() throws {
        let context = try contexte()
        let (fil, _) = try filNeuf(context)

        let tenue = Commitment(text: "Retour sur la grille d'astreinte", ownerSide: .manager,
                               dueAt: Self.seedDate.addingTimeInterval(-10 * Self.jour),
                               state: .kept,
                               promisedAt: Self.seedDate.addingTimeInterval(-30 * Self.jour))
        let aVenir = Commitment(text: "Arbitrage renfort ou décalage", ownerSide: .manager,
                                dueAt: Self.seedDate.addingTimeInterval(3 * Self.jour),
                                state: .open, promisedAt: Self.seedDate)
        // Une promesse **de moi** n'est pas « restée sans réponse » : c'est moi
        // qui la dois.
        let mienne = Commitment(text: "Chiffrage de la reprise", ownerSide: .collaborator,
                                dueAt: Self.seedDate.addingTimeInterval(-5 * Self.jour),
                                state: .open,
                                promisedAt: Self.seedDate.addingTimeInterval(-20 * Self.jour))
        for engagement in [tenue, aVenir, mienne] {
            context.insert(engagement)
            engagement.thread = fil
        }
        try context.save()

        #expect(UnansweredItemsBuilder.build(fil, now: Self.seedDate).isEmpty)
    }

    @Test("Une demande accordée ou refusée a eu sa réponse")
    func demandeTranchee() throws {
        let context = try contexte()
        let (fil, seance) = try filNeuf(context)

        let statuts: [(String, RequestStatus)] = [
            ("Budget formation Terraform", .granted),
            ("Télétravail le mercredi", .refused),
            ("Prime d'astreinte", .waiting)
        ]
        for (rang, ligne) in statuts.enumerated() {
            let item = OneOnOneAgendaItem(text: ligne.0, addedBySide: .collaborator,
                                          order: rang, visibility: .private,
                                          kind: .request, requestStatus: ligne.1,
                                          requestedAt: Self.seedDate
                                              .addingTimeInterval(-30 * Self.jour))
            context.insert(item)
            item.thread = fil
            item.meeting = seance
        }
        try context.save()

        let lignes = UnansweredItemsBuilder.build(fil, now: Self.seedDate)
        #expect(lignes.count == 1)
        #expect(lignes.first?.text == "Prime d'astreinte")
        #expect(lignes.first?.source == .request)
    }

    // MARK: - CE QUE JE VEUX OBTENIR

    @Test("Les sujets voulus sont mes sujets privés, moins ceux déjà portés en suspens")
    func sujetsVoulus() throws {
        let (_, fil, _) = try filDeDemonstration()
        let suspens = UnansweredItemsBuilder.build(fil, now: Self.seedDate)
        let voulus = WantedItemsBuilder.build(fil, excluding: suspens)

        // Trois sujets privés au fil ; celui de la mobilité est déjà porté par
        // la ligne « Mobilité archi » de `RESTÉ SANS RÉPONSE`, et une même
        // demande ne s'affiche pas deux fois sur un écran de dix lignes.
        #expect(voulus.count == 2)
        #expect(voulus.map(\.text).contains("Porter la formation Admin"))
        #expect(voulus.contains { $0.text.hasPrefix("Charge :") })
        #expect(!voulus.contains { $0.text.contains("Mobilité") })
        // Ce sont des sujets, jamais des demandes : celles-ci ont leur bloc.
        #expect(voulus.allSatisfy { $0.kind == .topic && $0.visibility == .private })
    }

    @Test("Un sujet traité ou partagé n'est plus un sujet à porter")
    func sujetsEcartes() throws {
        let context = try contexte()
        let (fil, seance) = try filNeuf(context)

        let lignes: [(String, AgendaItemState, Visibility)] = [
            ("Porter la formation Admin", .todo, .private),
            ("Sujet déjà traité", .done, .private),
            ("Sujet déjà partagé", .todo, .shared)
        ]
        for (rang, ligne) in lignes.enumerated() {
            let item = OneOnOneAgendaItem(text: ligne.0, addedBySide: .collaborator,
                                          order: rang, state: ligne.1, visibility: ligne.2)
            context.insert(item)
            item.thread = fil
            item.meeting = seance
        }
        try context.save()

        let voulus = WantedItemsBuilder.build(fil, excluding: [])
        #expect(voulus.map(\.text) == ["Porter la formation Admin"])
    }

    // MARK: - L'en-tête

    @Test("Une séance planifiée demain s'écrit « demain 14:00 »")
    func enteteDemain() throws {
        let context = try contexte()
        let (fil, _) = try filNeuf(context)
        let personne = try #require(fil.collaborator)

        // Horloge injectée : le 4 septembre 2026 à 9 h 15, la séance du
        // lendemain 14 h 00 s'écrit « demain ». Rien n'attend demain.
        let maintenant = Self.seedDate
        let demain = try #require(Self.aQuatorzeHeures(joursApres: 1, de: maintenant))
        let seance = Meeting(title: "1:1 avec Yann · 2", date: demain, notes: "")
        seance.kind = .manager
        context.insert(seance)
        seance.participants.append(personne)
        try context.save()

        let entete = CollabPrepModel.header(meeting: seance, thread: fil, now: maintenant)
        #expect(entete.title == "1:1 avec Yann — demain 14:00")
        #expect(entete.badge == "Collaborateur")
        #expect(entete.initials == "YP")
        // « dernier point » : la séance du 4 septembre, celle qui précède.
        #expect(entete.meta == "Préparation · 2 min · dernier point le 4 sept.")
    }

    @Test("Aujourd'hui, plus tard dans la semaine, et au-delà")
    func enteteAutresJours() throws {
        let context = try contexte()
        let (fil, _) = try filNeuf(context)
        let personne = try #require(fil.collaborator)
        let maintenant = Self.seedDate

        func entete(joursApres: Int) throws -> CollabPrepHeaderModel {
            let quand = try #require(Self.aQuatorzeHeures(joursApres: joursApres, de: maintenant))
            let seance = Meeting(title: "1:1 avec Yann · \(10 + joursApres)",
                                 date: quand, notes: "")
            seance.kind = .manager
            context.insert(seance)
            seance.participants.append(personne)
            try context.save()
            return CollabPrepModel.header(meeting: seance, thread: fil, now: maintenant)
        }

        #expect(try entete(joursApres: 0).title == "1:1 avec Yann — aujourd'hui 14:00")
        // Dans la fenêtre de sept jours : le jour de la semaine, comme toutes
        // les échéances du domaine (`OneOnOneDateFormat.dueDate`).
        #expect(try entete(joursApres: 3).title == "1:1 avec Yann — Lundi 14:00")
        #expect(try entete(joursApres: 14).title == "1:1 avec Yann — 18 sept. 14:00")
    }

    @Test("Un premier entretien annonce un premier point, sans date inventée")
    func entetePremierEntretien() throws {
        let context = try contexte()
        let (fil, seance) = try filNeuf(context)
        let entete = CollabPrepModel.header(meeting: seance, thread: fil, now: Self.seedDate)
        #expect(entete.meta == "Préparation · 2 min · premier point")
    }

    // MARK: - Aucune zone vide sans invite

    @Test("Un fil neuf offre une invite pour chacun des trois blocs")
    func troisInvites() throws {
        let context = try contexte()
        let (fil, seance) = try filNeuf(context)

        let suspens = UnansweredItemsBuilder.build(fil, now: Self.seedDate)
        let voulus = WantedItemsBuilder.build(fil, excluding: suspens)
        #expect(suspens.isEmpty)
        #expect(voulus.isEmpty)
        // Aucune séance précédente : la fenêtre des livrés n'a pas de borne.
        #expect(CollabPrepModel.deliveredSince(seance, in: fil) == nil)

        for invite in [UnansweredItemsBuilder.emptyInvite,
                       WantedItemsBuilder.emptyInvite,
                       CollabPrepModel.deliveredEmptyInvite] {
            #expect(!invite.isEmpty)
            // Une invite dit quoi faire : elle se termine par une action, pas
            // par le constat du vide (spec §1.1, critère chantier 1 n° 1).
            #expect(invite.count > 30)
        }
        #expect(!CollabPrepModel.provenance.isEmpty)
    }

    // MARK: - Outils

    /// Le `n`-ième jour après `date`, à 14 h 00 pile, calendrier grégorien
    /// `fr_FR` — l'heure de la capture.
    private static func aQuatorzeHeures(joursApres n: Int, de date: Date) -> Date? {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.locale = Locale(identifier: "fr_FR")
        guard let jour = calendrier.date(byAdding: .day, value: n, to: date) else { return nil }
        return calendrier.date(bySettingHour: 14, minute: 0, second: 0, of: jour)
    }
}
