import Foundation
import os

private let captionLog = Logger(subsystem: "com.onetoone.app", category: "atelier-legende")

/// La légende textuelle d'une planche (spec §7.2 : la barre d'assistant du dock
/// « génère une légende textuelle à partir des libellés d'objets »).
///
/// **Deux étages, et le premier suffit.** La légende est d'abord *calculée* :
/// combien de boîtes, de liaisons, de notes, de tracés, de questions et de
/// risques la scène porte, et comment s'appellent les trois premiers objets. Ce
/// calcul est pur, ne lève jamais, et marche en mode avion — la promesse §8
/// « local d'abord » ne peut pas dépendre d'un modèle. L'assistant ne fait que
/// **réécrire** cette phrase quand un endpoint est configuré ; au moindre
/// problème, c'est la version calculée qui est rendue.
///
/// Le prompt ne transporte jamais la scène : un JSON Excalidraw de 2 000 objets
/// coûterait des dizaines de milliers de jetons pour une phrase, et les
/// `versionNonce` n'apprennent rien à personne. Il transporte la légende pure
/// et les libellés.
enum BoardCaptionBuilder {

    /// Temps max accordé à l'assistant. L'appelant décrit les planches en tâche
    /// de fond : la légende calculée est déjà affichée.
    static let timeout: TimeInterval = 8

    /// Nombre de libellés cités entre parenthèses. Trois : au-delà, la légende
    /// devient une liste et le dock ne peut plus la tenir sur une ligne.
    static let maxLabels = 3

    /// Longueur max d'un libellé cité. Un titre de boîte peut être une phrase
    /// entière ; la légende en garde le début.
    static let maxLabelLength = 40

    /// Longueur max d'une légende venue de l'assistant. Au-delà, ce n'est plus
    /// une légende : la version calculée est rendue.
    static let maxCaptionLength = 240

    // MARK: - Inventaire

    /// Ce que porte une scène, compté sans le moteur.
    struct Inventory: Equatable, Sendable {
        var boxes = 0
        var connectors = 0
        /// Textes libres — un texte sans conteneur, le « post-it » du croquis.
        var notes = 0
        /// Tracés à main levée du mode Manuscrit.
        var strokes = 0
        var images = 0
        var questions = 0
        var risks = 0
        /// Libellés retenus, dans l'ordre de la scène : boîtes puis notes.
        var labels: [String] = []

        var isEmpty: Bool {
            boxes == 0 && connectors == 0 && notes == 0
                && strokes == 0 && images == 0
        }
    }

    /// Compte les objets d'une scène. Une scène illisible rend un inventaire
    /// vide : la planche n'est pas perdue pour autant, sa légende dit
    /// simplement « planche vide ».
    static func inventory(scene: String) -> Inventory {
        var resultat = Inventory()
        guard let data = scene.data(using: .utf8),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = objet["elements"] as? [[String: Any]]
        else { return resultat }

        // Le texte d'une boîte vit dans un élément lié (`containerId`) : on
        // indexe une fois plutôt que de rebalayer par objet.
        var textesLies: [String: String] = [:]
        for element in elements where (element["type"] as? String) == "text" {
            guard let conteneur = element["containerId"] as? String,
                  let texte = element["text"] as? String
            else { continue }
            textesLies[conteneur] = texte
        }

        var libellesDeBoites: [String] = []
        var libellesDeNotes: [String] = []
        var vus = Set<String>()

        func retiens(_ brut: String, dans liste: inout [String]) {
            let propre = normalized(brut)
            guard !propre.isEmpty, vus.insert(propre).inserted else { return }
            liste.append(propre)
        }

        for element in elements {
            guard (element["isDeleted"] as? Bool) != true,
                  let type = element["type"] as? String
            else { continue }
            switch type {
            case "rectangle", "ellipse", "diamond":
                resultat.boxes += 1
                if let id = element["id"] as? String, let texte = textesLies[id] {
                    retiens(texte, dans: &libellesDeBoites)
                }
            case "arrow", "line":
                resultat.connectors += 1
            case "text":
                // Un texte lié à une boîte n'est pas une note : c'est
                // l'étiquette de la boîte, déjà comptée.
                guard element["containerId"] as? String == nil else { continue }
                resultat.notes += 1
                if let texte = element["text"] as? String {
                    retiens(texte, dans: &libellesDeNotes)
                }
            case "freedraw":
                resultat.strokes += 1
            case "image":
                resultat.images += 1
            default:
                continue
            }
        }

        let annotations = BoardAnnotation.list(in: scene)
        resultat.questions = annotations.filter { $0.kind == .question }.count
        resultat.risks = annotations.filter { $0.kind == .risk }.count
        resultat.labels = Array((libellesDeBoites + libellesDeNotes).prefix(maxLabels))
        return resultat
    }

