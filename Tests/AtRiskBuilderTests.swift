import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La règle des trois motifs de la vue « À risque » (capture
/// `1f-vue-a-risque.png`), testée **avant sa vue** (décision **D11**).
///
/// Les sept lignes de la capture sont vérifiées sur le **semis du
/// portefeuille**, pas sur des projets fabriqués pour l'occasion : c'est ce
/// store-là que la recette `p1f` photographie, et un groupe juste sur un cas
/// d'école mais faux sur soixante-seize projets ne prouverait rien.
@Suite("Vue À risque — les trois motifs")
@MainActor
struct AtRiskBuilderTests {

    // MARK: - Outils

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func rapport(_ contexte: ModelContext, today: Date = Date()) throws -> AtRiskReport {
        AtRiskBuilder.build(projects: try contexte.fetch(FetchDescriptor<Project>()),
                            meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
                            today: today)
    }

    @discardableResult
    private func projet(_ contexte: ModelContext,
                        code: String = "P25_001",
                        nom: String? = nil,
                        sponsor: String = "Direction ASP",
                        statut: String = "Green",
                        chefLie: Bool = true,
                        chefNomme: String = "RIGAUT Manuel") -> Project {
        let p = Project(code: code, name: nom ?? "Projet \(code)", domain: "ASP",
                        sponsor: sponsor, projectType: "Métier", phase: "Build",
                        status: statut)
        contexte.insert(p)
        p.chefDeProjet = chefNomme
        if chefLie {
            let chef = Collaborator(name: chefNomme, role: "Chef de projet")
            contexte.insert(chef)
            p.projectManager = chef
        }
        return p
    }

    private func jalon(_ contexte: ModelContext,
                       on projet: Project,
                       libelle: String,
                       jours: Int?,
                       etat: MilestoneState = .planned,
                       today: Date = Date()) {
        let m = ProjectMilestone(label: libelle,
                                 dueAt: jours.map { today.addingTimeInterval(Double($0) * 86_400) },
                                 state: etat)
        contexte.insert(m)
        m.project = projet
    }

    private func reunion(_ contexte: ModelContext,
                         on projet: Project,
                         ilYA jours: Int,
                         kind: MeetingKind = .project,
                         today: Date = Date()) {
        let r = Meeting(title: "COPIL", date: today.addingTimeInterval(Double(-jours) * 86_400),
                        notes: "")
        r.kind = kind
        contexte.insert(r)
        r.project = projet
    }

    // MARK: - Les sept lignes de la capture 1f

    @Test("Le semis rend 2 jalons dépassés, 3 sans réunion, 2 fiches incomplètes et 7 projets")
    func comptesDuSemis() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let r = try rapport(contexte)
        #expect(r.overdueMilestones.count == 2)
        #expect(r.silent30Days.count == 3)
        #expect(r.incomplete.count == 2)
        #expect(r.projectCount == 7)
        #expect(!r.estVide)
    }

    @Test("Le badge « 7 » de la barre latérale sort du même calcul")
    func compteDuBadge() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let compte = AtRiskBuilder.count(projects: try contexte.fetch(FetchDescriptor<Project>()),
                                         meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
                                         today: Date())
        #expect(compte == 7)
    }

    @Test("Les deux jalons dépassés sont ceux de la capture, dans l'ordre et au mot près")
    func groupeDesJalons() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let lignes = try rapport(contexte).overdueMilestones
        #expect(lignes.map(\.title) == ["ASP – Installation nouvelle GED", "RH – TIME & APPLI"])
        #expect(lignes.first?.detail == "Recette utilisateurs · échue depuis 6 j · PENVEN Yann")
        #expect(lignes.last?.detail == "Livraison prod · échue depuis 2 j · NOMINE Laurent")
        for ligne in lignes {
            #expect(ligne.action.libelle == "Replanifier")
            if case .replan = ligne.action {} else { Issue.record("attendu .replan") }
        }
    }

    @Test("Les trois projets silencieux sont ceux de la capture, avec leurs deux libellés")
    func groupeDesSilences() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let lignes = try rapport(contexte).silent30Days
        #expect(Set(lignes.map(\.title)) == ["ASP – Intégration « NEVIDIS » Filiale",
                                             "ASP – Sécurisation IBMi Netserver",
                                             "FIN – Refonte facturation fournisseurs"])
        let details = Dictionary(uniqueKeysWithValues: lignes.map { ($0.title, $0.detail) })
        #expect(details["ASP – Sécurisation IBMi Netserver"] == "Dernière réunion il y a 34 j")
        // Écart assumé avec la maquette, qui écrit « il y a 41 j » : le semis
        // du lot 0 ne donne aucune réunion à ce projet, et le dispatch demande
        // de ne pas le modifier tant que les comptes 2/3/2 sortent.
        #expect(details["ASP – Intégration « NEVIDIS » Filiale"] == "Aucune réunion enregistrée")
        #expect(details["FIN – Refonte facturation fournisseurs"] == "Aucune réunion enregistrée")
        // Le plus long silence en tête : les deux « jamais » avant les 34 j.
        #expect(lignes.last?.title == "ASP – Sécurisation IBMi Netserver")
        #expect(lignes.allSatisfy { $0.action == .schedule })
        #expect(lignes.allSatisfy { $0.action.libelle == "Planifier" })
    }

    @Test("Les deux fiches incomplètes sont celles de la capture, avec leurs champs")
    func groupeDesFiches() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let lignes = try rapport(contexte).incomplete
        #expect(lignes.map(\.title) == ["AE – Gestion des services IO pour l’association ALP",
                                        "ASP – Obsolescence de la VM applicative"])
        #expect(lignes.first?.detail == "Sponsor non renseigné")
        #expect(lignes.last?.detail == "Pas de chef de projet · statut inconnu")
        #expect(lignes.first?.action == .complete(field: .sponsor))
        #expect(lignes.last?.action == .complete(field: .manager))
        #expect(lignes.allSatisfy { $0.action.libelle == "Compléter" })
    }

    @Test("Le semis deux fois ne change aucun groupe")
    func idempotence() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let premier = try rapport(contexte)
        RefonteDemoSeed.seedPortfolio(in: contexte)
        #expect(try rapport(contexte) == premier)
    }

    @Test("Un store vide rend trois groupes vides")
    func storeVide() throws {
        let contexte = try contexteEnMemoire()
        let r = try rapport(contexte)
        #expect(r.overdueMilestones.isEmpty)
        #expect(r.silent30Days.isEmpty)
        #expect(r.incomplete.isEmpty)
        #expect(r.projectCount == 0)
        #expect(r.estVide)
    }

    // MARK: - Motif 1 : jalon dépassé

    @Test("Un jalon échu et non fait est dépassé ; fait ou à venir, non")
    func motifJalon() {
        let aujourdHui = Date()
        let hier = aujourdHui.addingTimeInterval(-6 * 86_400)
        let demain = aujourdHui.addingTimeInterval(6 * 86_400)
        #expect(AtRiskBuilder.estDepasse(dueAt: hier, state: .planned, today: aujourdHui))
        #expect(AtRiskBuilder.estDepasse(dueAt: hier, state: .inProgress, today: aujourdHui))
        #expect(!AtRiskBuilder.estDepasse(dueAt: hier, state: .done, today: aujourdHui))
        #expect(!AtRiskBuilder.estDepasse(dueAt: demain, state: .planned, today: aujourdHui))
        #expect(!AtRiskBuilder.estDepasse(dueAt: nil, state: .inProgress, today: aujourdHui))
        #expect(!AtRiskBuilder.jalonDepasse(jalons: [], today: aujourdHui))
    }

    @Test("`MilestoneState.late` saisi compte comme dépassé, même à échéance future")
    func motifJalonSaisiEnRetard() throws {
        let aujourdHui = Date()
        #expect(AtRiskBuilder.estDepasse(dueAt: aujourdHui.addingTimeInterval(6 * 86_400),
                                         state: .late, today: aujourdHui))
        #expect(AtRiskBuilder.estDepasse(dueAt: nil, state: .late, today: aujourdHui))

        let contexte = try contexteEnMemoire()
        let p = projet(contexte, nom: "ASP – Bascule")
        reunion(contexte, on: p, ilYA: 3)
        jalon(contexte, on: p, libelle: "Bascule du site", jours: 6, etat: .late)
        let lignes = try rapport(contexte).overdueMilestones
        #expect(lignes.count == 1)
        // Pas de « échue depuis N j » : l'échéance n'est pas passée.
        #expect(lignes.first?.detail == "Bascule du site · en retard · RIGAUT Manuel")
    }

    @Test("Un jalon dû aujourd'hui n'est pas dépassé dans la journée")
    func jalonDuAujourdHui() {
        let calendrier = Calendar.current
        let quinzeHeures = calendrier.date(bySettingHour: 15, minute: 0, second: 0,
                                           of: Date()) ?? Date()
        let midi = calendrier.date(bySettingHour: 12, minute: 0, second: 0,
                                   of: quinzeHeures) ?? quinzeHeures
        #expect(!AtRiskBuilder.estDepasse(dueAt: midi, state: .planned, today: quinzeHeures))
    }

    @Test("Le jalon nommé est le plus ancien des dépassés")
    func jalonLePlusAncien() throws {
        let contexte = try contexteEnMemoire()
        let aujourdHui = Date()
        let p = projet(contexte, nom: "ASP – GED")
        reunion(contexte, on: p, ilYA: 3, today: aujourdHui)
        jalon(contexte, on: p, libelle: "Recette", jours: -6, today: aujourdHui)
        jalon(contexte, on: p, libelle: "Livraison", jours: -2, today: aujourdHui)
        let lignes = try rapport(contexte, today: aujourdHui).overdueMilestones
        // Une ligne par projet et par groupe, et c'est le retard le plus long.
        #expect(lignes.count == 1)
        #expect(lignes.first?.detail == "Recette · échue depuis 6 j · RIGAUT Manuel")
    }

    @Test("Le porteur est le chef lié, à défaut le nom du xlsx, à défaut rien")
    func porteurDeLaLigne() throws {
        let contexte = try contexteEnMemoire()
        let lie = projet(contexte, code: "P25_001", chefNomme: "PENVEN Yann")
        #expect(AtRiskBuilder.porteur(of: lie) == "PENVEN Yann")

        let libre = projet(contexte, code: "P25_002", chefLie: false, chefNomme: "NOMINE Laurent")
        #expect(AtRiskBuilder.porteur(of: libre) == "NOMINE Laurent")

        let anonyme = projet(contexte, code: "P25_003", chefLie: false, chefNomme: "")
        #expect(AtRiskBuilder.porteur(of: anonyme) == nil)

        let aujourdHui = Date()
        jalon(contexte, on: anonyme, libelle: "Recette", jours: -3, today: aujourdHui)
        let ligne = try rapport(contexte, today: aujourdHui).overdueMilestones
            .first { $0.title == anonyme.name }
        #expect(ligne?.detail == "Recette · échue depuis 3 j")
    }

    // MARK: - Motif 2 : sans réunion depuis 30 jours

    @Test("Aucune réunion tenue depuis trente jours, ou aucune du tout")
    func motifSilence() {
        let aujourdHui = Date()
        #expect(AtRiskBuilder.sansReunionRecente(nil, today: aujourdHui))
        #expect(AtRiskBuilder.sansReunionRecente(aujourdHui.addingTimeInterval(-34 * 86_400),
                                                 today: aujourdHui))
        #expect(!AtRiskBuilder.sansReunionRecente(aujourdHui.addingTimeInterval(-26 * 86_400),
                                                  today: aujourdHui))
        #expect(AtRiskBuilder.sansReunionDepuis == 30)
    }

    @Test("Une note et une réunion à venir ne rompent pas le silence")
    func silenceEtNotes() throws {
        let contexte = try contexteEnMemoire()
        let aujourdHui = Date()
        let p = projet(contexte, nom: "FIN – Facturation")
        reunion(contexte, on: p, ilYA: 2, kind: .note, today: aujourdHui)
        reunion(contexte, on: p, ilYA: -10, today: aujourdHui)   // dans dix jours
        let lignes = try rapport(contexte, today: aujourdHui).silent30Days
        #expect(lignes.count == 1)
        #expect(lignes.first?.detail == "Aucune réunion enregistrée")
    }

    @Test("Le détail du silence compte les jours pleins")
    func libelleDuSilence() {
        let aujourdHui = Date()
        #expect(AtRiskBuilder.detailDeSilence(nil, today: aujourdHui)
                == "Aucune réunion enregistrée")
        #expect(AtRiskBuilder.detailDeSilence(aujourdHui.addingTimeInterval(-34 * 86_400),
                                              today: aujourdHui)
                == "Dernière réunion il y a 34 j")
        #expect(AtRiskBuilder.silence(nil, today: aujourdHui) == Int.max)
    }

    // MARK: - Motif 3 : fiche incomplète

    @Test("Sponsor vide, chef non lié (D3) et statut inconnu rendent la fiche incomplète")
    func motifFiche() throws {
        let contexte = try contexteEnMemoire()
        #expect(AtRiskBuilder.champsManquants(projet(contexte, code: "P25_001", sponsor: ""))
                == [.sponsor])
        // D3 : la **relation** fait foi — le nom du xlsx ne suffit pas.
        let sansRelation = projet(contexte, code: "P25_002", chefLie: false,
                                  chefNomme: "NOMINE Laurent")
        #expect(AtRiskBuilder.champsManquants(sansRelation) == [.manager])
        #expect(AtRiskBuilder.champsManquants(projet(contexte, code: "P25_003", statut: "Unknown"))
                == [.status])
        #expect(AtRiskBuilder.champsManquants(projet(contexte, code: "P25_004", statut: ""))
                == [.status])
        // Une valeur hors table s'affiche en neutre (D14) mais ne manque pas.
        #expect(AtRiskBuilder.champsManquants(projet(contexte, code: "P25_005",
                                                     statut: "Réalisation")).isEmpty)
        #expect(!AtRiskBuilder.ficheIncomplete(projet(contexte, code: "P25_006")))
    }

    @Test("Les fragments manquants se joignent par « · », majuscule au premier seulement")
    func libelleDeLaFiche() {
        #expect(IncompleteField.sponsor.detail == "Sponsor non renseigné")
        #expect(IncompleteField.manager.detail == "Pas de chef de projet")
        #expect(IncompleteField.status.detail == "Statut inconnu")
        #expect(AtRiskBuilder.detailDeFiche([.status]) == "Statut inconnu")
        #expect(AtRiskBuilder.detailDeFiche([.manager, .status])
                == "Pas de chef de projet · statut inconnu")
        #expect(AtRiskBuilder.detailDeFiche([.sponsor, .manager, .status])
                == "Sponsor non renseigné · pas de chef de projet · statut inconnu")
        #expect(AtRiskBuilder.detailDeFiche([]).isEmpty)
    }

    @Test("« Compléter » vise le premier champ manquant")
    func champVise() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, nom: "ASP – VM", statut: "Unknown", chefLie: false)
        reunion(contexte, on: p, ilYA: 3)
        let ligne = try #require(try rapport(contexte).incomplete.first)
        #expect(ligne.action == .complete(field: .manager))
        #expect(ProjectField(.manager) == .manager)
        #expect(ProjectField(.sponsor) == .sponsor)
        #expect(ProjectField(.status) == .status)
    }

    // MARK: - Recoupements et exclusions

    @Test("Un projet peut figurer dans plusieurs groupes mais n'est compté qu'une fois")
    func plusieursGroupes() throws {
        let contexte = try contexteEnMemoire()
        let aujourdHui = Date()
        // Sponsor vide, aucune réunion, jalon échu : les trois motifs.
        let p = projet(contexte, nom: "ASP – Tout à la fois", sponsor: "")
        jalon(contexte, on: p, libelle: "Recette", jours: -4, today: aujourdHui)
        let r = try rapport(contexte, today: aujourdHui)
        #expect(r.overdueMilestones.count == 1)
        #expect(r.silent30Days.count == 1)
        #expect(r.incomplete.count == 1)
        #expect(r.projectCount == 1)
        // Trois lignes, trois identifiants : un `ForEach` refuse les doublons.
        let ids = r.overdueMilestones + r.silent30Days + r.incomplete
        #expect(Set(ids.map(\.id)).count == 3)
        #expect(Set(ids.map(\.project)).count == 1)
    }

    @Test("Un projet archivé n'est jamais à risque")
    func archiveExclu() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, sponsor: "")
        p.isArchived = true
        let r = try rapport(contexte)
        #expect(r.projectCount == 0)
        #expect(r.estVide)
    }

    @Test("Un projet sans nom se replie sur son code")
    func nomVide() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "P25_042", nom: "  ")
        #expect(AtRiskBuilder.nomAffiche(p) == "P25_042")
        #expect(try rapport(contexte).silent30Days.first?.title == "P25_042")
    }

    // MARK: - Le sous-titre

    @Test("Le sous-titre s'accorde et date la mise à jour")
    func sousTitre() {
        let calendrier = Calendar.current
        let matin = calendrier.date(bySettingHour: 9, minute: 30, second: 0, of: Date())!
        let apresMidi = calendrier.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let soir = calendrier.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        #expect(AtRiskBuilder.sousTitre(projets: 7, at: matin)
                == "7 projets demandent une décision · mis à jour ce matin")
        #expect(AtRiskBuilder.sousTitre(projets: 1, at: matin)
                == "1 projet demande une décision · mis à jour ce matin")
        #expect(AtRiskBuilder.sousTitre(projets: 0, at: matin)
                == "0 projets demandent une décision · mis à jour ce matin")
        #expect(AtRiskBuilder.libelleDeMiseAJour(matin) == "ce matin")
        #expect(AtRiskBuilder.libelleDeMiseAJour(apresMidi) == "cet après-midi")
        #expect(AtRiskBuilder.libelleDeMiseAJour(soir) == "ce soir")
    }

    @Test("Le rapport du semis porte le sous-titre de la capture")
    func sousTitreDuSemis() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let matin = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date())!
        let r = try rapport(contexte, today: matin)
        #expect(r.subtitle == "7 projets demandent une décision · mis à jour ce matin")
    }

    // MARK: - « Planifier »

    @Test("« Planifier » vise aujourd'hui + sept jours")
    func dateDePlanification() {
        let aujourdHui = Date()
        let cible = AtRiskBuilder.dateDePlanification(from: aujourdHui)
        #expect(AtRiskBuilder.planifierDansNJours == 7)
        #expect(AtRiskBuilder.joursEcoules(de: aujourdHui, a: cible) == 7)
    }

    @Test("Construire le rapport n'écrit rien dans le store")
    func lectureSeule() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        try contexte.save()
        _ = try rapport(contexte)
        #expect(!contexte.hasChanges)
    }
}
