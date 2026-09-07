import Foundation
import SwiftData

/// Le jeu de données de la capture de référence
/// `docs/superpowers/specs/refonte-2026-09/ecrans/6a-atelier-planche.png`.
///
/// Extension séparée : `RefonteDemoSeed.swift` sème la réunion de `1a-cockpit`
/// et plusieurs lots l'intègrent en parallèle — y ajouter l'atelier ferait un
/// conflit à chaque rebase.
///
/// Idempotent par le titre, comme le semis d'origine.
extension RefonteDemoSeed {

    // MARK: - Constantes de la capture

    static let workshopTitle = "Cible d'architecture GitLab — séance de travail"

    /// 62 minutes, la durée de la pilule audio (`34:20 / 62:00`).
    static let workshopDurationSeconds = 3_720

    /// Quatre participants. Les initiales `YP` et `CA` de la pilule de présence
    /// masquée (D11) sont celles des deux premiers.
    static let workshopParticipants: [(nom: String, role: String)] = [
        ("Yann Pichon", "Architecte plateforme"),
        ("Claire-Amélie Rousset", "Ingénieure réseau"),
        ("Patrice Vasseur", "Architecte applicatif"),
        ("Cléva Ferrand", "Responsable données"),
    ]

    /// Les quatre planches du dock, dans l'ordre de la capture. Le troisième
    /// élément est la planche **active** (`Planche 3 sur 4`).
    static let workshopBoards: [(titre: String, mode: BoardMode, t: Double, auteur: String)] = [
        ("Périmètre actuel", .sketch, 495, "Yann"),         // 08:15
        ("Flux réseau", .diagram, 1_180, "Claire-Amélie"),  // 19:40
        ("Cible d'architecture", .sketch, 2_060, "en cours"), // 34:20
        ("Notes de Patrice", .ink, 1_685, "stylet"),        // 28:05
    ]

    /// La scène de la planche active : les boîtes visibles sur la capture.
    static func workshopTargetScene() -> String {
        BoardScene.scene(boxes: [
            .init(x: 60, y: 40, width: 320, height: 100,
                  text: "Runners GitLab\n3 nœuds · autoscale"),
            .init(x: 940, y: 40, width: 290, height: 70,
                  text: "Nexus"),
            .init(x: 490, y: 170, width: 340, height: 100,
                  text: "GitLab auto-hébergé\ngitlab.rb + flux à valider"),
            .init(x: 60, y: 300, width: 320, height: 100,
                  text: "PostgreSQL dédiée\nisolée de la data",
                  stroke: WorkshopPalette.entries[1].hex,
                  background: "#f7faff"),
            .init(x: 940, y: 300, width: 290, height: 100,
                  text: "Jenkins\nà décommissionner",
                  stroke: WorkshopPalette.entries[2].hex,
                  background: "#fbeceb",
                  dashed: true),
            .init(x: 490, y: 440, width: 420, height: 90,
                  text: "Question ouverte : qui porte la bascule des runners ? — Claire-Amélie",
                  stroke: WorkshopPalette.entries[4].hex,
                  background: "#f9efe0"),
            .init(x: 960, y: 460, width: 200, height: 60,
                  text: "à valider\navec Cléva",
                  stroke: WorkshopPalette.entries[1].hex,
                  freeText: true),
        ], seed: 3)
    }

    /// Scène des autres planches : de quoi que la vignette ne soit pas vide et
    /// que la règle §7.1 les traite comme non vides.
    static func workshopScene(forIndex index: Int) -> String {
        switch index {
        case 0:
            return BoardScene.scene(boxes: [
                .init(x: 60, y: 60, width: 300, height: 90, text: "Runners partagés\n(GitLab.com)"),
                .init(x: 460, y: 60, width: 300, height: 90, text: "Jenkins historique"),
            ], seed: 1)
        case 1:
            return BoardScene.scene(boxes: [
                .init(x: 60, y: 60, width: 280, height: 80, text: "DMZ"),
                .init(x: 420, y: 60, width: 280, height: 80, text: "Zone applicative",
                      stroke: WorkshopPalette.entries[1].hex),
                .init(x: 240, y: 220, width: 280, height: 80, text: "Zone données",
                      stroke: WorkshopPalette.entries[3].hex),
            ], seed: 2)
        case 2:
            return workshopTargetScene()
        default:
            return BoardScene.scene(boxes: [
                .init(x: 60, y: 60, width: 360, height: 70,
                      text: "vérifier le quota runners", freeText: true),
                .init(x: 60, y: 150, width: 360, height: 70,
                      text: "qui garde Nexus ?", freeText: true),
            ], seed: 4)
        }
    }

