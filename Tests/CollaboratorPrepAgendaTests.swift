import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// `En faire mon ordre du jour` et `Partager les sujets à <Prénom>`
/// (capture 5b, spec §6.3), le composeur `Ajouter…`, le routage du mode
/// Préparer d'un 1:1 subi, et l'action « Préparer » du rappel de la veille.
@Suite("Préparation 1:1 subi — ordre du jour, partage et ouverture (spec §6.3)")
@MainActor
struct CollaboratorPrepAgendaTests {

    static var seedDate: Date { RefonteDemoSeed.oneOnOneSeedDate }

    private func contexte() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Le fil « Yann PENVEN me manage » du jeu des lots 10 et 13, sa séance, et
    /// le plan que l'écran propose au premier affichage : **les cases sans
    /// réponse décochées, les sujets voulus cochés**.
    private func planDeDemonstration() throws -> (context: ModelContext,
                                                  thread: OneOnOneThread,
                                                  meeting: Meeting,
                                                  unanswered: [UnansweredItemsBuilder.Item],
                                                  wanted: [OneOnOneAgendaItem]) {
        let context = try contexte()
        let seme = try #require(RefonteDemoSeed.seedLot13(in: context))
        let suspens = UnansweredItemsBuilder.build(seme.thread, now: Self.seedDate)
        let voulus = WantedItemsBuilder.build(seme.thread, excluding: suspens)
        return (context, seme.thread, seme.meeting, suspens, voulus)
    }

    // MARK: - L'ordre