    // MARK: - Légende calculée

    /// La légende d'une planche : « Croquis — 5 boîtes (Runners GitLab, Nexus,
    /// …), 3 liaisons, 1 question ouverte, 1 risque ».
    ///
    /// **Ne lève jamais** et ne rend jamais une chaîne vide : une planche sans
    /// légende afficherait un vide dans la frise de 6b et dans le rapport.
    static func caption(mode: BoardMode, scene: String) -> String {
        let inventaire = inventory(scene: scene)
        guard !inventaire.isEmpty else { return "\(mode.label) — planche vide" }

        var segments: [String] = []
        if inventaire.boxes > 0 {
            var segment = compte(inventaire.boxes, "boîte", "boîtes")
            if !inventaire.labels.isEmpty {
                segment += " (\(enumeration(inventaire.labels, total: inventaire.boxes + inventaire.notes)))"
            }
            segments.append(segment)
        }
        if inventaire.connectors > 0 {
            segments.append(compte(inventaire.connectors, "liaison", "liaisons"))
        }
        if inventaire.notes > 0 {
            var segment = compte(inventaire.notes, "note", "notes")
            // Les libellés sont cités avec les boîtes quand il y en a ; sinon
            // c'est aux notes de les porter, sans quoi un manuscrit de deux
            // lignes se lirait « Manuscrit — 2 notes » et n'apprendrait rien.
            if inventaire.boxes == 0, !inventaire.labels.isEmpty {
                segment += " (\(enumeration(inventaire.labels, total: inventaire.notes)))"
            }
            segments.append(segment)
        }
        if inventaire.strokes > 0 {
            segments.append(compte(inventaire.strokes, "tracé", "tracés"))
        }
        if inventaire.images > 0 {
            segments.append(compte(inventaire.images, "image", "images"))
        }
        if inventaire.questions > 0 {
            segments.append(compte(inventaire.questions, "question ouverte", "questions ouvertes"))
        }
        if inventaire.risks > 0 {
            segments.append(compte(inventaire.risks, "risque", "risques"))
        }

        return "\(mode.label) — \(segments.joined(separator: ", "))"
    }

    // MARK: - Raffinement par l'assistant

