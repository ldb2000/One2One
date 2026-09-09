import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le tableau du Portfolio (capture `1a-portfolio.png`), testé **sur le semis
/// de démonstration** — c'est ce store-là que la recette photographie.
///
/// Les huit lignes que la capture nomme sont interrogées une par une : leur
/// entité, leur phase, leur risque, leur chef de projet, leur cellule de jalon
/// et leur libellé de dernière réunion. Un tableau juste sur trois projets
/// fabriqués mais faux sur soixante-deux ne vaudrait rien, et c'est exactement
/// ce qui se compare au pixel près.
@Suite("Tableau du Portfolio")
@MainActor
struct PortfolioBuilderTests {

    // MARK: - Outillage

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func semis() throws -> (contexte: ModelContext, lignes: [PortfolioRow], projets: [Project]) {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())
        return (contexte,
                PortfolioBuilder.rows(projects: projets, meetings: reunions, today: Date()),
                projets)
    }

    private func ligne(_ lignes: [PortfolioRow], _ code: String) throws -> PortfolioRow {
        try #require(lignes.first { $0.code == code })
    }

    /// Un projet nu, pour les cas limites qu'aucun projet du semis ne porte.
    private func projet(_ contexte: ModelContext,
                        code: String = "T_001",
                        nom: String = "Projet d'essai",
                        entite: String? = nil,
                        domaine: String = "",
                        phase: String = "Build",
                        statut: String = "Green",
                        risque: String? = nil) -> Project {
        let p = Project(code: code, name: nom, domain: domaine, sponsor: "Direction",
                        projectType: "Métier", phase: phase, status: statut)
        p.riskLevel = risque
        contexte.insert(p)
        if let entite {
            let e = Entity(name: entite)
            contexte.insert(e)
            p.entity = e
        }
        return p
    }

    // MARK: - Les lignes

    @Test("Le semis rend 62 lignes — les projets actifs, pas les archivés")
    func nombreDeLignes() throws {
        let (_, lignes, projets) = try semis()
        #expect(lignes.count == 62)
        #expect(projets.count == 76)
        #expect(lignes.allSatisfy { code in projets.contains { $0.code == code.code && !$0.isArchived } })
    }

    @Test("Les huit lignes de la capture portent l'entité, la phase et le type attendus")
    func huitLignesDeLaCapture() throws {
        let (_, lignes, _) = try semis()
        let attendu: [(code: String, nom: String, phase: ProjectPhase?, type: String)] = [
            ("P25_112", "ASP – BLOOM", .build, "Métier"),
            ("P25_193", "AE – Gestion des services IO pour l’association ALP", .design, "Métier"),
            ("P25_087", "ASP – Installation nouvelle GED", .build, "Métier"),
            ("P25_140", "ASP – Sécurisation des flux inter-sites", .cadrage, "Technique"),
            ("P25_155", "ASP – Intégration « NEVIDIS » Filiale", .design, "Métier"),
            ("P25_061", "ASP – Mise en place d’une infrastructure de sauvegarde", .run, "Technique"),
            ("P25_099", "ASP – Obsolescence de la VM applicative", .build, "Technique"),
            ("P25_121", "ASP – Sécurisation IBMi Netserver", .run, "Technique"),
        ]
        for cas in attendu {
            let l = try ligne(lignes, cas.code)
            #expect(l.name == cas.nom)
            #expect(l.phase == cas.phase)
            #expect(l.type == cas.type)
            #expect(l.entity == "ASP", "\(cas.code) : entité \(String(describing: l.entity))")
        }
    }

    @Test("Les risques de la capture : Modéré, Élevé et le tiret")
    func risques() throws {
        let (_, lignes, _) = try semis()
        #expect(try ligne(lignes, "P25_112").risk == .modere)
        #expect(try ligne(lignes, "P25_087").risk == .eleve)
        #expect(try ligne(lignes, "P25_140").risk == .modere)
        #expect(try ligne(lignes, "P25_099").risk == .modere)
        // « — » sur la capture : le projet n'a pas de niveau de risque.
        #expect(try ligne(lignes, "P25_155").risk == nil)
        #expect(try ligne(lignes, "P25_061").risk == nil)
        #expect(try ligne(lignes, "P25_121").risk == nil)
    }

    @Test("Le chef de projet vient de la relation, jamais de la chaîne du xlsx (D3)")
    func chefDeProjet() throws {
        let (_, lignes, _) = try semis()
        #expect(try ligne(lignes, "P25_112").manager == "RIGAUT Manuel")
        #expect(try ligne(lignes, "P25_087").manager == "PENVEN Yann")
        #expect(try ligne(lignes, "P25_140").manager == "THEDREZ Wilfried")
        #expect(try ligne(lignes, "P25_155").manager == "ORSET Jean-Baptiste")
        #expect(try ligne(lignes, "P25_061").manager == "PAOLI Nicolas")
        #expect(try ligne(lignes, "P25_121").manager == "ZANNETTINI François-Louis")
        // P25_099 : le xlsx écrit « NOMINE Laurent », la relation manque.
        #expect(try ligne(lignes, "P25_099").manager == nil)
    }

    @Test("Le statut alimente la pastille, et une valeur hors table la rend neutre")
    func statuts() throws {
        let (contexte, lignes, _) = try semis()
        #expect(try ligne(lignes, "P25_112").status == .red)
        #expect(try ligne(lignes, "P25_087").status == .yellow)
        #expect(try ligne(lignes, "P25_193").status == .green)
        #expect(try ligne(lignes, "P25_099").status == .unknown)
        #expect(try ligne(lignes, "P25_112").statusLabel == "Red")

        let bizarre = projet(contexte, code: "T_STATUT", statut: "Réalisation")
        let l = PortfolioBuilder.rows(projects: [bizarre], meetings: [], today: Date())[0]
        #expect(l.status == nil)
        #expect(l.statusLabel == "")
        #expect(StatusIcon.teinte(l.statusLabel) == One2OneToken.inkMuted)
    }

    @Test("Une phase hors table garde sa valeur brute et rend un badge neutre (D14)")
    func phaseHorsTable() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, phase: "Réalisation")
        let l = PortfolioBuilder.rows(projects: [p], meetings: [], today: Date())[0]
        #expect(l.phase == nil)
        #expect(l.phaseRaw == "Réalisation")
    }

    @Test("L'entité tombe sur le domaine, puis sur un tiret")
    func entiteEtRepli() throws {
        let contexte = try contexteEnMemoire()
        let avecEntite = projet(contexte, code: "T_E", entite: "ASP", domaine: "RH")
        let sansEntite = projet(contexte, code: "T_D", domaine: "LOG")
        let sansRien = projet(contexte, code: "T_N", domaine: "   ")
        let lignes = PortfolioBuilder.rows(projects: [avecEntite, sansEntite, sansRien],
                                           meetings: [], today: Date())
        #expect(lignes[0].entity == "ASP")
        #expect(lignes[1].entity == "LOG")
        #expect(lignes[2].entity == nil)
        #expect(lignes[2].entityLabel == "—")
    }

    @Test("Les épinglés du semis remontent dans la ligne")
    func epingles() throws {
        let (_, lignes, _) = try semis()
        #expect(lignes.filter(\.pinned).map(\.code).sorted() == ["P25_087", "P25_112", "P25_193"])
    }

    // MARK: - La cellule « JALON »

    @Test("La colonne Jalon du semis : J−4, J−21, retard, J−35, —, J−60, J−12, J−90")
    func celluleJalon() throws {
        let (_, lignes, _) = try semis()
        #expect(try ligne(lignes, "P25_112").nextMilestone == .days(4))
        #expect(try ligne(lignes, "P25_193").nextMilestone == .days(21))
        // Jalon échu depuis six jours : « retard ».
        #expect(try ligne(lignes, "P25_087").nextMilestone == .late)
        #expect(try ligne(lignes, "P25_140").nextMilestone == .days(35))
        // Aucun jalon.
        #expect(try ligne(lignes, "P25_155").nextMilestone == .none)
        #expect(try ligne(lignes, "P25_061").nextMilestone == .days(60))
        #expect(try ligne(lignes, "P25_099").nextMilestone == .days(12))
        #expect(try ligne(lignes, "P25_121").nextMilestone == .days(90))
    }

    @Test("Les libellés de la cellule Jalon, au caractère près")
    func libellesJalon() {
        #expect(MilestoneCell.days(4).libelle == "J−4")
        #expect(MilestoneCell.days(0).libelle == "J−0")
        #expect(MilestoneCell.late.libelle == "retard")
        #expect(MilestoneCell.none.libelle == "—")
        // Le signe est un moins typographique (U+2212), pas un trait d'union.
        #expect(MilestoneCell.days(4).libelle.contains("\u{2212}"))
    }

    @Test("L'alerte du jalon s'allume à sept jours ou moins, et sur un retard")
    func alerteJalon() {
        #expect(MilestoneCell.seuilAlerte == 7)
        #expect(MilestoneCell.days(4).estAlerte)
        #expect(MilestoneCell.days(7).estAlerte)
        #expect(!MilestoneCell.days(8).estAlerte)
        #expect(MilestoneCell.late.estAlerte)
        #expect(!MilestoneCell.none.estAlerte)
    }

    @Test("Un jalon fait est ignoré ; `.late` l'emporte même sans échéance")
    func casLimitesDuJalon() throws {
        let contexte = try contexteEnMemoire()
        let aujourdhui = Date()

        let fait = projet(contexte, code: "T_J1")
        let jalonFait = ProjectMilestone(label: "Fini", dueAt: aujourdhui.addingTimeInterval(-86_400 * 10),
                                         state: .done)
        contexte.insert(jalonFait)
        jalonFait.project = fait
        #expect(PortfolioBuilder.milestoneCell(of: fait, today: aujourdhui) == .none)

        let declareEnRetard = projet(contexte, code: "T_J2")
        let jalonLate = ProjectMilestone(label: "Bloqué", dueAt: nil, state: .late)
        contexte.insert(jalonLate)
        jalonLate.project = declareEnRetard
        #expect(PortfolioBuilder.milestoneCell(of: declareEnRetard, today: aujourdhui) == .late)

        let sansEcheance = projet(contexte, code: "T_J3")
        let jalonSansDate = ProjectMilestone(label: "À planifier", dueAt: nil, state: .planned)
        contexte.insert(jalonSansDate)
        jalonSansDate.project = sansEcheance
        #expect(PortfolioBuilder.milestoneCell(of: sansEcheance, today: aujourdhui) == .none)

        // Deux jalons à venir : la plus proche échéance gagne.
        let deux = projet(contexte, code: "T_J4")
        for jours in [30, 5] {
            let j = ProjectMilestone(label: "J\(jours)",
                                     dueAt: Calendar.current.date(byAdding: .day, value: jours,
                                                                  to: aujourdhui),
                                     state: .planned)
            contexte.insert(j)
            j.project = deux
        }
        #expect(PortfolioBuilder.milestoneCell(of: deux, today: aujourdhui) == .days(5))
    }

    @Test("Un jalon dû aujourd'hui à midi est J−0, pas un retard")
    func jalonDuAujourdhui() throws {
        let contexte = try contexteEnMemoire()
        let calendrier = Calendar.current
        let quinzeHeures = calendrier.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let midi = calendrier.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let p = projet(contexte, code: "T_J5")
        let jalon = ProjectMilestone(label: "Aujourd'hui", dueAt: midi, state: .planned)
        contexte.insert(jalon)
        jalon.project = p
        #expect(PortfolioBuilder.milestoneCell(of: p, today: quinzeHeures) == .days(0))
    }

    // MARK: - La colonne « Dernière réu. »

    @Test("Les libellés relatifs de la capture : hier, il y a 3 j, il y a 2 sem., il y a 1 mois, jamais")
    func libellesRelatifs() {
        let aujourdhui = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        func il(y aJours: Int) -> String {
            let date = Calendar.current.date(byAdding: .day, value: -aJours, to: aujourdhui)!
            return PortfolioBuilder.relativeLabel(from: date, today: aujourdhui)
        }
        #expect(PortfolioBuilder.relativeLabel(from: nil, today: aujourdhui) == "jamais")
        #expect(il(y: 0) == "aujourd'hui")
        #expect(il(y: 1) == "hier")
        #expect(il(y: 3) == "il y a 3 j")
        #expect(il(y: 8) == "il y a 8 j")
        #expect(il(y: 13) == "il y a 13 j")
        #expect(il(y: 14) == "il y a 2 sem.")
        #expect(il(y: 21) == "il y a 3 sem.")
        #expect(il(y: 29) == "il y a 4 sem.")
        #expect(il(y: 30) == "il y a 1 mois")
        #expect(il(y: 34) == "il y a 1 mois")
        #expect(il(y: 90) == "il y a 3 mois")
        #expect(il(y: 400) == "il y a 1 an")
        #expect(il(y: 800) == "il y a 2 ans")
    }

    @Test("Une date à venir ne rend pas un libellé négatif")
    func dateAVenir() {
        let aujourdhui = Date()
        let demain = Calendar.current.date(byAdding: .day, value: 1, to: aujourdhui)!
        #expect(PortfolioBuilder.relativeLabel(from: demain, today: aujourdhui) == "aujourd'hui")
    }

    @Test("La colonne « Dernière réu. » du semis reproduit la capture")
    func derniereReunionDuSemis() throws {
        let (_, lignes, _) = try semis()
        #expect(try ligne(lignes, "P25_112").lastMeetingLabel == "il y a 3 j")
        #expect(try ligne(lignes, "P25_193").lastMeetingLabel == "hier")
        #expect(try ligne(lignes, "P25_087").lastMeetingLabel == "il y a 8 j")
        #expect(try ligne(lignes, "P25_140").lastMeetingLabel == "il y a 2 sem.")
        #expect(try ligne(lignes, "P25_155").lastMeetingLabel == "jamais")
        #expect(try ligne(lignes, "P25_061").lastMeetingLabel == "il y a 5 j")
        #expect(try ligne(lignes, "P25_099").lastMeetingLabel == "il y a 4 j")
        #expect(try ligne(lignes, "P25_121").lastMeetingLabel == "il y a 1 mois")
    }

    @Test("Une note et une réunion à venir ne comptent pas comme dernière réunion")
    func porteeDesReunions() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "T_R")
        let aujourdhui = Date()

        let note = Meeting(title: "Note", date: Calendar.current.date(byAdding: .day, value: -2,
                                                                       to: aujourdhui)!, notes: "")
        note.kind = .note
        note.project = p
        contexte.insert(note)

        let aVenir = Meeting(title: "COPIL de novembre",
                             date: Calendar.current.date(byAdding: .day, value: 40, to: aujourdhui)!,
                             notes: "")
        aVenir.kind = .project
        aVenir.project = p
        contexte.insert(aVenir)

        let lignes = PortfolioBuilder.rows(projects: [p], meetings: [note, aVenir], today: aujourdhui)
        #expect(lignes[0].lastMeeting == nil)
        #expect(lignes[0].lastMeetingLabel == "jamais")
    }

    // MARK: - Les facettes, en ET

    @Test("Aucune facette ne filtre rien")
    func facetteVide() throws {
        let (_, lignes, _) = try semis()
        #expect(PortfolioBuilder.apply(.aucun, to: lignes).count == lignes.count)
        #expect(PortfolioFilters.aucun.estVide)
    }

    @Test("La facette Entité : ASP garde les quinze projets ASP actifs")
    func facetteEntite() throws {
        let (_, lignes, _) = try semis()
        let filtrees = PortfolioBuilder.apply(PortfolioFilters(entities: ["ASP"]), to: lignes)
        #expect(filtrees.allSatisfy { $0.entity == "ASP" })
        // Les huit projets nommés par la capture en font partie.
        for code in ["P25_112", "P25_193", "P25_087", "P25_140",
                     "P25_155", "P25_061", "P25_099", "P25_121"] {
            #expect(filtrees.contains { $0.code == code }, "\(code) absent du filtre ASP")
        }
        #expect(filtrees.count == 15)
    }

    @Test("Le seuil « Risque ≥ Modéré » écarte Faible et l'absence de risque")
    func facetteRisque() throws {
        let (_, lignes, _) = try semis()
        let filtrees = PortfolioBuilder.apply(PortfolioFilters(riskAtLeast: "Modéré"), to: lignes)
        #expect(filtrees.allSatisfy { ($0.risk?.severity ?? -1) >= RiskLevel.modere.severity })
        #expect(!filtrees.contains { $0.risk == nil })
        #expect(!filtrees.contains { $0.risk == .faible })
        #expect(filtrees.contains { $0.code == "P25_087" })   // Élevé
        #expect(filtrees.contains { $0.code == "P25_112" })   // Modéré
    }

    @Test("Deux facettes se cumulent en ET")
    func facettesCumulees() throws {
        let (_, lignes, _) = try semis()
        let asp = PortfolioBuilder.apply(PortfolioFilters(entities: ["ASP"]), to: lignes)
        let aspEtRisque = PortfolioBuilder.apply(
            PortfolioFilters(entities: ["ASP"], riskAtLeast: "Modéré"), to: lignes)
        #expect(aspEtRisque.count < asp.count)
        #expect(aspEtRisque.allSatisfy { $0.entity == "ASP" && $0.risk != nil })
        // Les cinq projets ASP de la capture qui portent un risque ≥ Modéré.
        #expect(Set(aspEtRisque.map(\.code))
                    == Set(["P25_112", "P25_193", "P25_087", "P25_140", "P25_099"]))
    }

    @Test("Dans une même facette, les valeurs sont en OU")
    func facetteMultiValeurs() throws {
        let (_, lignes, _) = try semis()
        let deuxPhases = PortfolioBuilder.apply(PortfolioFilters(phases: ["Build", "Run"]), to: lignes)
        #expect(deuxPhases.allSatisfy { $0.phase == .build || $0.phase == .run })
        #expect(deuxPhases.contains { $0.phase == .build })
        #expect(deuxPhases.contains { $0.phase == .run })
    }

    @Test("La facette Statut lit le libellé persisté")
    func facetteStatut() throws {
        let (_, lignes, _) = try semis()
        let rouges = PortfolioBuilder.apply(PortfolioFilters(statuses: ["Red"]), to: lignes)
        #expect(rouges.allSatisfy { $0.status == .red })
        #expect(rouges.contains { $0.code == "P25_112" })
    }

    @Test("La facette Chef de projet sait isoler « Non affecté »")
    func facetteChefDeProjet() throws {
        let (_, lignes, _) = try semis()
        let dePenven = PortfolioBuilder.apply(PortfolioFilters(managers: ["PENVEN Yann"]), to: lignes)
        #expect(dePenven.allSatisfy { $0.manager == "PENVEN Yann" })
        let nonAffectes = PortfolioBuilder.apply(
            PortfolioFilters(managers: [ProjectPeople.nonAffecte]), to: lignes)
        #expect(nonAffectes.allSatisfy { $0.manager == nil })
        #expect(nonAffectes.contains { $0.code == "P25_099" })
    }

    @Test("Une valeur de facette écrite dans une autre casse filtre quand même")
    func facetteInsensible() throws {
        let (_, lignes, _) = try semis()
        #expect(PortfolioBuilder.apply(PortfolioFilters(entities: ["asp"]), to: lignes).count == 15)
        #expect(PortfolioBuilder.apply(PortfolioFilters(phases: ["cadrage"]), to: lignes).count
                    == PortfolioBuilder.apply(PortfolioFilters(phases: ["Cadrage"]), to: lignes).count)
    }

    @Test("Un seuil de risque illisible ne filtre rien plutôt que de tout vider")
    func seuilInconnu() throws {
        let (_, lignes, _) = try semis()
        #expect(PortfolioBuilder.apply(PortfolioFilters(riskAtLeast: "Catastrophique"),
                                       to: lignes).count == lignes.count)
    }

    @Test("Le champ de recherche filtre sur le nom, le code, l'entité et le sponsor")
    func facetteTexte() throws {
        let (_, lignes, _) = try semis()
        #expect(PortfolioBuilder.apply(PortfolioFilters(text: "netserver"), to: lignes)
                    .map(\.code) == ["P25_121"])
        #expect(PortfolioBuilder.apply(PortfolioFilters(text: "P25_112"), to: lignes)
                    .map(\.code) == ["P25_112"])
        // Sponsor : « Direction filiale » n'est porté que par P25_155.
        #expect(PortfolioBuilder.apply(PortfolioFilters(text: "Direction filiale"), to: lignes)
                    .map(\.code) == ["P25_155"])
        // Accents pliés.
        #expect(PortfolioBuilder.apply(PortfolioFilters(text: "securisation"), to: lignes)
                    .count >= 2)
        // Un terme blanc ne filtre pas.
        #expect(PortfolioBuilder.apply(PortfolioFilters(text: "   "), to: lignes).count == lignes.count)
    }

    // MARK: - Les valeurs des menus

    @Test("Les menus de facettes ne proposent que des valeurs présentes")
    func valeursDesFacettes() throws {
        let (_, lignes, _) = try semis()
        #expect(PortfolioBuilder.values(of: .entity, in: lignes)
                    == ["ASP", "COM", "DSI", "FIN", "JUR", "LOG", "RH", "SI"])
        // La phase suit l'ordre de la table, pas l'alphabet.
        #expect(PortfolioBuilder.values(of: .phase, in: lignes) == ["Cadrage", "Design", "Build", "Run"])
        #expect(PortfolioBuilder.values(of: .status, in: lignes) == ["Green", "Yellow", "Red", "Unknown"])
        // Le risque est un seuil : ses quatre crans, toujours.
        #expect(PortfolioBuilder.values(of: .risk, in: lignes)
                    == ["Faible", "Modéré", "Élevé", "Critique"])
        let chefs = PortfolioBuilder.values(of: .manager, in: lignes)
        #expect(chefs.last == ProjectPeople.nonAffecte)
        #expect(chefs.contains("RIGAUT Manuel"))
    }

    @Test("Une valeur hors table est proposée après celles de la table (D14)")
    func valeurHorsTableProposee() throws {
        let contexte = try contexteEnMemoire()
        let connue = projet(contexte, code: "T_P1", phase: "Build")
        let inconnue = projet(contexte, code: "T_P2", phase: "Réalisation")
        let lignes = PortfolioBuilder.rows(projects: [connue, inconnue], meetings: [], today: Date())
        #expect(PortfolioBuilder.values(of: .phase, in: lignes) == ["Build", "Réalisation"])
    }

    // MARK: - Le tri, colonne par colonne

    @Test("Le tri par défaut est le nom croissant")
    func triParDefaut() throws {
        let (_, lignes, _) = try semis()
        #expect(PortfolioSort.parDefaut.column == .name)
        #expect(PortfolioSort.parDefaut.ascending)
        let triees = PortfolioBuilder.sort(lignes, by: .parDefaut)
        #expect(triees.map(\.name) == lignes.map(\.name)
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test("Chaque colonne trie dans les deux sens, et le sens inverse est le miroir")
    func triDeChaqueColonne() throws {
        let (_, lignes, _) = try semis()
        for colonne in PortfolioSort.Column.allCases {
            let croissant = PortfolioBuilder.sort(lignes, by: PortfolioSort(column: colonne, ascending: true))
            let decroissant = PortfolioBuilder.sort(lignes, by: PortfolioSort(column: colonne, ascending: false))
            #expect(croissant.count == lignes.count, "\(colonne) perd des lignes")
            #expect(Set(croissant.map(\.code)) == Set(lignes.map(\.code)))
            #expect(croissant.first?.code != decroissant.first?.code
                        || lignes.count <= 1, "\(colonne) ne change rien en décroissant")
        }
    }

    @Test("Le tri par phase suit l'ordre Cadrage → Run, les valeurs hors table en dernier")
    func triParPhase() throws {
        let contexte = try contexteEnMemoire()
        let projets = [projet(contexte, code: "T_1", nom: "Zeta", phase: "Run"),
                       projet(contexte, code: "T_2", nom: "Alpha", phase: "Réalisation"),
                       projet(contexte, code: "T_3", nom: "Beta", phase: "Cadrage"),
                       projet(contexte, code: "T_4", nom: "Gamma", phase: "Design")]
        let lignes = PortfolioBuilder.rows(projects: projets, meetings: [], today: Date())
        let triees = PortfolioBuilder.sort(lignes, by: PortfolioSort(column: .phase, ascending: true))
        #expect(triees.map(\.phaseRaw) == ["Cadrage", "Design", "Run", "Réalisation"])
    }

    @Test("Le tri par risque met l'absence de risque avant Faible")
    func triParRisque() throws {
        let contexte = try contexteEnMemoire()
        let projets = [projet(contexte, code: "T_1", nom: "A", risque: "Critique"),
                       projet(contexte, code: "T_2", nom: "B", risque: nil),
                       projet(contexte, code: "T_3", nom: "C", risque: "Faible"),
                       projet(contexte, code: "T_4", nom: "D", risque: "Modéré")]
        let lignes = PortfolioBuilder.rows(projects: projets, meetings: [], today: Date())
        let triees = PortfolioBuilder.sort(lignes, by: PortfolioSort(column: .risk, ascending: true))
        #expect(triees.map(\.name) == ["B", "C", "D", "A"])
    }

    @Test("Le tri par chef de projet place « Non affecté » en dernier")
    func triParChefDeProjet() throws {
        let contexte = try contexteEnMemoire()
        let avec = projet(contexte, code: "T_1", nom: "A")
        let chef = Collaborator(name: "RIGAUT Manuel", role: "Chef de projet")
        contexte.insert(chef)
        avec.projectManager = chef
        let sans = projet(contexte, code: "T_2", nom: "B")
        let lignes = PortfolioBuilder.rows(projects: [sans, avec], meetings: [], today: Date())
        let triees = PortfolioBuilder.sort(lignes, by: PortfolioSort(column: .manager, ascending: true))
        #expect(triees.map(\.name) == ["A", "B"])
    }

    @Test("Le tri par jalon met le retard d'abord et l'absence de jalon en dernier")
    func triParJalon() throws {
        let (_, lignes, _) = try semis()
        let asp = PortfolioBuilder.apply(PortfolioFilters(entities: ["ASP"]), to: lignes)
        let triees = PortfolioBuilder.sort(asp, by: PortfolioSort(column: .milestone, ascending: true))
        #expect(triees.first?.code == "P25_087")            // retard
        #expect(triees.last?.nextMilestone == MilestoneCell.none)   // P25_155, sans jalon
        // Les échéances entre les deux sont croissantes.
        let jours = triees.compactMap { ligne -> Int? in
            if case .days(let n) = ligne.nextMilestone { return n }
            return nil
        }
        #expect(jours == jours.sorted())
    }

    @Test("Le tri par dernière réunion met « jamais » en tête du croissant")
    func triParDerniereReunion() throws {
        let (_, lignes, _) = try semis()
        let asp = PortfolioBuilder.apply(PortfolioFilters(entities: ["ASP"]), to: lignes)
        let triees = PortfolioBuilder.sort(asp, by: PortfolioSort(column: .lastMeeting, ascending: true))
        #expect(triees.first?.lastMeetingLabel == "jamais")
        #expect(triees.last?.lastMeetingLabel == "hier")
    }

    @Test("Le nom départage toujours, en croissant")
    func nomDepartage() throws {
        let contexte = try contexteEnMemoire()
        let projets = [projet(contexte, code: "T_1", nom: "Zeta", entite: "ASP"),
                       projet(contexte, code: "T_2", nom: "Alpha", entite: "ASP")]
        let lignes = PortfolioBuilder.rows(projects: projets, meetings: [], today: Date())
        for ascendant in [true, false] {
            let triees = PortfolioBuilder.sort(lignes,
                                               by: PortfolioSort(column: .entity, ascending: ascendant))
            #expect(triees.map(\.name) == ["Alpha", "Zeta"])
        }
    }

    // MARK: - Les textes de l'en-tête et du pied

    @Test("Le sous-titre du semis : « 62 actifs · 8 entités · 14 archivés »")
    func sousTitre() throws {
        let (_, _, projets) = try semis()
        #expect(PortfolioBuilder.summary(projects: projets) == "62 actifs · 8 entités · 14 archivés")
    }

    @Test("Le sous-titre accorde le singulier et supporte un store vide")
    func sousTitreAccorde() throws {
        let contexte = try contexteEnMemoire()
        #expect(PortfolioBuilder.summary(projects: []) == "0 actif · 0 entité · 0 archivé")
        let seul = projet(contexte, code: "T_S", entite: "ASP")
        #expect(PortfolioBuilder.summary(projects: [seul]) == "1 actif · 1 entité · 0 archivé")
    }

    @Test("Le pied du tableau, au mot de la capture")
    func pied() {
        #expect(PortfolioBuilder.footer(affichees: 8, total: 62)
                    == "8 lignes sur 62 · sélection multiple ⇧-clic pour changer phase, statut ou entité en lot")
        #expect(PortfolioBuilder.footer(affichees: 1, total: 62).hasPrefix("1 ligne sur 62"))
    }

    @Test("Le libellé d'une chip active : « Entité : ASP », « Risque ≥ Modéré »")
    func libellesDesChips() {
        #expect(PortfolioFacet.entity.libelleActif(["ASP"]) == "Entité : ASP")
        #expect(PortfolioFacet.risk.libelleActif(["Modéré"]) == "Risque ≥ Modéré")
        #expect(PortfolioFacet.phase.libelleActif(["Build", "Run"]) == "Phase : 2 valeurs")
        #expect(PortfolioFacet.allCases.map(\.libelle)
                    == ["Entité", "Risque", "Phase", "Statut", "Chef de projet"])
    }

    // MARK: - Le groupement par entité

    @Test("« Groupé par entité » range les mêmes lignes sous huit en-têtes")
    func groupement() throws {
        let (_, lignes, _) = try semis()
        let groupes = PortfolioBuilder.groups(lignes)
        #expect(groupes.map(\.entite) == ["ASP", "COM", "DSI", "FIN", "JUR", "LOG", "RH", "SI"])
        #expect(groupes.reduce(0) { $0 + $1.lignes.count } == lignes.count)
        #expect(groupes.first { $0.entite == "ASP" }?.lignes.count == 15)
    }

    @Test("Les projets sans entité forment le dernier groupe")
    func groupementSansEntite() throws {
        let contexte = try contexteEnMemoire()
        let projets = [projet(contexte, code: "T_1", nom: "A", entite: "ASP"),
                       projet(contexte, code: "T_2", nom: "B", domaine: "")]
        let lignes = PortfolioBuilder.rows(projects: projets, meetings: [], today: Date())
        let groupes = PortfolioBuilder.groups(lignes)
        #expect(groupes.map(\.entite) == ["ASP", "Sans entité"])
    }

    // MARK: - Idempotence du semis

    @Test("Semer deux fois ne change aucune ligne")
    func idempotence() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let premier = PortfolioBuilder.rows(
            projects: try contexte.fetch(FetchDescriptor<Project>()),
            meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
            today: Date())
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let second = PortfolioBuilder.rows(
            projects: try contexte.fetch(FetchDescriptor<Project>()),
            meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
            today: Date())
        #expect(premier.count == second.count)
        #expect(Set(premier.map(\.code)) == Set(second.map(\.code)))
    }
}
