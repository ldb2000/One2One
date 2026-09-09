import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// L'onglet « Pilotage » de l'écran projet (capture
/// `1d-ecran-projet-pilotage.png`), testé **sur le semis de démonstration** —
/// c'est ce store-là que la recette `p1d` photographie.
///
/// Chaque chiffre et chaque libellé de la capture est interrogé : les quatre
/// tuiles, les quatre lignes d'actions dans leur ordre, les trois réunions,
/// les deux mails, l'invite de rattachement, les trois interlocuteurs, les
/// cinq lignes d'identité et l'alerte de deadline. Un onglet juste sur un
/// projet fabriqué mais faux sur `P25_193` ne vaudrait rien.
@Suite("Écran projet — onglet Pilotage")
@MainActor
struct ProjectPilotageBuilderTests {

    // MARK: - Outillage

    private func contexteEnMemoire() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    /// Le semis complet, et l'état du projet de la capture 1d.
    private func semis(today: Date = Date())
        throws -> (contexte: ModelContext, projet: Project, etat: ProjectPilotageState) {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let projet = try #require(projets.first {
            $0.stableID == RefonteDemoSeed.portfolioFocusProjectStableID
        })
        let etat = ProjectPilotageBuilder.build(
            project: projet,
            meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
            suggestions: try contexte.fetch(FetchDescriptor<MailIndexSuggestion>()),
            today: today
        )
        return (contexte, projet, etat)
    }

    /// Un projet nu, pour les cas limites qu'aucun projet du semis ne porte.
    private func projetNu(_ contexte: ModelContext, code: String = "T_001") -> Project {
        let p = Project(code: code, name: "Projet d'essai", domain: "",
                        phase: "Build", status: "Green")
        contexte.insert(p)
        return p
    }

    private func midi(_ decale: Int) -> Date {
        let calendrier = Calendar.current
        let midi = calendrier.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        return calendrier.date(byAdding: .day, value: decale, to: midi) ?? midi
    }

    // MARK: - Tuile « ACTIONS OUVERTES »

    @Test("Six actions ouvertes dont deux en retard, comme la capture")
    func tuileDesActions() throws {
        let semis = try semis()
        #expect(semis.etat.openActions == 6)
        #expect(semis.etat.lateActions == 2)
    }

    @Test("Une action terminée ou abandonnée ne compte pas")
    func actionsFermees() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        for (titre, statut) in [("Ouverte", ActionStatus.open),
                                ("Faite", .done),
                                ("Abandonnée", .dropped)] {
            let tache = ActionTask(title: titre)
            tache.status = statut
            tache.dueDate = midi(-2)
            contexte.insert(tache)
            tache.project = projet
        }
        let etat = ProjectPilotageBuilder.build(project: projet, meetings: [],
                                                suggestions: [], today: Date())
        #expect(etat.openActions == 1)
        #expect(etat.lateActions == 1)
    }

    /// Comparaison au **début du jour** : une action due aujourd'hui à midi
    /// n'est pas en retard à quinze heures.
    @Test("Une action due aujourd'hui n'est pas en retard")
    func retardAuDebutDuJour() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        let tache = ActionTask(title: "Due aujourd'hui")
        tache.dueDate = midi(0)
        contexte.insert(tache)
        tache.project = projet
        let debut = Calendar.current.startOfDay(for: Date())
        #expect(!ProjectPilotageBuilder.estEnRetard(tache, debutDuJour: debut))
        tache.dueDate = midi(-1)
        #expect(ProjectPilotageBuilder.estEnRetard(tache, debutDuJour: debut))
        tache.dueDate = nil
        #expect(!ProjectPilotageBuilder.estEnRetard(tache, debutDuJour: debut))
    }

    // MARK: - Tuile « DERNIÈRE RÉUNION »

    @Test("La dernière réunion est « hier », « COPIL · 45 min »")
    func tuileDeLaDerniereReunion() throws {
        let semis = try semis()
        let derniere = try #require(semis.etat.lastMeeting)
        #expect(derniere.label == "hier")
        #expect(derniere.kindLine == "COPIL · 45 min")
    }

    @Test("Sans durée connue, la ligne de type se réduit au type")
    func ligneDeTypeSansDuree() throws {
        let contexte = try contexteEnMemoire()
        let reunion = Meeting(title: "Atelier de cadrage", date: Date(), notes: "")
        reunion.kind = .workshop
        contexte.insert(reunion)
        #expect(ProjectPilotageBuilder.ligneDeType(reunion) == "Atelier")
        reunion.meetingDurationSeconds = 30 * 60
        #expect(ProjectPilotageBuilder.ligneDeType(reunion) == "Atelier · 30 min")
    }

    @Test("Sans badge, la ligne de type porte le libellé du kind")
    func ligneDeTypeSansBadge() throws {
        let contexte = try contexteEnMemoire()
        let reunion = Meeting(title: "Point hebdomadaire", date: Date(), notes: "")
        reunion.kind = .project
        contexte.insert(reunion)
        #expect(ProjectPilotageBuilder.ligneDeType(reunion) == "Projet")
    }

    @Test("Un projet sans réunion n'a pas de tuile de dernière réunion")
    func aucuneReunion() throws {
        let contexte = try contexteEnMemoire()
        let etat = ProjectPilotageBuilder.build(project: projetNu(contexte), meetings: [],
                                                suggestions: [], today: Date())
        #expect(etat.lastMeeting == nil)
        #expect(etat.rhythm == [0, 0, 0, 0, 0, 0, 0, 0])
        #expect(etat.rhythmLabel == "0 réunions / 12 sem.")
    }

    /// Une note n'est pas une réunion tenue, une réunion planifiée n'est pas
    /// la dernière : les deux règles du dépôt, vérifiées ici parce que la
    /// tuile les rendrait fausses en silence.
    @Test("Ni les notes ni les réunions à venir ne comptent")
    func notesEtReunionsAVenir() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        for (titre, kind, jours) in [("Note d'hier", MeetingKind.note, -1),
                                     ("Réunion de demain", .project, 1),
                                     ("Réunion d'avant-hier", .project, -2)] {
            let m = Meeting(title: titre, date: midi(jours), notes: "")
            m.kind = kind
            contexte.insert(m)
            m.project = projet
        }
        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())
        let etat = ProjectPilotageBuilder.build(project: projet, meetings: reunions,
                                                suggestions: [], today: Date())
        #expect(etat.lastMeeting?.label == "il y a 2 j")
        #expect(etat.meetings.count == 1)
        #expect(etat.meetings.first?.titre == "Réunion d'avant-hier")
    }

    // MARK: - Tuile « RYTHME »

    @Test("Huit barres, neuf réunions sur douze semaines")
    func tuileDuRythme() throws {
        let semis = try semis()
        #expect(semis.etat.rhythm.count == ProjectPilotageBuilder.rhythmBars)
        #expect(semis.etat.rhythm.count == 8)
        #expect(semis.etat.rhythm.reduce(0, +) == 9)
        #expect(semis.etat.rhythmLabel == "9 réunions / 12 sem.")
        // La barre la plus à droite est la plus récente : deux réunions y
        // tombent (hier et il y a huit jours).
        #expect(semis.etat.rhythm.last == 2)
    }

    @Test("Une réunion plus vieille que douze semaines n'est comptée nulle part")
    func rythmeHorsFenetre() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        for jours in [-1, -85, -200] {
            let m = Meeting(title: "R\(jours)", date: midi(jours), notes: "")
            m.kind = .project
            contexte.insert(m)
            m.project = projet
        }
        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())
        let etat = ProjectPilotageBuilder.build(project: projet, meetings: reunions,
                                                suggestions: [], today: Date())
        #expect(etat.rhythm.reduce(0, +) == 1)
        #expect(etat.rhythmLabel == "1 réunion / 12 sem.")
    }

    @Test("L'accord du libellé de rythme suit le nombre")
    func accordDuRythme() {
        #expect(ProjectPilotageBuilder.libelleDuRythme(0) == "0 réunions / 12 sem.")
        #expect(ProjectPilotageBuilder.libelleDuRythme(1) == "1 réunion / 12 sem.")
        #expect(ProjectPilotageBuilder.libelleDuRythme(9) == "9 réunions / 12 sem.")
    }

    // MARK: - Tuile « CHARGE »

    @Test("La charge est 48 / 60 j, barre aux quatre cinquièmes")
    func tuileDeLaCharge() throws {
        let semis = try semis()
        #expect(semis.etat.charge.spentLabel == "48")
        #expect(semis.etat.charge.plannedLabel == "/ 60 j")
        #expect(semis.etat.charge.ratio == 0.8)
        #expect(!semis.etat.charge.estVide)
    }

    @Test("Sans budget ni jours, la charge est vide ; un dépassement borne la barre")
    func chargeLimites() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        #expect(ProjectPilotageBuilder.charge(of: projet).estVide)
        #expect(ProjectPilotageBuilder.charge(of: projet).ratio == nil)

        projet.plannedDays = 10
        projet.budgetCons = 14
        #expect(ProjectPilotageBuilder.charge(of: projet).ratio == 1)
        #expect(ProjectPilotageBuilder.charge(of: projet).spentLabel == "14")

        projet.plannedDays = 0
        #expect(ProjectPilotageBuilder.charge(of: projet).ratio == nil)
    }

    @Test("Un nombre entier de jours s'écrit sans décimale")
    func formatDesNombres() {
        #expect(ProjectPilotageBuilder.nombre(48) == "48")
        #expect(ProjectPilotageBuilder.nombre(60.0) == "60")
        #expect(ProjectPilotageBuilder.nombre(12.5) == "12,5")
    }

    // MARK: - Carte « ACTIONS EN COURS »

    /// Les quatre lignes de la capture, dans son ordre : les deux retards, du
    /// plus ancien au plus récent, puis les deux suivantes dans l'ordre de la
    /// liste — « Planifier l'atelier sécurité », sans échéance, passe devant
    /// deux actions datées de la semaine suivante.
    @Test("Quatre actions, les retards d'abord, dans l'ordre de la capture")
    func carteDesActions() throws {
        let semis = try semis()
        #expect(semis.etat.actions.count == ProjectPilotageBuilder.maxActions)
        #expect(semis.etat.actions.map(\.title) == [
            "Valider le périmètre IO avec l’ALP",
            "Chiffrer la reprise de données",
            "Rédiger le DAT",
            "Planifier l’atelier sécurité",
        ])
        #expect(semis.etat.actions.map(\.echeanceLabel) == [
            "retard 3 j", "retard 1 j",
            ProjectPilotageBuilder.jourEtMois(Date().addingTimeInterval(5 * 86_400)),
            "—",
        ])
        #expect(semis.etat.actions.map(\.enRetard) == [true, true, false, false])
    }

    @Test("La sous-ligne d'une action porte le porteur et l'origine")
    func sousLignesDesActions() throws {
        let semis = try semis()
        let attendu = "issue du COPIL du "
            + ProjectPilotageBuilder.jourEtMois(Date().addingTimeInterval(-86_400))
        #expect(semis.etat.actions[0].sousLigne == "RIGAUT Manuel · \(attendu)")
        #expect(semis.etat.actions[1].sousLigne == "PENVEN Yann")
        #expect(semis.etat.actions[2].sousLigne == "THEDREZ Wilfried")
        #expect(semis.etat.actions[3].sousLigne == ProjectPeople.nonAffecte)
    }

    /// Une action née d'une réunion **sans badge** n'affiche pas d'origine :
    /// « issue de la réunion projet du 08/09 » n'apprend rien sur un écran qui
    /// ne montre que les réunions de ce projet.
    @Test("Sans badge sur la réunion d'origine, l'action n'affiche pas d'origine")
    func origineSansBadge() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        let reunion = Meeting(title: "Point hebdomadaire", date: midi(-2), notes: "")
        reunion.kind = .project
        contexte.insert(reunion)
        reunion.project = projet
        let tache = ActionTask(title: "Suivre")
        contexte.insert(tache)
        tache.project = projet
        #expect(ProjectPilotageBuilder.origine(de: tache) == nil)
        tache.meeting = reunion
        #expect(ProjectPilotageBuilder.origine(de: tache) == nil)
        reunion.kind = .workshop
        #expect(ProjectPilotageBuilder.origine(de: tache)
                == "issue du Atelier du \(ProjectPilotageBuilder.jourEtMois(midi(-2)))")
    }

    @Test("L'échéance se lit en retard, en date ou en tiret")
    func libellesDEcheance() throws {
        let contexte = try contexteEnMemoire()
        let tache = ActionTask(title: "T")
        contexte.insert(tache)
        let debut = Calendar.current.startOfDay(for: Date())
        #expect(ProjectPilotageBuilder.echeance(de: tache, debutDuJour: debut) == .aucune)
        tache.dueDate = midi(-3)
        #expect(ProjectPilotageBuilder.echeance(de: tache, debutDuJour: debut) == .retard(3))
        tache.dueDate = midi(0)
        #expect(ProjectPilotageBuilder.echeance(de: tache, debutDuJour: debut)
                == .date(ProjectPilotageBuilder.jourEtMois(midi(0))))
    }

    // MARK: - Carte « DERNIÈRES RÉUNIONS »

    @Test("Trois réunions, badgées, de la plus récente à la plus ancienne")
    func carteDesReunions() throws {
        let semis = try semis()
        #expect(semis.etat.meetings.count == ProjectPilotageBuilder.maxMeetings)
        #expect(semis.etat.meetings.map(\.titre) == [
            "Arbitrage périmètre IO",
            "Cadrage technique avec l’ALP",
            "Point d’avancement — PENVEN Yann",
        ])
        #expect(semis.etat.meetings.map(\.badge) == [.copil, .atelier, .oneOnOne])
        #expect(semis.etat.meetings.map(\.dateLabel) == [
            ProjectPilotageBuilder.jourEtMois(midi(-1)),
            ProjectPilotageBuilder.jourEtMois(midi(-8)),
            ProjectPilotageBuilder.jourEtMois(midi(-19)),
        ])
    }

    /// La carte s'appelle « résumé de décision » : la première décision prime
    /// sur le résumé court, et le résumé court sert de repli.
    @Test("Le résumé d'une réunion est sa première décision, à défaut son résumé court")
    func resumeDeDecision() throws {
        let semis = try semis()
        #expect(semis.etat.meetings[0].resume == "Le lot « annuaire » sort du périmètre v1")
        #expect(semis.etat.meetings[1].resume
                == "Choix d’architecture retenu : passerelle IO mutualisée.")
        #expect(semis.etat.meetings[2].resume.isEmpty)
    }

    // MARK: - Carte « PÉRIMÈTRE & CONTEXTE »

    @Test("Le périmètre est celui du semis et son pied invite à éditer")
    func cartePerimetre() throws {
        let semis = try semis()
        #expect(semis.etat.scopeText.hasPrefix("Reprise des services IO"))
        #expect(semis.etat.scopeFooter == "Cliquer pour éditer")

        semis.projet.scopeUpdatedAt = midi(-1)
        #expect(ProjectPilotageBuilder.piedDuPerimetre(semis.projet, today: Date())
                == "Cliquer pour éditer · dernière mise à jour hier")
    }

    // MARK: - Mails

    @Test("Deux mails liés, trois suggestions à rattacher")
    func mails() throws {
        let semis = try semis()
        #expect(semis.etat.mailCount == 2)
        #expect(semis.etat.mails.map(\.sujet)
                == ["RE : périmètre v1 — annuaire", "Planning atelier sécurité"])
        #expect(semis.etat.mails[0].sousLigne == "ALP · hier")
        #expect(semis.etat.mails[1].sousLigne
                == "THEDREZ W. · \(ProjectPilotageBuilder.jourEtMois(midi(-5)))")
        #expect(semis.etat.pendingMailSuggestions == 3)
        #expect(semis.etat.pendingMailLabel == "3 mails à rattacher à ce projet")
    }

    @Test("Une suggestion qui vise un autre projet ne compte pas")
    func suggestionsDUnAutreProjet() throws {
        let semis = try semis()
        let autres = try semis.contexte.fetch(FetchDescriptor<Project>())
            .filter { $0.persistentModelID != semis.projet.persistentModelID }
        let suggestion = MailIndexSuggestion(messageId: "x", accountName: "A", mailbox: "B",
                                             subject: "S", sender: "e@f.example",
                                             dateReceived: Date())
        semis.contexte.insert(suggestion)
        suggestion.suggestedProject = autres.first
        let etat = ProjectPilotageBuilder.build(
            project: semis.projet,
            meetings: try semis.contexte.fetch(FetchDescriptor<Meeting>()),
            suggestions: try semis.contexte.fetch(FetchDescriptor<MailIndexSuggestion>()),
            today: Date())
        #expect(etat.pendingMailSuggestions == 3)
    }

    @Test("L'expéditeur est abrégé : le domaine d'une adresse, l'initiale d'un prénom")
    func abreviationDeLExpediteur() {
        #expect(ProjectPilotageBuilder.expediteurAbrege("contact@alp.example") == "ALP")
        #expect(ProjectPilotageBuilder.expediteurAbrege("THEDREZ Wilfried") == "THEDREZ W.")
        #expect(ProjectPilotageBuilder.expediteurAbrege("Marie Claire Dupont") == "Marie C. D.")
        #expect(ProjectPilotageBuilder.expediteurAbrege("ALP") == "ALP")
        #expect(ProjectPilotageBuilder.expediteurAbrege("  ") == "—")
    }

    @Test("La date d'un mail est relative jusqu'à hier, datée au-delà")
    func dateDeMail() {
        #expect(ProjectPilotageBuilder.dateDeMail(midi(0), today: Date()) == "aujourd'hui")
        #expect(ProjectPilotageBuilder.dateDeMail(midi(-1), today: Date()) == "hier")
        #expect(ProjectPilotageBuilder.dateDeMail(midi(-5), today: Date())
                == ProjectPilotageBuilder.jourEtMois(midi(-5)))
    }

    @Test("L'invite de rattachement s'accorde et disparaît à zéro")
    func inviteDeRattachement() {
        #expect(ProjectPilotageBuilder.libelleDesSuggestions(0) == nil)
        #expect(ProjectPilotageBuilder.libelleDesSuggestions(1) == "1 mail à rattacher à ce projet")
        #expect(ProjectPilotageBuilder.libelleDesSuggestions(3) == "3 mails à rattacher à ce projet")
    }

    // MARK: - Carte « INTERLOCUTEURS »

    /// Décision **D3** : la relation fait foi. Le sponsor de `P25_193` est
    /// vide, la ligne passe en pointillés.
    @Test("Trois interlocuteurs : chef, architecte, et un sponsor à renseigner")
    func interlocuteurs() throws {
        let semis = try semis()
        #expect(semis.etat.people.map(\.role)
                == ["Chef de projet", "Architecte technique", "Sponsor"])
        #expect(semis.etat.people[0].nom == "RIGAUT Manuel")
        #expect(semis.etat.people[1].nom == "THEDREZ Wilfried")
        #expect(semis.etat.people[2].nom == "Sponsor à renseigner")
        #expect(semis.etat.people[2].aRenseigner)
        #expect(!semis.etat.people[0].aRenseigner)
        // Le raccourci « 1:1 ▸ » n'existe que si un collaborateur est lié.
        #expect(semis.etat.people[0].collaboratorID != nil)
        #expect(semis.etat.people[1].collaboratorID != nil)
        #expect(semis.etat.people[2].collaboratorID == nil)
    }

    /// D3 encore : un nom dans la colonne libre du xlsx ne suffit pas.
    @Test("Un chef de projet non lié reste à renseigner")
    func chefNonLie() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        projet.chefDeProjet = "NOMINE Laurent"
        let lignes = ProjectPilotageBuilder.interlocuteurs(of: projet)
        #expect(lignes[0].nom == "Chef de projet à renseigner")
        #expect(lignes[0].aRenseigner)
    }

    // MARK: - Carte « RISQUE »

    @Test("Le risque est modéré, avec la description du semis")
    func risque() throws {
        let semis = try semis()
        #expect(semis.etat.risk == .modere)
        #expect(semis.etat.riskRaw == "Modéré")
        #expect(semis.etat.riskDescription.hasPrefix("Disponibilité de l’équipe ALP"))
    }

    @Test("Une valeur de risque hors table reste lisible, sans niveau")
    func risqueHorsTable() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        projet.riskLevel = "Majeur"
        let etat = ProjectPilotageBuilder.build(project: projet, meetings: [],
                                                suggestions: [], today: Date())
        #expect(etat.risk == nil)
        #expect(etat.riskRaw == "Majeur")
    }

    // MARK: - Carte « IDENTITÉ »

    @Test("Les cinq lignes d'identité de la capture")
    func identite() throws {
        let semis = try semis()
        #expect(semis.etat.identity.map(\.libelle)
                == ["Code", "Domaine", "Jours", "Fin design", "DAT / DIT"])
        #expect(semis.etat.identity.map(\.valeur) == [
            "P25_193", "ASP", "60",
            ProjectPilotageBuilder.jourMoisAnnee(midi(0)),
            "— / —",
        ])
        #expect(semis.etat.identity[0].mono)
        #expect(semis.etat.identity.last?.absente == true)
    }

    @Test("Un DAT déposé change la ligne DAT / DIT")
    func documentsTechniques() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        #expect(ProjectPilotageBuilder.documents(of: projet) == "— / —")
        projet.hasDAT = true
        #expect(ProjectPilotageBuilder.documents(of: projet) == "✓ / —")
        projet.hasDIT = true
        #expect(ProjectPilotageBuilder.documents(of: projet) == "✓ / ✓")
    }

    // MARK: - Alerte de deadline

    @Test("La deadline de design du semis tombe aujourd'hui — J−0")
    func alerteDeDeadline() throws {
        let semis = try semis()
        let alerte = try #require(semis.etat.deadlineAlert)
        #expect(alerte == "Deadline design \(ProjectPilotageBuilder.jourMoisAnnee(midi(0)))"
                + " — J\u{2212}0")
    }

    @Test("L'alerte n'apparaît qu'à sept jours, et dit son retard passé l'échéance")
    func seuilDeLAlerte() throws {
        let contexte = try contexteEnMemoire()
        let projet = projetNu(contexte)
        let debut = Calendar.current.startOfDay(for: Date())
        #expect(ProjectPilotageBuilder.alerteDeDeadline(projet, debutDuJour: debut) == nil)

        projet.designEndDeadline = midi(8)
        #expect(ProjectPilotageBuilder.alerteDeDeadline(projet, debutDuJour: debut) == nil)

        projet.designEndDeadline = midi(7)
        #expect(ProjectPilotageBuilder.alerteDeDeadline(projet, debutDuJour: debut)?
            .hasSuffix("J\u{2212}7") == true)

        projet.designEndDeadline = midi(-3)
        #expect(ProjectPilotageBuilder.alerteDeDeadline(projet, debutDuJour: debut)?
            .hasSuffix("retard 3 j") == true)
    }

    // MARK: - Rien ne s'écrit dans le store

    /// Un constructeur pur ne touche pas au modèle : la règle du dépôt, et la
    /// raison pour laquelle `stableID` reste optionnel dans les lignes.
    @Test("Construire l'état n'écrit rien")
    func aucuneEcriture() throws {
        let semis = try semis()
        #expect(!semis.contexte.hasChanges)
    }
}