    @Test("Les lignes sans réponse cochées passent devant les sujets voulus, préfixées")
    func ordreDuPlan() throws {
        let jeu = try planDeDemonstration()
        let plan = PrepToAgenda.plan(unanswered: jeu.unanswered, wanted: jeu.wanted)

        #expect(plan.count == 4)
        // Les deux lignes sans réponse d'abord, dans leur ordre d'ancienneté,
        // et chacune dit de quoi elle est faite.
        #expect(plan[0].text.hasPrefix("Sujet : Mobilité archi — "))
        #expect(plan[1].text
                == "Promesse : Grille de compensation des astreintes promise, 2 reports")
        #expect(plan[0].isExisting == false)
        #expect(plan[1].isExisting == false)
        // Puis mes sujets, tels que je les ai écrits : ils existent déjà.
        #expect(plan[2].isExisting)
        #expect(plan[3].isExisting)
        #expect(plan.map(\.text).contains("Porter la formation Admin"))
    }

    @Test("Les préfixes nomment la source de chaque ligne")
    func prefixes() {
        #expect(PrepToAgenda.prefix(for: .promise) == "Promesse : ")
        #expect(PrepToAgenda.prefix(for: .topic) == "Sujet : ")
        #expect(PrepToAgenda.prefix(for: .request) == "Demande : ")
    }

    @Test("Une ligne décochée n'est pas portée")
    func lignesDecochees() throws {
        let jeu = try planDeDemonstration()
        // L'état d'ouverture de l'écran : rien de coché à gauche, tout coché à
        // droite. Le plan ne porte alors que mes sujets.
        let plan = PrepToAgenda.plan(unanswered: [], wanted: jeu.wanted)
        #expect(plan.count == 2)
        #expect(plan.allSatisfy { $0.isExisting })
    }

    // MARK: - La matérialisation

    @Test("Le bouton crée des sujets privés, numérotés dans l'ordre du plan")
    func materialisation() throws {
        let jeu = try planDeDemonstration()
        let plan = PrepToAgenda.plan(unanswered: jeu.unanswered, wanted: jeu.wanted)

        let portes = PrepToAgenda.apply(plan, for: jeu.meeting, in: jeu.thread,
                                        in: jeu.context)
        #expect(portes.count == 4)
        #expect(portes.map(\.text) == plan.map(\.text))
        #expect(portes.map(\.order) == [0, 1, 2, 3])
        #expect(portes.allSatisfy { $0.kind == .topic })
        #expect(portes.allSatisfy { $0.state == .todo })
        // Spec §6.1 : côté collaborateur, le défaut n'est pas négociable.
        #expect(portes.allSatisfy { $0.visibility == .private })
        #expect(portes.allSatisfy { $0.meeting?.persistentModelID
                                    == jeu.meeting.persistentModelID })

        // Les autres sujets de la séance suivent, ils ne devancent pas le plan.
        let sujets = AgendaCarryover.items(of: jeu.thread, for: jeu.meeting)
            .filter { $0.kind == .topic }
        #expect(sujets.prefix(4).map(\.text) == plan.map(\.text))
        // Les demandes gardent leurs rangs : leur carte est une autre liste.
        #expect(AgendaCarryover.requests(of: jeu.thread).count == 3)
    }

    @Test("Un second clic ne duplique rien")
    func idempotence() throws {
        let jeu = try planDeDemonstration()
        let plan = PrepToAgenda.plan(unanswered: jeu.unanswered, wanted: jeu.wanted)

        #expect(!PrepToAgenda.isApplied(plan, in: jeu.thread))
        PrepToAgenda.apply(plan, for: jeu.meeting, in: jeu.thread, in: jeu.context)
        let apresLePremier = jeu.thread.agendaItems.count
        #expect(PrepToAgenda.isApplied(plan, in: jeu.thread))

        let secondes = PrepToAgenda.apply(plan, for: jeu.meeting, in: jeu.thread,
                                          in: jeu.context)
        #expect(jeu.thread.agendaItems.count == apresLePremier)
        #expect(secondes.map(\.text) == plan.map(\.text))
        #expect(secondes.map(\.order) == [0, 1, 2, 3])
    }

    @Test("Le bouton dit ce qu'il a fait plutôt que de le promettre encore")
    func libelles() throws {
        let jeu = try planDeDemonstration()
        #expect(PrepToAgenda.agendaButtonLabel == "En faire mon ordre du jour")
        #expect(PrepToAgenda.doneLabel(4) == "Ordre du jour prêt · 4 sujets")
        #expect(PrepToAgenda.doneLabel(1) == "Ordre du jour prêt · 1 sujet")
        #expect(PrepToAgenda.shareButtonLabel(for: jeu.thread) == "Partager les sujets à Yann")
        #expect(PrepToAgenda.shareConfirmation(2) == "Partager 2 sujets avec votre manager ?")
        // Un plan vide n'a rien à verser : le bouton est déjà « fait ».
        #expect(PrepToAgenda.isApplied([], in: jeu.thread))
    }

    // MARK: - Le partage (critère chantier 5 n° 2)

    @Test("Le second bouton passe ces sujets — et eux seuls — en partagé")
    func partage() throws {
        let jeu = try planDeDemonstration()
        let plan = PrepToAgenda.plan(unanswered: jeu.unanswered, wanted: jeu.wanted)
        let privesAvant = jeu.thread.agendaItems.filter { $0.visibility == .private }.count

        let compte = PrepToAgenda.share(plan, for: jeu.meeting, in: jeu.thread,
                                        in: jeu.context)
        #expect(compte == 4)
        #expect(PrepToAgenda.isShared(plan, in: jeu.thread))
        let portes = PrepToAgenda.apply(plan, for: jeu.meeting, in: jeu.thread,
                                        in: jeu.context)
        #expect(portes.allSatisfy { $0.visibility == .shared })

        // Deux des quatre lignes existaient déjà en privé, les deux autres
        // viennent d'être créées : le fil perd exactement deux lignes privées.
        let privesApres = jeu.thread.agendaItems.filter { $0.visibility == .private }.count
        #expect(privesApres == privesAvant - 2)

        // Un second partage ne recompte pas ce qui est déjà partagé.
        #expect(PrepToAgenda.share(plan, for: jeu.meeting, in: jeu.thread,
                                   in: jeu.context) == 0)
    }

    @Test("Une ligne escaladée ne redescend pas vers le manager (D9)")
    func escaladeNeRedescendPas() throws {
        let jeu = try planDeDemonstration()
        let sujet = try #require(jeu.wanted.first)
        sujet.visibility = .escalated
        try jeu.context.save()

        let plan = PrepToAgenda.plan(unanswered: [], wanted: [sujet])
        #expect(PrepToAgenda.share(plan, for: jeu.meeting, in: jeu.thread,
                                   in: jeu.context) == 0)
        #expect(sujet.visibility == .escalated)
    }

    // MARK: - Le composeur

    @Test("Le composeur crée un sujet privé, et refuse le vide")
    func composeur() throws {
        let jeu = try planDeDemonstration()
        let avant = jeu.thread.agendaItems.count

        #expect(CollaboratorPrepStore.addWantedTopic(text: "   ", for: jeu.meeting,
                                                     in: jeu.thread,
                                                     in: jeu.context) == nil)
        #expect(jeu.thread.agendaItems.count == avant)

        // Un libellé qu'aucun lexique de `RecurringTopicFamily` ne reconnaît :
        // un sujet ajouté sur une famille déjà comptée deux fois la porterait
        // au seuil de trois et le ferait basculer dans `RESTÉ SANS RÉPONSE`,
        // ce qui est le comportement voulu mais pas ce que ce test vérifie.
        let cree = try #require(CollaboratorPrepStore.addWantedTopic(
            text: "  Un arbitrage daté avant la fin du mois  ",
            for: jeu.meeting, in: jeu.thread, in: jeu.context))
        #expect(cree.text == "Un arbitrage daté avant la fin du mois")
        #expect(cree.kind == .topic)
        #expect(cree.state == .todo)
        #expect(cree.visibility == .private)
        #expect(cree.meeting?.persistentModelID == jeu.meeting.persistentModelID)

        // Il rejoint immédiatement `CE QUE JE VEUX OBTENIR`.
        let suspens = UnansweredItemsBuilder.build(jeu.thread, now: Self.seedDate)
        let voulus = WantedItemsBuilder.build(jeu.thread, excluding: suspens)
        #expect(voulus.contains { $0.persistentModelID == cree.persistentModelID })
    }

    // MARK: - Le routage

    @Test("Seul le couple (1:1 subi, Préparer) mène à l'écran 5b")
    func aiguillage() {
        #expect(MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: .manager,
                                                                        mode: .prepare))
        #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: .manager,
                                                                         mode: .live))
        #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: .manager,
                                                                         mode: .review))
        // Le 1:1 mené a le sien (2b, lot 12).
        #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: .oneToOne,
                                                                         mode: .prepare))
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(!MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: kind,
                                                                             mode: .prepare))
        }
    }

    @Test("Les six branches de routage ne se disputent jamais un écran")
    func routageExclusif() {
        for kind in MeetingKind.allCases {
            for mode in MeetingScreenModel.Mode.allCases {
                let atelier = kind == .workshop && mode == .live
                // Lot 18, entré dans la base à l'intégration de la vague 7 :
                // l'atelier en Relire monte la planche de séance, et il est
                // **prélevé** sur le poste de pilotage — d'où le `!` de la
                // dernière ligne, qui reproduit l'ordre de
                // `MeetingSpaceView.contenu`.
                let atelierRelecture = MeetingSpaceRouting.usesWorkshopReview(kind: kind,
                                                                              mode: mode)
                let branches = [
                    atelier,
                    atelierRelecture,
                    MeetingSpaceRouting.usesOneOnOneManagerSession(kind: kind, mode: mode),
                    MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: kind, mode: mode),
                    MeetingSpaceRouting.usesOneOnOnePreparation(kind: kind, mode: mode),
                    MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: kind,
                                                                            mode: mode),
                    mode == .review && !atelierRelecture
                ]
                #expect(branches.filter { $0 }.count <= 1,
                        "\(kind) / \(mode) : \(branches.filter { $0 }.count) branches")
            }
        }
    }

    @Test("Un 1:1 subi jamais ouvert et sans enregistrement s'ouvre en Préparer")
    func modeParDefaut() {
        // La spec §3 ouvre un 1:1 en Préparer ; c'est un 1:1 subi qu'on ouvre
        // la veille, depuis la notification de rappel.
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: nil, kind: .manager,
                                                hasRecording: false) == .prepare)
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: nil, kind: .manager,
                                                hasRecording: true) == nil)
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: "live", kind: .manager,
                                                hasRecording: false) == nil)
        for kind in [MeetingKind.global, .project, .work, .workshop, .note] {
            #expect(MeetingSpaceRouting.initialMode(persistedRaw: nil, kind: kind,
                                                    hasRecording: false) == nil)
        }
    }

    // MARK: - L'ouverture la veille

    @Test("Le rappel d'un 1:1 subi porte une action « Préparer », et lui seul")
    func notificationPreparer() {
        #expect(MeetingNotificationService.preStartCategory(for: .manager)
                == MeetingNotificationService.Category.preStartOneOnOne)
        for kind in MeetingKind.allCases where kind != .manager {
            #expect(MeetingNotificationService.preStartCategory(for: kind)
                    == MeetingNotificationService.Category.preStart)
        }

        let categories = MeetingNotificationService.makeCategories()
        let subie = categories.first {
            $0.identifier == MeetingNotificationService.Category.preStartOneOnOne
        }
        let preparer = subie?.actions.first {
            $0.identifier == MeetingNotificationService.Action.prepare
        }
        #expect(preparer?.title == "Préparer")
        // L'action de préparation vient en tête : c'est ce que le rappel de la
        // veille propose de faire.
        #expect(subie?.actions.first?.identifier == MeetingNotificationService.Action.prepare)
        #expect(subie?.actions.count == 3)

        // Le rappel des autres réunions ne change pas : rien à préparer en
        // deux minutes sur une réunion de projet.
        let standard = categories.first {
            $0.identifier == MeetingNotificationService.Category.preStart
        }
        #expect(standard?.actions.contains {
            $0.identifier == MeetingNotificationService.Action.prepare
        } == false)
        // Une seule catégorie par identifiant : `setNotificationCategories`
        // remplace l'ensemble enregistré, un doublon en perdrait une.
        #expect(Set(categories.map(\.identifier)).count == categories.count)
    }

    // MARK: - Aucune ligne deux fois sur la carte

    @Test("Une ligne versée à l'ordre du jour ne réapparaît pas dans les sujets voulus")
    func aucunDoublonApresVersement() throws {
        let jeu = try planDeDemonstration()
        let plan = PrepToAgenda.plan(unanswered: jeu.unanswered, wanted: jeu.wanted)
        PrepToAgenda.apply(plan, for: jeu.meeting, in: jeu.thread, in: jeu.context)

        // Les sujets créés sont des sujets privés `todo` : sans exclusion, la
        // carte du bas les reprendrait tous les deux.
        let suspens = UnansweredItemsBuilder.build(jeu.thread, now: Self.seedDate)
        let voulus = WantedItemsBuilder.build(jeu.thread, excluding: suspens)
        #expect(!voulus.contains { $0.text.hasPrefix("Promesse : ") })
        #expect(!voulus.contains { $0.text.hasPrefix("Sujet : ") })
        #expect(!voulus.contains { $0.text.hasPrefix("Demande : ") })
    }

    @Test("La carte est étroite et centrée, sans rail ni bandeau")
    func largeurDeLaCarte() {
        // La capture 5b : une carte de ~940 px, seule à l'écran. La largeur est
        // une constante de la vue et non un jeton partagé : c'est le seul écran
        // de la refonte qui la porte.
        #expect(CollaboratorPrepView.cardMaxWidth == 940)
        #expect(CollaboratorPrepView.cardMaxWidth < One2OneToken.actionsRailWidth * 3)
    }

    // MARK: - Le crochet de recette

    @Test("Le code 5b ouvre l'entretien subi en mode Préparer")
    func codeDeRecette() {
        let ecran = RecetteScreen.from(environment: "5b")
        #expect(ecran == .collaboratorPreparation)
        #expect(ecran?.cible == .entretienSubi)
        #expect(ecran?.mode == .prepare)
    }
}
