import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// `CE QUE J'AI LIVRÉ` (spec §6.2 : « généré automatiquement depuis les
/// `Action` closes et les réunions où l'utilisateur a un rôle actif, depuis la
/// date du 1:1 précédent »), et le critère chantier 5 n° 3 : « la liste se
/// remplit **sans saisie manuelle** et se cite en un clic ».
///
/// La règle retenue pour « mes » actions est `destinataire == .moi` : l'utilisateur
/// de l'application n'est pas un `Collaborator`, il n'a pas de fiche d'annuaire,
/// donc `Collaborator.assignedTasks` ne le concerne jamais. `ActionAudience.moi`
/// est le défaut du modèle et la seule désignation de l'utilisateur qui existe.
@Suite("Ce que j'ai livré — DeliveredItemsBuilder (spec §6.2)")
@MainActor
struct DeliveredItemsBuilderTests {

    /// Vendredi 4 septembre 2026, 9 h 15 — la séance de la capture 5a.
    static let seance = Date(timeIntervalSince1970: 1_788_506_100)
    /// Le 1:1 précédent du fil : quinze jours plus tôt, le 21 août.
    static let precedente = seance.addingTimeInterval(-14 * 86_400)

    private static func jours(_ n: Double) -> Date {
        seance.addingTimeInterval(n * 86_400)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Une action close, adressée à moi.
    private func actionClose(_ titre: String,
                             le date: Date,
                             charge: Int? = nil,
                             in context: ModelContext) -> ActionTask {
        let action = ActionTask(title: titre)
        action.destinataire = .moi
        action.isCompleted = true
        action.completedAt = date
        action.effortMinutes = charge
        context.insert(action)
        return action
    }

    // MARK: - Actions closes

    @Test("Une action close dans la fenêtre est reprise avec sa date et sa charge")
    func actionCloseReprise() throws {
        let context = try makeContext()
        let action = actionClose("Reprise du périmètre Nexus",
                                 le: Self.jours(-6), charge: 960, in: context)
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                                 since: Self.precedente, now: Self.seance)
        #expect(lignes.count == 1)
        let ligne = try #require(lignes.first)
        #expect(ligne.symbol == "✓")
        #expect(ligne.status == .delivered)
        #expect(ligne.text == "Reprise du périmètre Nexus")
        #expect(ligne.detail == "Action close le 29 août · 2 j")
    }

