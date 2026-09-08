import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La source unique des compteurs d'actions de l'écran de réunion, et la
/// non-régression du retour d'usage du 8 septembre 2026 : « le tableau
/// n'affiche plus qu'une action assignée, mais le bandeau annonce ACTIONS 3 ·
/// 2 non assignées et la nav du mode Relire Actions 3 ».
///
/// La cause était une double définition : le bandeau et la nav comptaient
/// `meeting.tasks` **sans filtre de statut**, le tableau et le rail filtraient
/// `status == .open`. Deux nombres pour la même réunion, sur le même écran.
@Suite("Compteurs d'actions de la réunion")
@MainActor
struct MeetingActionCountsTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    /// Une réunion et ses trois actions, dont **deux sans responsable**.
    private func troisActions(in context: ModelContext)
        -> (reunion: Meeting, taches: [ActionTask], porteur: Collaborator) {
        let reunion = Meeting(title: "Point Planview", date: .now)
        context.insert(reunion)
        let porteur = Collaborator(name: "Bruno Lindeboom", role: "Architecte")
        context.insert(porteur)
        var taches: [ActionTask] = []
        for index in 0..<3 {
            let tache = ActionTask(title: "Action \(index)")
            context.insert(tache)
            tache.meeting = reunion
            taches.append(tache)
        }
        // La première a un responsable, les deux autres non.
        taches[0].collaborator = porteur
        taches[0].destinataire = .collaborateur
        return (reunion, taches, porteur)
    }

    /// Ce qu'affiche le tableau du poste de pilotage, calculé comme lui.
    private func lignesDuTableau(_ reunion: Meeting) -> Int {
        ActionsRailGrouping.triees(MeetingActionCounts.ouvertes(reunion.tasks)).count
    }

    /// Le complément de l'entrée `Actions` de la nav latérale.
    private func navActions(_ reunion: Meeting) -> ReviewSidebarNav.Entree {
        ReviewSidebarNav.entrees(for: reunion).first { $0.section == .actions }!
    }

    // MARK: - Le scénario du livrable

    @Test("Assigner une action puis en supprimer une donne 2 · 1")
    func assignerPuisSupprimer() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, taches, porteur) = troisActions(in: context)
        try context.save()

        var compteurs = MeetingActionCounts.compute(meeting: reunion)
        #expect(compteurs.retenues == 3)
        #expect(compteurs.sansPorteur == 2)

        // On assigne l'une des deux orphelines…
        taches[1].collaborator = porteur
        taches[1].destinataire = .collaborateur
        // … et on en supprime une déjà assignée.
        context.delete(taches[0])
        try context.save()

        compteurs = MeetingActionCounts.compute(meeting: reunion)
        #expect(compteurs.retenues == 2)
        #expect(compteurs.sansPorteur == 1)

        // Les trois surfaces disent la même chose.
        let kpi = MeetingKPIBuilder.build(meeting: reunion).actions
        #expect(kpi.total == 2)
        #expect(kpi.unassigned == 1)
        #expect(navActions(reunion).complement == .compte(2))
        #expect(navActions(reunion).alerte)
        #expect(lignesDuTableau(reunion) == 2)
    }

    @Test("Une ligne supprimée ne compte plus, même avant le save")
    func suppressionAvantSave() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, taches, _) = troisActions(in: context)
        try context.save()

        context.delete(taches[2])
        // `meeting.tasks` garde la ligne jusqu'au `save()` : c'est
        // exactement l'instant où un compteur naïf ment.
        #expect(reunion.tasks.count == 3)
        #expect(MeetingActionCounts.compute(meeting: reunion).retenues == 2)
        #expect(MeetingKPIBuilder.build(meeting: reunion).actions.total == 2)
        #expect(navActions(reunion).complement == .compte(2))
        #expect(lignesDuTableau(reunion) == 2)

        try context.save()
        #expect(MeetingActionCounts.compute(meeting: reunion).retenues == 2)
    }

    // MARK: - Le symptôme rapporté

    @Test("Deux actions abandonnées quittent le bandeau comme elles quittent le tableau")
    func abandonSuitLeTableau() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, taches, porteur) = troisActions(in: context)
        taches[1].collaborator = porteur
        taches[1].destinataire = .collaborateur
        taches[0].status = .dropped
        taches[2].status = .dropped
        try context.save()

        // Avant le correctif : bandeau « 3 · 2 non assignées », nav
        // « Actions 3 », tableau d'une seule ligne.
        let kpi = MeetingKPIBuilder.build(meeting: reunion).actions
        #expect(kpi.total == 1)
        #expect(kpi.unassigned == 0)
        #expect(navActions(reunion).complement == .compte(1))
        #expect(!navActions(reunion).alerte)
        #expect(lignesDuTableau(reunion) == 1)
    }

    @Test("Une action faite reste au portefeuille et remplit la barre")
    func actionFaiteResteComptee() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, taches, porteur) = troisActions(in: context)
        taches[1].collaborator = porteur
        taches[2].collaborator = porteur
        taches[0].isCompleted = true
        try context.save()

        let compteurs = MeetingActionCounts.compute(meeting: reunion)
        #expect(compteurs.retenues == 3)
        #expect(compteurs.faites == 1)
        #expect(compteurs.ouvertes == 2)
        #expect(compteurs.sansPorteur == 0)
        #expect(abs(compteurs.doneFraction - 1.0 / 3.0) < 0.0001)

        // Cocher toutes les actions ne fait pas tomber le compteur à zéro :
        // c'est la barre qui se remplit, pas le total qui s'évapore.
        taches[1].isCompleted = true
        taches[2].isCompleted = true
        let toutesFaites = MeetingActionCounts.compute(meeting: reunion)
        #expect(toutesFaites.retenues == 3)
        #expect(toutesFaites.doneFraction == 1)
        #expect(MeetingKPIBuilder.build(meeting: reunion).actions.total == 3)
    }

    @Test("Un nom non résolu vaut un porteur, et une action faite n'a plus de dette")
    func porteurEtDette() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, taches, _) = troisActions(in: context)
        // L'extraction a nommé quelqu'un que la base ne connaît pas.
        taches[1].unresolvedAssigneeName = "  Nathalie Lefèvre "
        // Une orpheline cochée : elle n'est plus « à assigner ».
        taches[2].isCompleted = true
        try context.save()

        let compteurs = MeetingActionCounts.compute(meeting: reunion)
        #expect(compteurs.retenues == 3)
        #expect(compteurs.sansPorteur == 0)
        #expect(MeetingKPIBuilder.build(meeting: reunion).actions.unassigned == 0)
        #expect(!navActions(reunion).alerte)
    }

    @Test("Sans action retenue, la barre reste vide et l'entrée est atone")
    func aucuneAction() throws {
        let context = ModelContext(try makeContainer())
        let (reunion, taches, _) = troisActions(in: context)
        for tache in taches { tache.status = .dropped }
        try context.save()

        let compteurs = MeetingActionCounts.compute(meeting: reunion)
        #expect(compteurs.retenues == 0)
        #expect(compteurs.abandonnees == 3)
        #expect(compteurs.doneFraction == 0)
        #expect(navActions(reunion).complement == .compte(0))
        #expect(navActions(reunion).atone)
    }

    // MARK: - Le bloc « CAPTURÉ CETTE SÉANCE »

    @Test("Une action de la séance puis abandonnée quitte CAPTURÉ CETTE SÉANCE")
    func captureDeSeance() throws {
        let context = ModelContext(try makeContainer())
        let debut = Date().addingTimeInterval(-600)
        let reunion = Meeting(title: "Point Planview", date: debut)
        context.insert(reunion)
        for index in 0..<3 {
            let tache = ActionTask(title: "Action \(index)")
            context.insert(tache)
            tache.meeting = reunion
            tache.createdAt = debut.addingTimeInterval(60)
        }
        try context.save()
        #expect(SessionCapturedSummary.compteurs(meeting: reunion, depuis: debut).actions == 3)

        reunion.tasks[0].status = .dropped
        context.delete(reunion.tasks[1])
        #expect(SessionCapturedSummary.compteurs(meeting: reunion, depuis: debut).actions == 1)
    }

    // MARK: - Une seule définition, lue dans le corps des vues

    /// Le chemin d'un fichier de source depuis `Tests/`.
    private func source(_ chemin: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/
            .deletingLastPathComponent()      // racine
            .appendingPathComponent(chemin)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Tous les `.swift` d'un répertoire, récursivement.
    private func sources(sous chemin: String) -> [(nom: String, texte: String)] {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(chemin)
        guard let parcours = FileManager.default.enumerator(atPath: racine.path) else { return [] }
        var trouves: [(String, String)] = []
        for cas in parcours {
            guard let relatif = cas as? String, relatif.hasSuffix(".swift") else { continue }
            let url = racine.appendingPathComponent(relatif)
            if let texte = try? String(contentsOf: url, encoding: .utf8) {
                trouves.append(("\(chemin)/\(relatif)", texte))
            }
        }
        return trouves
    }

    /// Les mots qui trahissent un décompte mémorisé.
    private static let motsDeCompteur = [
        "count", "nombre", "compte", "total", "kpi",
        "porteur", "responsable", "unassigned", "assignee"
    ]

    @Test("Aucun compteur d'actions mémorisé dans Spaces/** et Review/**")
    func aucunCompteurMemorise() {
        let fichiers = sources(sous: "OneToOne/Views/Meeting/Spaces")
        // Sans cette garde, le test passerait sur un répertoire introuvable.
        #expect(fichiers.count > 15)
        #expect(fichiers.contains { $0.nom.hasSuffix("Review/ActionsTable.swift") })

        var fautes: [String] = []
        for fichier in fichiers {
            for ligne in fichier.texte.split(separator: "\n", omittingEmptySubsequences: false) {
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                guard !nette.hasPrefix("//"), !nette.hasPrefix("///") else { continue }
                guard nette.contains("@State") || nette.contains("@StateObject") else { continue }
                let minuscule = nette.lowercased()
                if Self.motsDeCompteur.contains(where: { minuscule.contains($0) }) {
                    fautes.append("\(fichier.nom) : \(nette)")
                }
            }
        }
        // Un compteur en `@State` ne suit ni une suppression ni une
        // réassignation : il se calcule dans `body`, sur les données observées.
        #expect(fautes.isEmpty, "Compteurs mémorisés : \(fautes.joined(separator: " | "))")
    }

    @Test("Le modèle d'écran ne mémorise aucun décompte d'actions")
    func modeleDEcranSansCompteur() {
        for chemin in ["OneToOne/Views/Meeting/MeetingScreenModel.swift",
                       "OneToOne/Views/Meeting/Spaces/Review/ReviewState.swift"] {
            let texte = source(chemin)
            #expect(!texte.isEmpty)
            for ligne in texte.split(separator: "\n") {
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                guard nette.hasPrefix("var ") || nette.hasPrefix("private(set) var ") else { continue }
                // Une propriété **calculée** est admise : elle se réévalue.
                guard !nette.contains("{") else { continue }
                let minuscule = nette.lowercased()
                #expect(!Self.motsDeCompteur.contains { minuscule.contains($0) },
                        "\(chemin) mémorise un décompte : \(nette)")
            }
        }
    }

    @Test("Toutes les surfaces à compteur passent par MeetingActionCounts")
    func surfacesBrancheesSurLaSourceUnique() {
        let surfaces = [
            "OneToOne/Services/Meeting/MeetingKPIBuilder.swift",
            "OneToOne/Views/Meeting/Spaces/Review/ReviewSidebarNav.swift",
            "OneToOne/Views/Meeting/Spaces/Review/ActionsTable.swift",
            "OneToOne/Views/Meeting/Spaces/Rail/ActionsRail.swift",
            "OneToOne/Views/Meeting/Spaces/Rail/ActionsRailGrouping.swift",
            "OneToOne/Views/Meeting/Spaces/MeetingReportSpace.swift",
            "OneToOne/Views/Meeting/Session/SessionCapturedSummary.swift"
        ]
        for chemin in surfaces {
            let texte = source(chemin)
            #expect(!texte.isEmpty, "source introuvable : \(chemin)")
            #expect(texte.contains("MeetingActionCounts."),
                    "\(chemin) recompte les actions au lieu de lire MeetingActionCounts")
        }
        // Et plus personne ne compte la relation brute dans ces fichiers.
        for chemin in surfaces {
            let texte = source(chemin)
            for ligne in texte.split(separator: "\n") {
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                guard !nette.hasPrefix("//"), !nette.hasPrefix("///") else { continue }
                #expect(!nette.contains("meeting.tasks.count"),
                        "\(chemin) compte `meeting.tasks` sans filtre : \(nette)")
            }
        }
    }
}