    // MARK: - Semis

    /// Sème la réunion d'atelier et rend la réunion.
    ///
    /// `store` est injectable : un test ne doit pas écrire dans le dossier
    /// `recordings/` de production. Optionnel plutôt que défaut `.shared`, dont
    /// l'évaluation chez l'appelant n'est pas isolée sur l'acteur principal.
    @discardableResult
    static func seedWorkshop(in context: ModelContext, store: BoardStore? = nil) -> Meeting {
        let magasin = store ?? .shared
        let titre = workshopTitle
        if let existante = (try? context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.title == titre })
        ))?.first {
            return existante
        }

        let collaborateurs = seedWorkshopCollaborators(in: context)

        // Semer l'atelier **arme le drapeau** : une réunion de type Atelier
        // dont l'ecran 6a reste desactive ne sert a rien, et la recette
        // n'aurait aucun moyen de l'activer sans passer par les reglages.
        // Le semis est une commande de recette explicite, pas un demarrage.
        armeLeDrapeau(in: context)

        // 4 septembre 2026, 14:00 à Paris — l'après-midi de la séance.
        let reunion = Meeting(title: workshopTitle,
                              date: Date(timeIntervalSince1970: 1_788_523_200),
                              notes: "")
        reunion.kind = .workshop
        reunion.project = seedWorkshopProject(in: context)
        reunion.durationSeconds = workshopDurationSeconds
        reunion.meetingDurationSeconds = workshopDurationSeconds
        reunion.notesMigrated = true
        reunion.shortSummary = "Cible d'architecture GitLab : runners, Nexus, base dédiée, sortie de Jenkins."
        context.insert(reunion)

        for collaborateur in collaborateurs {
            reunion.participants.append(collaborateur)
            reunion.setParticipantStatus(.present, for: collaborateur)
        }

        for (index, description) in workshopBoards.enumerated() {
            let planche = Board(index: index,
                                title: description.titre,
                                mode: description.mode,
                                t: description.t,
                                authorNames: description.auteur)
            context.insert(planche)
            planche.meeting = reunion
            _ = try? magasin.save(scene: workshopScene(forIndex: index),
                                  board: planche,
                                  meetingStableID: reunion.ensuredStableID)
        }

        try? context.save()
        return reunion
    }

    /// Arme `workshopEnabled` dans les reglages canoniques, en les creant si
    /// l'installation n'en a pas encore.
    private static func armeLeDrapeau(in context: ModelContext) {
        let existants = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let reglages = existants.canonicalSettings {
            reglages.workshopEnabled = true
            return
        }
        let reglages = AppSettings()
        reglages.workshopEnabled = true
        context.insert(reglages)
    }

    /// Le projet de la capture — le fil d'Ariane dit
    /// `One2One › S/D — Modernisation CI/CD`.
    private static func seedWorkshopProject(in context: ModelContext) -> Project {
        let nom = "S/D — Modernisation CI/CD"
        let existants = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        if let trouve = existants.first(where: {
            $0.name.localizedCaseInsensitiveCompare(nom) == .orderedSame
        }) {
            return trouve
        }
        let projet = Project(code: "P25_142",
                             name: nom,
                             domain: "S/D",
                             sponsor: "Olivier Freund",
                             phase: "Cadrage",
                             status: "Green")
        context.insert(projet)
        return projet
    }

    /// Réutilise les collaborateurs existants — semer ne doit pas créer un
    /// second « Yann Pichon » dans une base réelle.
    private static func seedWorkshopCollaborators(in context: ModelContext) -> [Collaborator] {
        let existants = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
        return workshopParticipants.map { participant in
            if let trouve = existants.first(where: {
                $0.name.localizedCaseInsensitiveCompare(participant.nom) == .orderedSame
            }) {
                return trouve
            }
            let collaborateur = Collaborator(name: participant.nom, role: participant.role)
            context.insert(collaborateur)
            return collaborateur
        }
    }
}
