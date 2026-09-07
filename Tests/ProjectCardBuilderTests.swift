import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// `ProjectCardBuilder` est la seule règle métier de la fiche projet : tout ce
/// que le panneau affiche en sort. Les valeurs testées ici sont celles de la
/// capture `3b-fiche-projet.png` et des seuils de la spec §4.3.
@Suite("Fiche projet — état d'affichage")
@MainActor
struct ProjectCardBuilderTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeProject(_ context: ModelContext,
                             status: String = "Yellow") -> Project {
        let projet = Project(code: "P25_110",
                             name: "S/D — Modernisation CI/CD",
                             domain: "S/D",
                             phase: "Réalisation",
                             status: status)
        context.insert(projet)
        return projet
    }

    // MARK: - Statut

    @Test("Green, Yellow et Red se traduisent en ok, watch et risk")
    func statusMapping() {
        #expect(ProjectCardStatus(projectStatus: "Green") == .ok)
        #expect(ProjectCardStatus(projectStatus: "Yellow") == .watch)
        #expect(ProjectCardStatus(projectStatus: "Red") == .risk)
        #expect(ProjectCardStatus.ok.projectStatusRaw == "Green")
        #expect(ProjectCardStatus.watch.projectStatusRaw == "Yellow")
        #expect(ProjectCardStatus.risk.projectStatusRaw == "Red")
        // L'ordre du menu à trois valeurs de la spec §4.3.
        #expect(ProjectCardStatus.allCases == [.ok, .watch, .risk])
        #expect(ProjectCardStatus.ok.label == "Sous contrôle")
        #expect(ProjectCardStatus.watch.label == "À surveiller")
        #expect(ProjectCardStatus.risk.label == "En risque")
    }

    /// `Unknown` n'est pas un quatrième statut du menu : la spec §4.3 en veut
    /// trois. Il s'affiche « À qualifier » et se replie sur `watch` — c'est le
    /// seul choix honnête, un projet non qualifié n'est ni sain ni en risque.
    @Test("Unknown se replie sur watch mais s'affiche « À qualifier »")
    func unknownStatusIsUnqualified() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context, status: "Unknown")
        let etat = ProjectCardBuilder.build(project: projet, meetings: [])

        #expect(ProjectCardStatus(projectStatus: "Unknown") == .watch)
        #expect(etat.status == .watch)
        #expect(etat.statusIsQualified == false)
        #expect(etat.statusLabel == "À qualifier")
    }

    @Test("Yellow s'affiche « À surveiller », comme sur la capture")
    func watchStatusLabel() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let etat = ProjectCardBuilder.build(project: projet, meetings: [])

        #expect(etat.status == .watch)
        #expect(etat.statusIsQualified)
        #expect(etat.statusLabel == "À surveiller")
        #expect(etat.reference == "P25_110")
        #expect(etat.name == "S/D — Modernisation CI/CD")
    }

    // MARK: - Budget

    /// Les trois seuils de la spec §4.3, aux bornes. Un ratio exactement à
    /// 70 % est déjà `warn` : la spec écrit « < 70 % ok », pas « ≤ ».
    @Test("La teinte du budget suit les seuils 70 % et 90 %")
    func budgetToneThresholds() {
        #expect(ProjectCardBuilder.tone(ratio: 0) == .ok)
        #expect(ProjectCardBuilder.tone(ratio: 0.699) == .ok)
        #expect(ProjectCardBuilder.tone(ratio: 0.7) == .warn)
        #expect(ProjectCardBuilder.tone(ratio: 0.899) == .warn)
        #expect(ProjectCardBuilder.tone(ratio: 0.9) == .report)
        #expect(ProjectCardBuilder.tone(ratio: 1.4) == .report)
    }

    /// Le budget de la capture. ⚠️ Écart connu et assumé : la maquette dessine
    /// la barre en orange alors que 40 000 / 61 000 = 65,6 %, donc `ok` selon
    /// la règle écrite deux fois dans la spec (« < 70 % ok »). C'est la règle
    /// qui est implémentée : elle est chiffrée, la teinte de la maquette ne
    /// l'est pas. Consigné dans `STATUS.md`.
    @Test("Le budget de la capture : 40 000 € / 61 000 €")
    func budgetOfCapture() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        projet.budgetCons = 40_000
        projet.budgetInit = 61_000
        let etat = ProjectCardBuilder.build(project: projet, meetings: [])

        let budget = try #require(etat.budget)
        #expect(budget.spent == 40_000)
        #expect(budget.total == 61_000)
        #expect(budget.tone == .ok)
        #expect(abs(budget.ratio - 40_000.0 / 61_000.0) < 0.0001)
        #expect(budget.text == "40\u{202F}000\u{00A0}€ / 61\u{202F}000\u{00A0}€")
    }

    /// Le formatage est écrit à la main, pas délégué à un `NumberFormatter` :
    /// la locale du poste ne doit pas décider de la présentation d'une fiche
    /// française — et un test qui dépend de la locale de la machine ne prouve
    /// rien.
    @Test("Les montants sont groupés à la française, espace fine insécable")
    func budgetTextFormatting() {
        #expect(ProjectCardBuilder.amountText(0) == "0\u{00A0}€")
        #expect(ProjectCardBuilder.amountText(999) == "999\u{00A0}€")
        #expect(ProjectCardBuilder.amountText(1_000) == "1\u{202F}000\u{00A0}€")
        #expect(ProjectCardBuilder.amountText(1_234_567) == "1\u{202F}234\u{202F}567\u{00A0}€")
        // Arrondi à l'euro : une fiche de pilotage n'affiche pas de centimes.
        #expect(ProjectCardBuilder.amountText(40_499.6) == "40\u{202F}500\u{00A0}€")
    }

    /// `budgetRev` est le budget révisé : quand il existe, c'est lui le total.
    @Test("Le total est le budget révisé quand il existe, l'initial sinon")
    func revisedBudgetWins() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        projet.budgetCons = 90_000
        projet.budgetInit = 61_000
        projet.budgetRev = 100_000
        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.budget?.total == 100_000)
        #expect(etat.budget?.tone == .report)               // 90 %
    }

    /// Sans total connu il n'y a pas de barre à dessiner : le panneau affiche
    /// une invite, pas une division par zéro.
    @Test("Sans total, ou avec un total nul, il n'y a pas de budget")
    func missingBudgetIsNil() throws {
        let context = ModelContext(try makeContainer())
        let sansRien = makeProject(context)
        #expect(ProjectCardBuilder.build(project: sansRien, meetings: []).budget == nil)

        let totalNul = makeProject(context)
        totalNul.budgetCons = 12_000
        totalNul.budgetInit = 0
        #expect(ProjectCardBuilder.build(project: totalNul, meetings: []).budget == nil)
    }

    /// Un dépassement ne casse pas la barre : le ratio est borné à 1 pour le
    /// dessin, mais la teinte reste `report` et le texte dit la vérité.
    @Test("Un budget dépassé borne la barre sans mentir sur les montants")
    func overspentBudgetIsClamped() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        projet.budgetCons = 80_000
        projet.budgetInit = 61_000
        let budget = try #require(ProjectCardBuilder.build(project: projet, meetings: []).budget)
        #expect(budget.ratio == 1)
        #expect(budget.tone == .report)
        #expect(budget.text == "80\u{202F}000\u{00A0}€ / 61\u{202F}000\u{00A0}€")
    }

    // MARK: - Jalons

    @Test("Un jalon en retard affiche « bloqué » et non sa date")
    func lateMilestoneIsBlocked() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let jalon = ProjectMilestone(label: "Migration Marine — chiffrage à valider",
                                     dueAt: Date(timeIntervalSince1970: 1_759_190_400),
                                     state: .late,
                                     order: 1)
        context.insert(jalon)
        jalon.project = projet

        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        let rendu = try #require(etat.milestones.first)
        #expect(rendu.isBlocked)
        #expect(rendu.trailingText == "bloqué")
        #expect(rendu.state == .late)
        #expect(rendu.label == "Migration Marine — chiffrage à valider")
    }

    @Test("Un jalon sans date n'affiche rien à droite")
    func undatedMilestoneHasNoTrailingText() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let jalon = ProjectMilestone(label: "Recette de bout en bout", state: .planned)
        context.insert(jalon)
        jalon.project = projet

        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.milestones.first?.trailingText.isEmpty == true)
        #expect(etat.milestones.first?.isBlocked == false)
    }

    /// SwiftData ne garantit pas l'ordre d'une relation : le tri est explicite,
    /// sinon la fiche se réordonne d'une ouverture à l'autre.
    @Test("Les jalons sortent triés par ordre manuel, puis par date")
    func milestonesAreSorted() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let tard = ProjectMilestone(label: "Tard", dueAt: Date(timeIntervalSince1970: 2_000_000), order: 1)
        let tot = ProjectMilestone(label: "Tôt", dueAt: Date(timeIntervalSince1970: 1_000_000), order: 1)
        let premier = ProjectMilestone(label: "Premier", dueAt: nil, order: 0)
        for jalon in [tard, tot, premier] {
            context.insert(jalon)
            jalon.project = projet
        }

        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.milestones.map(\.label) == ["Premier", "Tôt", "Tard"])
    }

    // MARK: - Risques, interlocuteurs, en-tête

    @Test("Les risques ouverts sortent du plus grave au plus faible")
    func risksAreSortedBySeverity() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        for (titre, gravite) in [("Faible", "Faible"), ("Critique", "Critique"), ("Élevé", "Élevé")] {
            let alerte = ProjectAlert(title: titre, severity: gravite)
            context.insert(alerte)
            alerte.project = projet
        }
        let resolue = ProjectAlert(title: "Réglé", severity: "Critique")
        resolue.isResolved = true
        context.insert(resolue)
        resolue.project = projet

        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.risks.map(\.title) == ["Critique", "Élevé", "Faible"])
        #expect(etat.risks.first?.level == .critique)
        #expect(etat.risks.count == 3)          // la résolue n'est pas un risque ouvert
    }

    @Test("Un interlocuteur s'écrit « nom — rôle »")
    func contactText() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let contact = ProjectContact(name: "Olivier Freund", role: "partenaire, décideur", order: 0)
        context.insert(contact)
        contact.project = projet
        let sansRole = ProjectContact(name: "Alexis / Jeff", role: "", order: 1)
        context.insert(sansRole)
        sansRole.project = projet

        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.contacts.map(\.text) == ["Olivier Freund — partenaire, décideur", "Alexis / Jeff"])
    }

    @Test("L'en-tête compte les réunions du projet, pas les autres")
    func meetingCountFiltersOnProject() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let autre = makeProject(context)
        autre.name = "Autre dossier"

        for _ in 0..<3 {
            let reunion = Meeting(title: "R", date: Date(), notes: "")
            context.insert(reunion)
            reunion.project = projet
        }
        let horsSujet = Meeting(title: "X", date: Date(), notes: "")
        context.insert(horsSujet)
        horsSujet.project = autre
        let sansProjet = Meeting(title: "Y", date: Date(), notes: "")
        context.insert(sansProjet)

        let toutes = try context.fetch(FetchDescriptor<Meeting>())
        let etat = ProjectCardBuilder.build(project: projet, meetings: toutes)
        #expect(etat.meetingCount == 3)
    }

    /// « dernière mise à jour aujourd'hui par vous » : le texte de la capture.
    /// L'auteur est toujours « vous », l'app étant mono-utilisateur.
    @Test("La ligne de mise à jour dit « aujourd'hui » le jour même")
    func lastUpdateTextSaysToday() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let maintenant = Date(timeIntervalSince1970: 1_757_000_000)
        let reunion = Meeting(title: "R", date: maintenant, notes: "")
        context.insert(reunion)
        reunion.project = projet

        let etat = ProjectCardBuilder.build(project: projet, meetings: [reunion], now: maintenant)
        #expect(etat.lastUpdateText == "dernière mise à jour aujourd'hui par vous")
    }

    @Test("La veille, elle dit « hier »")
    func lastUpdateTextSaysYesterday() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let maintenant = Date(timeIntervalSince1970: 1_757_000_000)
        let reunion = Meeting(title: "R", date: maintenant.addingTimeInterval(-86_400), notes: "")
        context.insert(reunion)
        reunion.project = projet

        let etat = ProjectCardBuilder.build(project: projet, meetings: [reunion], now: maintenant)
        #expect(etat.lastUpdateText == "dernière mise à jour hier par vous")
    }

    @Test("Sans réunion, la ligne de mise à jour ne prétend rien")
    func lastUpdateTextWithoutMeeting() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.lastUpdateText == "jamais mis à jour")
        #expect(etat.meetingCount == 0)
    }

    /// `build` est appelé depuis un `body` SwiftUI, plusieurs fois par rendu :
    /// il ne doit **rien** écrire. `ensuredStableID` backfille et enregistre le
    /// contexte — l'employer ici muterait le store pendant le calcul d'une vue.
    /// Le test le vérifie sur une ligne dont le `stableID` est `nil`, et
    /// s'assure au passage que l'identité rendue est stable d'un appel à
    /// l'autre (sinon `ForEach` recréerait ses vues à chaque image).
    @Test("Construire l'état d'affichage n'écrit rien dans le modèle")
    func buildHasNoSideEffect() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        let jalon = ProjectMilestone(label: "Sans identifiant stable", order: 0)
        context.insert(jalon)
        jalon.project = projet
        jalon.stableID = nil
        let contact = ProjectContact(name: "Sans identifiant", role: "x", order: 0)
        context.insert(contact)
        contact.project = projet
        contact.stableID = nil
        try context.save()

        let premier = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(jalon.stableID == nil, "build ne doit pas backfiller le stableID")
        #expect(contact.stableID == nil)
        #expect(context.hasChanges == false, "build ne doit rien écrire dans le contexte")

        let second = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(premier.milestones.map(\.id) == second.milestones.map(\.id))
        #expect(premier.contacts.map(\.id) == second.contacts.map(\.id))
    }

    @Test("Périmètre et tags sont repris tels quels")
    func scopeAndTags() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject(context)
        projet.scopeText = "Refonte de la chaîne CI/CD."
        projet.tags = ["GitLab", "Nexus", "PostgreSQL", "Cléva"]

        let etat = ProjectCardBuilder.build(project: projet, meetings: [])
        #expect(etat.scopeText == "Refonte de la chaîne CI/CD.")
        #expect(etat.tags == ["GitLab", "Nexus", "PostgreSQL", "Cléva"])
    }
}