    @Test("Une action close sans charge n'affiche pas de charge inventée")
    func actionSansCharge() throws {
        let context = try makeContext()
        let action = actionClose("Base PostgreSQL dédiée préparée",
                                 le: Self.jours(-2), in: context)
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                                 since: Self.precedente, now: Self.seance)
        #expect(lignes.first?.detail == "Action close le 2 sept.")
    }

    @Test("Une action close avant le 1:1 précédent est écartée")
    func actionTropAncienne() throws {
        let context = try makeContext()
        let action = actionClose("Vieux livrable", le: Self.jours(-40), in: context)
        try context.save()

        #expect(DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                            since: Self.precedente,
                                            now: Self.seance).isEmpty)
    }

    @Test("Une action close après la séance est écartée : la séance est l'instant de référence")
    func actionDansLeFutur() throws {
        let context = try makeContext()
        let action = actionClose("Livrable à venir", le: Self.jours(3), in: context)
        try context.save()

        #expect(DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                            since: Self.precedente,
                                            now: Self.seance).isEmpty)
    }

    @Test("Une action déléguée à un collaborateur n'est pas un de mes livrables")
    func actionDeleguee() throws {
        let context = try makeContext()
        let action = actionClose("Chiffrage délégué", le: Self.jours(-3), in: context)
        action.destinataire = .collaborateur
        try context.save()

        #expect(DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                            since: Self.precedente,
                                            now: Self.seance).isEmpty)
    }

    @Test("Sans 1:1 précédent, tout ce qui est clos jusqu'à la séance remonte")
    func premiereSeanceDuFil() throws {
        let context = try makeContext()
        let ancienne = actionClose("Livrable d'avant", le: Self.jours(-120), in: context)
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [ancienne], meetings: [],
                                                 since: nil, now: Self.seance)
        #expect(lignes.count == 1)
    }

    // MARK: - Réunions à rôle actif

    @Test("Une réunion portant une décision compte comme un livrable")
    func reunionAvecDecision() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Présentation COSUI — risques Jenkins",
                              date: Self.jours(-3), notes: "")
        reunion.kind = .project
        context.insert(reunion)
        let decision = MeetingNote(t: 120, text: "Jenkins reste en place jusqu'en janvier",
                                   kind: .decision)
        context.insert(decision)
        decision.meeting = reunion
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [], meetings: [reunion],
                                                 since: Self.precedente, now: Self.seance)
        let ligne = try #require(lignes.first)
        #expect(ligne.text == "Présentation COSUI — risques Jenkins")
        #expect(ligne.detail == "Réunion du 1er sept. · a débloqué la décision")
        // La chaîne de citation vise la note qui a justifié le rôle actif :
        // c'est elle qui est adressable, pas la réunion entière.
        #expect(ligne.reference?.kind == .note)
        #expect(ligne.reference?.stableID == decision.ensuredStableID)
    }

    @Test("Une réunion où je n'ai qu'écrit des notes compte aussi, avec un détail plus sobre")
    func reunionAvecNotes() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Atelier de cadrage", date: Self.jours(-4), notes: "")
        reunion.kind = .work
        context.insert(reunion)
        let note = MeetingNote(t: 60, text: "Périmètre arrêté à trois lots",
                               authorSide: .me)
        context.insert(note)
        note.meeting = reunion
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [], meetings: [reunion],
                                                 since: Self.precedente, now: Self.seance)
        #expect(lignes.first?.detail == "Réunion du 31 août · notes prises")
    }

    @Test("Une réunion muette n'est pas un livrable")
    func reunionMuette() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Point d'équipe", date: Self.jours(-5), notes: "")
        reunion.kind = .work
        context.insert(reunion)
        try context.save()

        #expect(DeliveredItemsBuilder.build(actions: [], meetings: [reunion],
                                            since: Self.precedente,
                                            now: Self.seance).isEmpty)
    }

    @Test("Un tête-à-tête n'est jamais un livrable, même s'il porte une décision")
    func teteATeteEcarte() throws {
        let context = try makeContext()
        for kind in [MeetingKind.oneToOne, .manager] {
            let seance = Meeting(title: "1:1 avec Yann · 4", date: Self.jours(-1), notes: "")
            seance.kind = kind
            context.insert(seance)
            let decision = MeetingNote(t: 0, text: "Décision d'entretien", kind: .decision)
            context.insert(decision)
            decision.meeting = seance
            try context.save()

            #expect(DeliveredItemsBuilder.build(actions: [], meetings: [seance],
                                                since: Self.precedente,
                                                now: Self.seance).isEmpty)
        }
    }

    // MARK: - Actions bloquées

    @Test("Une action ouverte et reportée remonte en `bloqué`, avec le nombre de reports")
    func actionReportee() throws {
        let context = try makeContext()
        let action = ActionTask(title: "Tests de clustering en recette")
        action.destinataire = .moi
        action.deferralCount = 2
        context.insert(action)
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                                 since: Self.precedente, now: Self.seance)
        let ligne = try #require(lignes.first)
        #expect(ligne.symbol == "◐")
        #expect(ligne.status == .blocked)
        #expect(ligne.detail == "En cours · reporté 2 fois")
    }

    @Test("Un commentaire de blocage donne la cause, telle qu'elle est écrite")
    func actionBloqueeAvecCause() throws {
        let context = try makeContext()
        let action = ActionTask(title: "Tests de clustering en recette")
        action.destinataire = .moi
        context.insert(action)
        let commentaire = ActionComment(text: "Bloqué par les comptes GitLab",
                                        date: Self.jours(-2))
        context.insert(commentaire)
        commentaire.task = action
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                                 since: Self.precedente, now: Self.seance)
        #expect(lignes.first?.detail == "En cours · bloqué par les comptes GitLab")
        #expect(lignes.first?.status == .blocked)
    }

    @Test("Une action ouverte que rien ne bloque ne remonte pas : ce n'est pas un livrable")
    func actionOuverteNonBloquee() throws {
        let context = try makeContext()
        let action = ActionTask(title: "Chantier en cours")
        action.destinataire = .moi
        context.insert(action)
        try context.save()

        #expect(DeliveredItemsBuilder.build(actions: [action], meetings: [],
                                            since: Self.precedente,
                                            now: Self.seance).isEmpty)
    }

    // MARK: - Tri

    @Test("Les livrés d'abord, du plus ancien au plus récent, les bloqués en dernier")
    func tri() throws {
        let context = try makeContext()
        let deux = actionClose("Base PostgreSQL dédiée préparée",
                               le: Self.jours(-2), in: context)
        let vingtNeuf = actionClose("Reprise du périmètre Nexus",
                                    le: Self.jours(-6), charge: 960, in: context)
        let bloquee = ActionTask(title: "Tests de clustering en recette")
        bloquee.destinataire = .moi
        bloquee.deferralCount = 1
        context.insert(bloquee)

        let reunion = Meeting(title: "Présentation COSUI — risques Jenkins",
                              date: Self.jours(-3), notes: "")
        reunion.kind = .project
        context.insert(reunion)
        let decision = MeetingNote(t: 0, text: "Jenkins reste en place", kind: .decision)
        context.insert(decision)
        decision.meeting = reunion
        try context.save()

        let lignes = DeliveredItemsBuilder.build(actions: [deux, vingtNeuf, bloquee],
                                                 meetings: [reunion],
                                                 since: Self.precedente, now: Self.seance)
        #expect(lignes.map(\.text) == ["Reprise du périmètre Nexus",
                                       "Présentation COSUI — risques Jenkins",
                                       "Base PostgreSQL dédiée préparée",
                                       "Tests de clustering en recette"])
    }

    // MARK: - Intitulés

    @Test("`auto · depuis le 21 août` : l'en-tête dit d'où vient la liste")
    func enTete() {
        #expect(DeliveredItemsBuilder.title == "CE QUE J'AI LIVRÉ")
        #expect(DeliveredItemsBuilder.autoBadge == "auto")
        #expect(DeliveredItemsBuilder.sinceLabel(Self.precedente) == "depuis le 21 août")
        // Première séance du fil : il n'y a pas de borne à annoncer, et une
        // date inventée serait un mensonge sur l'étendue de la liste.
        #expect(DeliveredItemsBuilder.sinceLabel(nil) == "depuis le début du fil")
    }

    @Test("La charge s'écrit en jours au-delà d'une journée de travail")
    func charges() {
        #expect(DeliveredItemsBuilder.effortLabel(minutes: nil) == nil)
        #expect(DeliveredItemsBuilder.effortLabel(minutes: 0) == nil)
        #expect(DeliveredItemsBuilder.effortLabel(minutes: 30) == "30min")
        #expect(DeliveredItemsBuilder.effortLabel(minutes: 240) == "4h")
        #expect(DeliveredItemsBuilder.effortLabel(minutes: 270) == "4h30")
        #expect(DeliveredItemsBuilder.effortLabel(minutes: 480) == "1 j")
        #expect(DeliveredItemsBuilder.effortLabel(minutes: 960) == "2 j")
    }

    @Test("Une liste vide propose une invite, jamais un vide muet")
    func invite() {
        #expect(!DeliveredItemsBuilder.emptyInvite.isEmpty)
        #expect(DeliveredItemsBuilder.quoteButtonLabel == "Citer")
    }

    // MARK: - Citer (critère n° 3)

    @Test("`Citer` produit le texte de la preuve, ligne et provenance réunies")
    func texteDeLaPreuve() throws {
        let context = try makeContext()
        let action = actionClose("Reprise du périmètre Nexus",
                                 le: Self.jours(-6), charge: 960, in: context)
        try context.save()

        let ligne = try #require(DeliveredItemsBuilder
            .build(actions: [action], meetings: [],
                   since: Self.precedente, now: Self.seance).first)
        #expect(DeliveredItemsBuilder.quoteText(ligne)
                == "Reprise du périmètre Nexus — Action close le 29 août · 2 j")
    }

    @Test("Une action née d'une phrase transmet sa chaîne de citation à la preuve")
    func chaineDeCitationPropagee() throws {
        let context = try makeContext()
        let action = actionClose("Reprise du périmètre Nexus",
                                 le: Self.jours(-6), in: context)
        let origine = SourceRef(kind: .transcript, stableID: UUID(), t: 412)
        action.sourceRef = origine
        try context.save()

        let ligne = try #require(DeliveredItemsBuilder
            .build(actions: [action], meetings: [],
                   since: Self.precedente, now: Self.seance).first)
        // La preuve ne s'invente pas une source : elle cite celle de l'action.
        #expect(ligne.reference == origine)
    }
}
