import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le jeu de démonstration de la capture 2a.
///
/// Même raison d'être qu'au lot 10 : ce test **vérifie l'arithmétique de la
/// maquette**. Un jeu de données qui ne tient pas les nombres ne se voit pas à
/// l'œil sur une capture d'écran — il se voit ici.
@Suite("Jeu de démonstration — l'écran de séance 1:1 (2a)")
@MainActor
struct RefonteDemoSeedLot11Tests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }

    private func semer() throws -> (thread: OneOnOneThread,
                                    meeting: Meeting,
                                    context: ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let seme = try #require(RefonteDemoSeed.seedLot11(in: context))
        return (seme.thread, seme.meeting, context)
    }

    // MARK: - Idempotence

    @Test("Semer deux fois ne duplique rien")
    func semerDeuxFois() throws {
        let (fil, seance, context) = try semer()
        let engagements = fil.commitments.count
        let sujets = fil.agendaItems.count
        let notes = seance.timedNotes.count
        let reunions = try context.fetch(FetchDescriptor<Meeting>()).count

        _ = RefonteDemoSeed.seedLot11(in: context)

        #expect(fil.commitments.count == engagements)
        #expect(fil.agendaItems.count == sujets)
        #expect(seance.timedNotes.count == notes)
        let reunionsApres = try context.fetch(FetchDescriptor<Meeting>()).count
        let reglages = try context.fetch(FetchDescriptor<AppSettings>()).count
        let actions4h = try context.fetch(FetchDescriptor<ActionTask>())
            .filter { $0.effortMinutes == 240 }.count
        #expect(reunionsApres == reunions)
        #expect(reglages == 1)
        #expect(actions4h == 1)
    }

    @Test("Les nombres du lot 10 ne bougent pas")
    func arithmetiqueDuLot10() throws {
        let (fil, _, _) = try semer()
        // Le lot 11 ajoute deux engagements **ouverts** : le taux de tenue,
        // qui ne compte que les soldés, est inchangé.
        #expect(CommitmentLedger.rateLabel(fil) == "8 tenus sur 11 · taux 73 %")
        #expect(CommitmentLedger.lateOnManagerSideLabel(fil, now: Self.maintenant)
                == "1 en retard côté manager")
        #expect(MoodTrend.deltaLabel(fil) == "↓ vs 21 août (Bien)")
    }

    // MARK: - Colonne gauche

    @Test("La carte personne affiche les trois lignes de la capture")
    func cartePersonne() throws {
        let (fil, _, _) = try semer()
        #expect(PersonCardModel.name(of: fil) == "Laurent NOMINÉ")
        #expect(PersonCardModel.roleLine(of: fil, now: Self.maintenant)
                == "Ingénieur CI/CD · dans l'équipe depuis 3 ans")
        #expect(PersonCardModel.lastMeetingLabel(of: fil, now: Self.maintenant)
                == "21 août · il y a 2 sem.")
        #expect(PersonCardModel.rhythmLabel(of: fil) == "Toutes les 2 sem.")
    }

    @Test("L'ordre du jour a quatre sujets, dont un barré avec sa cible")
    func ordreDuJour() throws {
        let (fil, seance, _) = try semer()
        let lignes = ManagerAgendaModel.rows(for: seance, in: fil,
                                             ownerName: RefonteDemoSeed.sessionOwnerName)
        #expect(lignes.count == 4)
        #expect(lignes.filter(\.isStruck).count == 1)
        #expect(lignes.last?.item.text == "Point objectifs S2")
        #expect(lignes.last?.isStruck == true)
        // Deux sujets ajoutés par Laurent, deux par moi : « co-construit ».
        #expect(lignes.map(\.initials).filter { $0 == "LN" }.count == 2)
        #expect(lignes.map(\.initials).filter { $0 == "YP" }.count == 2)
    }

    @Test("RESTÉ EN SUSPENS montre deux sujets récurrents jamais tranchés")
    func resteEnSuspens() throws {
        let (fil, seance, _) = try semer()
        let suspens = ManagerAgendaModel.pendingEntries(fil, for: seance, now: Self.maintenant)
        #expect(suspens.count == 2)
        #expect(suspens.allSatisfy { $0.isRecurringTopic })
        #expect(suspens.contains { $0.text == "Mobilité archi" })
        #expect(suspens.contains { $0.text == "Astreintes" })
        // Le sujet reporté est déjà barré dans l'ordre du jour, juste au-dessus.
        #expect(!suspens.contains { $0.text == "Point objectifs S2" })
    }

    // MARK: - Colonne centrale

    @Test("Les six notes de la capture se rangent dans les trois sections")
    func notesDeLaCapture() throws {
        let (_, seance, _) = try semer()
        // `02:40` sous `① COMMENT ÇA VA`.
        #expect(OneOnOneNoteSections.notes(seance, in: .howAreYou).map(\.t) == [160])
        // `06:15`, `13:02` et la note privée `17:30` sous `② SES SUJETS`.
        #expect(OneOnOneNoteSections.notes(seance, in: .topics).map(\.t) == [375, 782, 1_050])
        let privee = try #require(OneOnOneNoteSections.notes(seance, in: .topics)
                                    .first { $0.visibility == .private })
        #expect(privee.t == 1_050)
        #expect(privee.text.contains("Risque de départ"))
        // Les deux cartes de `③`, donc « 1:1 complet ».
        #expect(OneOnOneNoteSections.feedback(seance, .given).count == 1)
        #expect(OneOnOneNoteSections.feedback(seance, .received).count == 1)
        #expect(OneOnOneNoteSections.completenessLabel(seance) == "1:1 complet")
    }

    @Test("La durée de la séance est celle de la pilule audio : 31:07")
    func dureeDeLaSeance() throws {
        let (_, seance, _) = try semer()
        #expect(seance.durationSeconds == 1_867)
        #expect(MeetingPlayhead.mmss(Double(seance.durationSeconds)) == "31:07")
    }

    // MARK: - Colonne droite

    @Test("Les quatre cartes du rail, deux par côté, avec leurs pilules")
    func cartesDuRail() throws {
        let (fil, seance, _) = try semer()
        let groupes = CommitmentsRailModel.groups(for: seance, in: fil,
                                                  ownerName: RefonteDemoSeed.sessionOwnerName,
                                                  now: Self.maintenant)
        #expect(groupes.map(\.title) == ["Moi · 2", "Laurent · 2"])
        #expect(groupes.map(\.initials) == ["YP", "LN"])

        let arbitrage = try #require(groupes[0].commitments
            .first { $0.text == "Arbitrer renfort ou décalage du Webcast" })
        #expect(CommitmentsRailModel.duePill(arbitrage, now: Self.maintenant) == "Vendredi")
        #expect(CommitmentsRailModel.criticalityPill(arbitrage) == "Bloquant pour lui")

        let mobilite = try #require(groupes[0].commitments
            .first { $0.text == "Ouvrir le sujet mobilité archi avec Claire-Amélie" })
        #expect(CommitmentsRailModel.privacyPill(mobilite) == "● privé")
        #expect(CommitmentsRailModel.duePill(mobilite, now: Self.maintenant) == "30 sept.")

        let formation = try #require(groupes[1].commitments
            .first { $0.text == "Cadrer la formation Admin (plan + 2 dates)" })
        #expect(CommitmentsRailModel.duePill(formation, now: Self.maintenant) == "11 sept.")
        #expect(CommitmentsRailModel.effortPill(formation) == "4h")

        let chiffrage = try #require(groupes[1].commitments
            .first { $0.text == "Chiffrer la reprise AP restante" })
        // Le 9 septembre est dans la fenêtre de sept jours : il s'écrit en jour
        // de la semaine, comme dans le tableau de la préparation (2b).
        #expect(CommitmentsRailModel.duePill(chiffrage, now: Self.maintenant) == "Mercredi")
    }

    @Test("Les trois lignes de TENUS DEPUIS LE DERNIER 1:1")
    func lignesDuLedger() throws {
        let (fil, seance, _) = try semer()
        let lignes = CommitmentsRailModel.ledgerLines(
            for: seance, in: fil,
            ownerName: RefonteDemoSeed.sessionOwnerName, now: Self.maintenant)
        #expect(lignes.count == 3)

        // Le manqué en tête, en rouge, avec son compteur de reports — critère
        // chantier 2 n° 2 sur le jeu de la capture.
        #expect(lignes[0].symbol == "✗")
        #expect(lignes[0].text == "Retour sur la grille d'astreinte")
        #expect(lignes[0].initials == "YP")
        #expect(lignes[0].deferralLabel == "2× reporté")

        let tenus = lignes.dropFirst()
        #expect(tenus.allSatisfy { $0.symbol == "✓" })
        #expect(tenus.contains { $0.text == "Reprise du périmètre Nexus" && $0.initials == "LN" })
        #expect(tenus.contains { $0.text == "Accès environnement recette" && $0.initials == "YP" })
    }

    @Test("Le pied de clôture nomme Laurent, le 18 septembre et la ligne exclue")
    func cloture() throws {
        let (fil, seance, _) = try semer()
        #expect(CommitmentsRailModel.recapButtonLabel(for: fil) == "Envoyer le récap à Laurent")
        #expect(CommitmentsRailModel.planNextButtonLabel(for: fil, now: Self.maintenant)
                == "Planifier le prochain — 18 sept.")
        // Deux lignes privées dans le jeu de la capture : la note `17:30` et
        // l'engagement `● privé 30 sept.` — le compte porte sur **toutes** les
        // lignes que le récap laissera de côté, pas seulement les notes.
        #expect(CommitmentsRailModel.excludedLinesLabel(for: seance, in: fil)
                == "2 lignes privées seront exclues.")
    }

    // MARK: - Barre du haut

    @Test("Le fil d'Ariane de la capture se compose des quatre segments")
    func filDAriane() throws {
        let (_, seance, _) = try semer()
        #expect(MeetingTopChromeBar.teamSegmentLabel(for: seance.kind) == "Mon équipe")
        #expect(MeetingTopChromeBar.typeBadge(for: seance.kind) == "1:1")
        #expect(MeetingTopChromeBar.titlePlaceholder(for: seance)
                == "Laurent NOMINÉ — entretien du 4 septembre")
        #expect(MeetingTopChromeBar.privacyPillLabel(for: seance.kind) == "● Privé — vous deux")
        #expect(MeetingTopChromeBar.reportBaseLabel(for: seance.kind) == "Rapport 1:1")
    }
}