    /// Vrai si un endpoint IA est utilisable. Volontairement grossier — un
    /// modèle choisi — parce qu'il ne doit ni lire le Trousseau ni toucher au
    /// réseau : c'est une condition d'appel, pas une validation de
    /// configuration. Même critère que `ProjectCardSuggestions`.
    @MainActor
    static func isEndpointConfigured(_ settings: AppSettings) -> Bool {
        !settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Le prompt : court, et sans la scène. Il donne la légende calculée et les
    /// libellés, et demande une phrase.
    static func buildPrompt(mode: BoardMode, pure: String, labels: [String]) -> String {
        let cites = labels.isEmpty ? "(aucun libellé)" : labels.joined(separator: " | ")
        return """
        Voici une planche d'atelier en mode « \(mode.label) ».

        Inventaire de ses objets : \(pure)
        Libellés relevés sur la planche : \(cites)

        Écris une légende d'une phrase, en français, qui dise ce que cette
        planche montre. N'invente aucun objet, aucun chiffre, aucun nom qui ne
        soit pas ci-dessus. Pas de préambule, pas de guillemets.

        Réponds exclusivement en JSON strict, conforme à ce schéma :
        {"caption":"…"}

        - `caption` : une seule phrase, 240 caractères au maximum.
        - Pas de texte avant ou après le JSON. Pas de bloc markdown.
        """
    }

    /// Analyse la réponse. **Ne lève jamais** : rend `nil` dès que la réponse
    /// n'est pas une légende exploitable, ce qui fait retomber l'appelant sur
    /// la légende calculée.
    static func parse(_ raw: String) -> String? {
        let propre = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, let data = propre.data(using: .utf8) else { return nil }

        struct Enveloppe: Decodable { var caption: String? }
        guard let enveloppe = try? JSONDecoder().decode(Enveloppe.self, from: data),
              let brut = enveloppe.caption
        else {
            captionLog.info("légende : réponse inexploitable, la légende calculée est conservée")
            return nil
        }
        let legende = brut
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legende.isEmpty, legende.count <= maxCaptionLength else { return nil }
        return legende
    }

    /// La légende, raffinée par l'assistant si c'est possible.
    ///
    /// **Non lançante** : sans endpoint, sur erreur, sur timeout ou sur réponse
    /// illisible, rend la légende calculée. Une planche a toujours une légende.
    @MainActor
    static func refined(mode: BoardMode,
                        scene: String,
                        settings: AppSettings,
                        client: AIClientProtocol = AIClient.live) async -> String {
        let pure = caption(mode: mode, scene: scene)
        guard isEndpointConfigured(settings) else { return pure }
        let inventaire = inventory(scene: scene)
        guard !inventaire.isEmpty else { return pure }

        let prompt = buildPrompt(mode: mode, pure: pure, labels: inventaire.labels)
        do {
            let brut = try await withTimeout(seconds: timeout) {
                try await client.send(prompt: prompt, settings: settings)
            }
            return parse(brut) ?? pure
        } catch {
            captionLog.info("légende : l'assistant n'a pas répondu, la légende calculée est conservée")
            return pure
        }
    }

    // MARK: - Outils

    /// `1 boîte` / `5 boîtes`. Le français ne pardonne pas « 1 liaisons ».
    private static func compte(_ nombre: Int, _ singulier: String, _ pluriel: String) -> String {
        "\(nombre) \(nombre == 1 ? singulier : pluriel)"
    }

    /// `Runners GitLab, Nexus, GitLab auto-hébergé, …` — l'ellipse n'apparaît
    /// que s'il reste quelque chose à citer.
    private static func enumeration(_ libelles: [String], total: Int) -> String {
        let cites = libelles.joined(separator: ", ")
        return total > libelles.count ? "\(cites), …" : cites
    }

    /// Aplatit un libellé sur une ligne et le borne. Un titre sur deux lignes
    /// devient une phrase : une légende ne contient pas de retour à la ligne.
    private static func normalized(_ brut: String) -> String {
        let plat = brut
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard plat.count > maxLabelLength else { return plat }
        return String(plat.prefix(maxLabelLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Enlève un éventuel bloc de code markdown autour du JSON. Les modèles en
    /// ajoutent un même quand on le leur interdit ; `ProjectCardSuggestions` et
    /// `AIReportService` ont la même tolérance.
    private static func stripCodeFence(_ texte: String) -> String {
        let coupe = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard coupe.hasPrefix("```") else { return coupe }
        var lignes = coupe.components(separatedBy: "\n")
        if !lignes.isEmpty { lignes.removeFirst() }
        if let derniere = lignes.last,
           derniere.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lignes.removeLast()
        }
        return lignes.joined(separator: "\n")
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let resultat = try await group.next()!
            group.cancelAll()
            return resultat
        }
    }
}
