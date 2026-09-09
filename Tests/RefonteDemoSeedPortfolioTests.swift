import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le portefeuille de démonstration (décision **D6**) : ce que les captures
/// `1a-portfolio.png`, `1d-ecran-projet-pilotage.png` et `1f-vue-a-risque.png`
/// demandent d'avoir sous les yeux.
///
/// Sans lui, comparer le Portfolio à sa maquette voudrait dire saisir soixante
/// projets à la main — donc ne jamais le faire deux fois pareil. Et comme tout
/// semis du dépôt, il est **idempotent** et n'écrase jamais un projet réel :
/// c'est la condition pour qu'un item de menu soit sans danger.
@Suite("Semis du portefeuille — D6")
@MainActor
struct RefonteDemoSeedPortfolioTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func projets(_ contexte: ModelContext) throws -> [Project] {
        try contexte.fetch(FetchDescriptor<Project>())
    }

    private func focus(_ contexte: ModelContext) throws -> Project {
        let code = RefonteDemoSeed.portfolioFocusProjectCode
        return try #require(try projets(contexte).first { $0.code == code })
    }

    // MARK: - Le compte de l'en-tête de la capture 1a

    @Test("Le semis pose 62 projets actifs et 14 archivés")
    func comptes() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let tous = try projets(contexte)
        #expect(tous.filter { !$0.isArchived }.count == 62)
        #expect(tous.filter(\.isArchived).count == 14)
        #expect(tous.count == 76)
        #expect(RefonteDemoSeed.portfolioActiveCount == 62)
        #expect(RefonteDemoSeed.portfolioArchivedCount == 14)
    }

    @Test("Les projets actifs se répartissent sur les huit entités de la capture")
    func huitEntites() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let actifs = try projets(contexte).filter { !$0.isArchived }
        let entites = Set(actifs.compactMap { $0.entity?.name })
        #expect(entites == Set(RefonteDemoSeed.portfolioEntityNames))
        #expect(entites.count == 8)
        #expect(actifs.allSatisfy { $0.entity != nil }, "aucun projet sans entité")
    }

    @Test("Les codes de projet sont uniques")
    func codesUniques() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let codes = try projets(contexte).map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test("Trois projets sont épinglés — ceux de la section « ÉPINGLÉS »")
    func troisEpingles() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let epingles = try projets(contexte).filter(\.pinned)
        #expect(epingles.count == 3)
        #expect(Set(epingles.map(\.code)) == ["P25_112", "P25_193", "P25_087"])
    }

    /// Les huit lignes visibles du tableau de la capture 1a, dans l'ordre, avec
    /// leurs valeurs.
    @Test("Les huit lignes de la capture 1a sont là, avec leurs phases et leurs risques")
    func lignesDeLaCapture() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let parCode = Dictionary(uniqueKeysWithValues: try projets(contexte).map { ($0.code, $0) })

        let attendu: [(code: String, phase: String, risque: String?, type: String)] = [
            ("P25_112", "Build",   "Modéré",  "Métier"),
            ("P25_193", "Design",  "Modéré",  "Métier"),
            ("P25_087", "Build",   "Élevé",   "Métier"),
            ("P25_140", "Cadrage", "Modéré",  "Technique"),
            ("P25_155", "Design",  nil,       "Métier"),
            ("P25_061", "Run",     nil,       "Technique"),
            ("P25_099", "Build",   "Modéré",  "Technique"),
            ("P25_121", "Run",     nil,       "Technique"),
        ]
        for ligne in attendu {
            let projet = try #require(parCode[ligne.code], "\(ligne.code) absent")
            #expect(projet.phase == ligne.phase, "\(ligne.code)")
            #expect((projet.riskLevel ?? "").isEmpty == (ligne.risque == nil), "\(ligne.code)")
            if let risque = ligne.risque {
                #expect(projet.riskLevel == risque, "\(ligne.code)")
            }
            #expect(projet.projectType == ligne.type, "\(ligne.code)")
            #expect(projet.entity?.name == "ASP", "\(ligne.code)")
            // Toute phase semée est une phase connue (D14).
            #expect(ProjectPhase(raw: projet.phase) != nil, "\(ligne.code)")
        }
    }

    // MARK: - L'écran projet de la capture 1d

    @Test("Le projet de la capture 1d porte l'identifiant stable que la recette attend")
    func identifiantDuProjetFocus() throws {
        let contexte = try contexteEnMemoire()
        let rendu = RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try focus(contexte)
        #expect(projet.stableID == RefonteDemoSeed.portfolioFocusProjectStableID)
        #expect(rendu?.code == RefonteDemoSeed.portfolioFocusProjectCode)
    }

    @Test("La fiche du projet 1d porte périmètre, risque, charge et fin de design")
    func ficheDuProjetFocus() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try focus(contexte)

        #expect(projet.name == "AE – Gestion des services IO pour l’association ALP")
        #expect(projet.phase == "Design")
        #expect(projet.status == "Green")
        #expect(projet.riskLevel == "Modéré")
        #expect(projet.riskDescription?.contains("équipe ALP") == true)
        #expect(projet.scopeText.contains("annuaire"))
        #expect(projet.plannedDays == 60)
        #expect(projet.budgetCons == 48)
        // « Deadline design 09/09/2026 — J−0 » : la deadline est le jour du semis.
        let deadline = try #require(projet.designEndDeadline)
        #expect(Calendar.current.isDateInToday(deadline))
        // Capture 1f : la fiche est incomplète **par le sponsor**.
        #expect(projet.sponsor.isEmpty)
    }

    /// Décision **D3** : la relation fait foi. Le chef de projet et
    /// l'architecte du projet de la capture 1d sont des `Collaborator` liés,
    /// pas seulement des chaînes importées.
    @Test("Le chef de projet et l'architecte du projet 1d sont des collaborateurs liés")
    func interlocuteursLies() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try focus(contexte)

        #expect(projet.projectManager?.name == "RIGAUT Manuel")
        #expect(projet.technicalArchitect?.name == "THEDREZ Wilfried")
        #expect(projet.chefDeProjet == "RIGAUT Manuel")
        #expect(projet.architecte == "THEDREZ Wilfried")
        // La carte INTERLOCUTEURS de la capture 1d : deux lignes nommées, le
        // sponsor restant à renseigner.
        let roles = projet.contacts.sorted { $0.order < $1.order }.map { "\($0.name) · \($0.role)" }
        #expect(roles == ["RIGAUT Manuel · Chef de projet",
                          "THEDREZ Wilfried · Architecte technique"])
    }

    @Test("Le projet 1d a six actions ouvertes, dont deux en retard")
    func actionsDuProjetFocus() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try focus(contexte)

        let ouvertes = projet.tasks.filter { $0.status == .open }
        #expect(ouvertes.count == 6)
        // « En retard » = ouverte et échue (D11).
        let debutDuJour = Calendar.current.startOfDay(for: Date())
        let enRetard = ouvertes.filter { ($0.dueDate ?? .distantFuture) < debutDuJour }
        #expect(enRetard.count == 2)
        #expect(Set(enRetard.map(\.title)) == ["Valider le périmètre IO avec l’ALP",
                                               "Chiffrer la reprise de données"])
        // Les quatre libellés visibles de la capture 1d.
        let titres = Set(ouvertes.map(\.title))
        #expect(titres.contains("Rédiger le DAT"))
        #expect(titres.contains("Planifier l’atelier sécurité"))
        // « Planifier l'atelier sécurité » est la seule non affectée.
        #expect(ouvertes.filter { $0.collaborator == nil }.map(\.title)
            == ["Planifier l’atelier sécurité"])
    }

    @Test("Le projet 1d a trois réunions nommées : un COPIL, un atelier, un 1:1")
    func reunionsDuProjetFocus() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try focus(contexte)

        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())
            .filter { $0.project?.code == projet.code }
        // « RYTHME · 9 réunions / 12 sem. » de la capture 1d.
        #expect(reunions.count == 9)

        let copil = try #require(reunions.first { $0.title == "Arbitrage périmètre IO" })
        #expect(copil.tags.contains { $0.name == "COPIL" })
        #expect(copil.meetingDurationSeconds == 45 * 60)
        #expect(copil.decisions.first?.contains("annuaire") == true)
        // La dernière réunion, « hier ».
        let derniere = try #require(reunions.max { $0.date < $1.date })
        #expect(derniere.title == copil.title)
        #expect(Calendar.current.dateComponents([.day], from: derniere.date, to: Date()).day == 1)

        let atelier = try #require(reunions.first { $0.title == "Cadrage technique avec l’ALP" })
        #expect(atelier.kind == .workshop)
        let unAUn = try #require(reunions.first { $0.title == "Point d’avancement — PENVEN Yann" })
        #expect(unAUn.kind == .oneToOne)
    }

    @Test("Le projet 1d a deux mails liés et trois suggestions de rattachement")
    func mailsDuProjetFocus() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try focus(contexte)

        #expect(projet.mails.count == 2)
        #expect(projet.mails.contains { $0.subject == "RE : périmètre v1 — annuaire" })
        let suggestions = try contexte.fetch(FetchDescriptor<MailIndexSuggestion>())
            .filter { $0.suggestedProject?.code == projet.code }
        #expect(suggestions.count == 3)
    }

    // MARK: - Les trois motifs de la capture 1f

    @Test("Deux projets seulement portent un jalon dépassé")
    func deuxJalonsDepasses() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let debutDuJour = Calendar.current.startOfDay(for: Date())
        let depasses = try projets(contexte)
            .filter { !$0.isArchived }
            .filter { projet in
                projet.milestones.contains { jalon in
                    guard let echeance = jalon.dueAt else { return false }
                    return echeance < debutDuJour && jalon.state != .done
                }
            }
        #expect(depasses.count == 2)
        #expect(Set(depasses.map(\.code)).contains("P25_087"))
    }

    @Test("Trois projets seulement sont sans réunion depuis trente jours")
    func troisSansReunion() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let reunions = try contexte.fetch(FetchDescriptor<Meeting>())
        let seuil = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let silencieux = try projets(contexte)
            .filter { !$0.isArchived }
            .filter { projet in
                let leurs = reunions.filter { $0.project?.code == projet.code }
                guard let derniere = leurs.map(\.date).max() else { return true }
                return derniere < seuil
            }
        #expect(silencieux.count == 3)
        #expect(Set(silencieux.map(\.code)).contains("P25_121"))
        #expect(Set(silencieux.map(\.code)).contains("P25_155"))
    }

    /// Règle **D11** / **D3** : `projectManager == nil || sponsor.isEmpty ||
    /// status == "Unknown"`. Exactement deux projets, comme la capture 1f.
    @Test("Deux projets seulement ont une fiche incomplète")
    func deuxFichesIncompletes() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let incompletes = try projets(contexte)
            .filter { !$0.isArchived }
            .filter { $0.projectManager == nil || $0.sponsor.isEmpty || $0.status == "Unknown" }
        #expect(incompletes.count == 2)
        #expect(Set(incompletes.map(\.code)) == ["P25_193", "P25_099"])
    }

    /// D3 : le projet incomplet garde le nom importé du xlsx dans
    /// `chefDeProjet` — c'est lui qui préremplira le sélecteur de l'action
    /// « Compléter » (lot 5).
    @Test("Le projet à fiche incomplète garde son chef de projet en chaîne libre")
    func chefDeProjetEnChaineLibre() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try #require(try projets(contexte).first { $0.code == "P25_099" })
        #expect(projet.projectManager == nil)
        #expect(projet.chefDeProjet == "NOMINE Laurent")
        #expect(projet.status == "Unknown")
    }

    @Test("Le portefeuille porte vingt-trois actions ouvertes")
    func vingtTroisActions() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let codes = Set(try projets(contexte).map(\.code))
        let ouvertes = try contexte.fetch(FetchDescriptor<ActionTask>())
            .filter { $0.status == .open }
            .filter { codes.contains($0.project?.code ?? "") }
        #expect(ouvertes.count == 23)
    }

    // MARK: - Idempotence et respect des données réelles

    @Test("Semer deux fois ne duplique rien")
    func idempotent() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let apresUn = try projets(contexte).count
        let reunionsUn = try contexte.fetch(FetchDescriptor<Meeting>()).count
        let actionsUn = try contexte.fetch(FetchDescriptor<ActionTask>()).count
        let entitesUn = try contexte.fetch(FetchDescriptor<Entity>()).count

        RefonteDemoSeed.seedPortfolio(in: contexte)
        #expect(try projets(contexte).count == apresUn)
        #expect(try contexte.fetch(FetchDescriptor<Meeting>()).count == reunionsUn)
        #expect(try contexte.fetch(FetchDescriptor<ActionTask>()).count == actionsUn)
        #expect(try contexte.fetch(FetchDescriptor<Entity>()).count == entitesUn)
        #expect(try contexte.fetch(FetchDescriptor<MailIndexSuggestion>()).count == 3)
    }

    /// Un projet réel peut porter un code du semis. Le semis ne le touche
    /// **pas** : ni budget, ni jalon, ni interlocuteur de démonstration — même
    /// raison que `seedProject` du semis de réunion.
    @Test("Un projet existant portant le même code n'est jamais modifié")
    func projetExistantIntact() throws {
        let contexte = try contexteEnMemoire()
        let existant = Project(code: RefonteDemoSeed.portfolioFocusProjectCode,
                               name: "Mon vrai projet",
                               domain: "MOI",
                               sponsor: "Un sponsor réel",
                               projectType: "Transverse",
                               phase: "Réalisation",
                               status: "Red")
        existant.scopeText = "Périmètre saisi à la main"
        contexte.insert(existant)
        try contexte.save()
        let identifiantReel = existant.stableID

        RefonteDemoSeed.seedPortfolio(in: contexte)

        #expect(existant.name == "Mon vrai projet")
        #expect(existant.phase == "Réalisation")
        #expect(existant.status == "Red")
        #expect(existant.sponsor == "Un sponsor réel")
        #expect(existant.scopeText == "Périmètre saisi à la main")
        #expect(existant.stableID == identifiantReel)
        #expect(existant.milestones.isEmpty)
        #expect(existant.contacts.isEmpty)
        #expect(existant.mails.isEmpty)
        #expect(existant.tasks.isEmpty)
        #expect(existant.pinned == false)
        // Et le semis n'a pas créé un doublon de ce code.
        #expect(try projets(contexte).filter { $0.code == existant.code }.count == 1)
    }

    /// Motif de `seedCollaborators` : un « rigaut manuel » déjà en base est
    /// réutilisé, jamais dédoublé.
    @Test("Un collaborateur homonyme est réutilisé, casse ignorée")
    func collaborateurHomonymeReutilise() throws {
        let contexte = try contexteEnMemoire()
        let existant = Collaborator(name: "rigaut manuel", role: "Architecte")
        contexte.insert(existant)
        try contexte.save()

        RefonteDemoSeed.seedPortfolio(in: contexte)

        let tous = try contexte.fetch(FetchDescriptor<Collaborator>())
        #expect(tous.filter { $0.name.localizedCaseInsensitiveCompare("rigaut manuel") == .orderedSame }
            .count == 1)
        #expect(existant.role == "Architecte", "le rôle réel n'est pas réécrit")
        let projet = try focus(contexte)
        #expect(projet.projectManager?.persistentModelID == existant.persistentModelID)
    }

    /// Une entité déjà en base est réutilisée : le semis ne crée pas un second
    /// « ASP ».
    @Test("Une entité homonyme est réutilisée")
    func entiteHomonymeReutilisee() throws {
        let contexte = try contexteEnMemoire()
        let asp = Entity(name: "ASP", summary: "Mon résumé")
        contexte.insert(asp)
        try contexte.save()

        RefonteDemoSeed.seedPortfolio(in: contexte)

        let entites = try contexte.fetch(FetchDescriptor<Entity>())
        #expect(entites.filter { $0.name == "ASP" }.count == 1)
        #expect(asp.summary == "Mon résumé")
        #expect(!asp.projects.isEmpty)
    }
}
