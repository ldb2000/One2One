import Foundation
import os

private let projectCardLog = Logger(subsystem: "com.onetoone.app", category: "fiche-projet")

/// Une mise à jour **proposée** de la fiche projet. Le mot compte : rien n'est
/// écrit tant que l'utilisateur n'a pas accepté la ligne (spec §4.3, critère
/// d'acceptation n° 4 du chantier 3).
struct ProjectCardUpdate: Equatable, Sendable, Identifiable {

    /// Les quatre champs que l'assistant a le droit de proposer. La liste est
    /// fermée : un modèle qui invente un champ voit sa ligne écartée, pas
    /// interprétée.
    enum Field: String, Codable, Sendable, CaseIterable {
        case budgetSpent
        case milestoneState
        case status
        case risk

        var label: String {
            switch self {
            case .budgetSpent:    return "Budget consommé"
            case .milestoneState: return "Statut d'un jalon"
            case .status:         return "Statut du projet"
            case .risk:           return "Risque"
            }
        }
    }

    var field: Field
    /// Ce que la proposition désigne : « jalon Marine », « Budget consommé ».
    var label: String
    var current: String
    var proposed: String
    /// La citation qui justifie la proposition : « mm:ss texte ». Sans preuve,
    /// une proposition n'est pas vérifiable — et une fiche projet n'est pas un
    /// endroit où faire confiance à un modèle sur parole.
    var evidence: String

    /// Identité stable pour la feuille de diff : le champ et ce qu'il désigne.
    /// Deux propositions sur le même jalon sont la même ligne.
    var id: String { "\(field.rawValue)|\(label)" }

    /// Le libellé affiché en tête de ligne dans la feuille de diff, et repris
    /// dans l'énumération de l'encart.
    var displayLabel: String { label.isEmpty ? field.label : label }
}

/// L'assistant déduit des mises à jour de la fiche depuis les notes et les
/// décisions de la séance (spec §4.3).
///
/// Trois garde-fous, dans cet ordre :
/// 1. **Rien n'est demandé** sans endpoint configuré ni sans matière : pas
///    d'encart, pas d'erreur, pas d'appel.
/// 2. **Rien n'est levé** : une réponse illisible rend `[]`. Une exception
///    ferait remonter une erreur technique au milieu d'une réunion.
/// 3. **Rien n'est écrit** : `accept` mute un `ProjectCardDraft`, jamais un
///    `Project`. Il faut encore `Enregistrer`.
enum ProjectCardSuggestions {

    /// Temps max accordé à l'appel. L'appelant lance la suggestion en tâche de
    /// fond : l'encart apparaît quand il apparaît.
    static let timeout: TimeInterval = 8

    /// Longueur max du texte source. Au-delà, le prompt coûte plus qu'il ne
    /// rapporte.
    static let maxSourceCharacters = 6_000

    /// Nombre max de propositions retenues. Une fiche n'a que six champs
    /// éditables : au-delà, le modèle brode.
    static let maxUpdates = 6

    // MARK: - Disponibilité

    /// Vrai si un endpoint IA est utilisable. Le test est volontairement
    /// grossier — un modèle choisi — parce qu'il ne doit ni lire le Trousseau
    /// ni toucher au réseau : c'est une condition d'affichage, pas une
    /// validation de configuration. Celle-ci a lieu dans `AIClient`, qui
    /// lèvera, et l'échec se traduira par l'absence d'encart.
    @MainActor
    static func isEndpointConfigured(_ settings: AppSettings) -> Bool {
        !settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Source

    /// Ce que la séance a produit : les notes horodatées, le markdown des notes
    /// libres et les décisions. Pas la transcription entière — la spec §4.3
    /// parle des mises à jour « déduites de la séance », et une transcription
    /// de 23 minutes noierait les deux lignes qui comptent.
    @MainActor
    static func sourceText(meeting: Meeting) -> String {
        var morceaux: [String] = []

        let notes = meeting.timedNotes.sorted { gauche, droite in
            gauche.t == droite.t ? gauche.orderIndex < droite.orderIndex : gauche.t < droite.t
        }
        for note in notes where !note.text.isEmpty {
            morceaux.append("[\(MeetingPlayhead.mmss(note.t))] \(note.text)")
        }

        let libres = meeting.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !libres.isEmpty { morceaux.append(libres) }

        for decision in meeting.decisions where !decision.isEmpty {
            morceaux.append("Décision : \(decision)")
        }

        let assemble = morceaux.joined(separator: "\n")
        guard assemble.count > maxSourceCharacters else { return assemble }
        return String(assemble.prefix(maxSourceCharacters))
    }

    // MARK: - Prompt

    /// Le prompt porte l'état **courant** de la fiche : sans lui, le modèle
    /// propose des « mises à jour » identiques à ce qui est déjà écrit.
    static func buildPrompt(source: String, card: ProjectCardState) -> String {
        var etat: [String] = ["Statut : \(card.statusLabel)"]
        if let budget = card.budget {
            etat.append("Budget consommé : \(budget.text)")
        } else {
            etat.append("Budget consommé : inconnu")
        }
        for jalon in card.milestones {
            let suffixe = jalon.trailingText.isEmpty ? "" : " (\(jalon.trailingText))"
            etat.append("Jalon : \(jalon.label) — \(jalon.state.label)\(suffixe)")
        }
        for risque in card.risks {
            etat.append("Risque connu : \(risque.title)")
        }

        return """
        Voici la fiche d'un projet, telle qu'elle est enregistrée aujourd'hui :
        \(etat.joined(separator: "\n"))

        Voici ce qui s'est dit et écrit pendant la réunion :
        \"\"\"
        \(source)
        \"\"\"

        Repère les mises à jour de la fiche que la réunion justifie. N'en invente
        aucune : si rien ne change, renvoie une liste vide. Chaque proposition
        doit citer le passage qui la justifie.

        Réponds exclusivement en JSON strict, conforme à ce schéma :
        {"updates":[{"field":"budgetSpent|milestoneState|status|risk","label":"…","current":"…","proposed":"…","evidence":"mm:ss texte"}]}

        - `field` : uniquement l'une des quatre valeurs ci-dessus.
        - `label` : ce que la proposition désigne (« jalon Marine », « Budget consommé »).
        - `current` : la valeur enregistrée aujourd'hui.
        - `proposed` : la valeur à écrire. Pour `status`, l'une de « Sous contrôle »,
          « À surveiller », « En risque ». Pour `milestoneState`, l'un de « Prévu »,
          « En cours », « Fait », « bloqué ». Pour `budgetSpent`, un montant en euros.
          Pour `risque`, le libellé du risque à ajouter.
        - `evidence` : le timecode et la citation qui justifient la proposition.
        - Pas de texte avant ou après le JSON. Pas de bloc markdown.
        """
    }

    // MARK: - Analyse

    /// Analyse la réponse. **Ne lève jamais** : une réponse illisible rend
    /// `[]`, ce qui fait disparaître l'encart et rien de plus.
    static func parse(_ raw: String) -> [ProjectCardUpdate] {
        let propre = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, let data = propre.data(using: .utf8) else { return [] }

        struct Enveloppe: Decodable {
            var updates: [Ligne]?
        }
        struct Ligne: Decodable {
            var field: String
            var label: String?
            var current: String?
            var proposed: String?
            var evidence: String?
        }

        let enveloppe: Enveloppe
        do {
            enveloppe = try JSONDecoder().decode(Enveloppe.self, from: data)
        } catch {
            projectCardLog.info("suggestions : réponse inexploitable, aucun encart")
            return []
        }

        var retenues: [ProjectCardUpdate] = []
        var vues = Set<String>()
        for ligne in enveloppe.updates ?? [] {
            guard let champ = ProjectCardUpdate.Field(rawValue: ligne.field) else { continue }
            let propose = (ligne.proposed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !propose.isEmpty else { continue }
            let proposition = ProjectCardUpdate(
                field: champ,
                label: (ligne.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                current: (ligne.current ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                proposed: propose,
                evidence: (ligne.evidence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard vues.insert(proposition.id).inserted else { continue }
            retenues.append(proposition)
            if retenues.count == maxUpdates { break }
        }
        return retenues
    }

    /// Enlève un éventuel bloc de code markdown autour du JSON. Les modèles en
    /// ajoutent un même quand on le leur interdit ; `AIReportService` a la même
    /// tolérance.
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

    // MARK: - Demande

    /// Demande les mises à jour au modèle configuré. **Non lançante** : sans
    /// endpoint, sans matière, sur erreur ou sur timeout, rend `[]`.
    @MainActor
    static func suggest(meeting: Meeting,
                        card: ProjectCardState,
                        settings: AppSettings,
                        client: AIClientProtocol = AIClient.live) async -> [ProjectCardUpdate] {
        guard isEndpointConfigured(settings) else { return [] }
        let source = sourceText(meeting: meeting)
        guard !source.isEmpty else { return [] }

        let prompt = buildPrompt(source: source, card: card)
        do {
            let brut = try await withTimeout(seconds: timeout) {
                try await client.send(prompt: prompt, settings: settings)
            }
            return parse(brut)
        } catch {
            projectCardLog.error("suggestions : échec \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Acceptation

    /// Applique **une** proposition au brouillon. Rend `false` si elle est
    /// inapplicable — un jalon inconnu, un montant illisible, un statut hors
    /// des trois valeurs : dans ce cas rien n'est modifié et l'interface garde
    /// la ligne, à l'utilisateur de trancher à la main. Deviner serait la seule
    /// façon de contourner la validation humaine.
    static func accept(_ update: ProjectCardUpdate, in draft: inout ProjectCardDraft) -> Bool {
        switch update.field {
        case .status:
            guard let statut = statut(depuis: update.proposed) else { return false }
            draft.status = statut
            return true

        case .budgetSpent:
            guard let montant = montant(depuis: update.proposed) else { return false }
            draft.budgetSpent = montant
            return true

        case .milestoneState:
            guard let etat = etatDeJalon(depuis: update.proposed),
                  let index = indexDeJalon(nomme: update.label, dans: draft) else { return false }
            draft.milestones[index].state = etat
            return true

        case .risk:
            let titre = update.proposed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !titre.isEmpty else { return false }
            // Un risque proposé arrive « Modéré » : la gravité est un jugement,
            // et le modèle n'a pas à le porter. L'utilisateur la relève lui-même.
            draft.risks.append(.init(id: UUID(), title: titre, severity: "Modéré", existing: nil))
            return true
        }
    }

    /// Reconnaît un statut par son libellé français ou par sa valeur brute.
    static func statut(depuis texte: String) -> ProjectCardStatus? {
        let clef = normalise(texte)
        for statut in ProjectCardStatus.allCases
        where normalise(statut.label) == clef || normalise(statut.rawValue) == clef
                || normalise(statut.projectStatusRaw) == clef {
            return statut
        }
        return nil
    }

    /// Reconnaît un état de jalon. « bloqué » est le libellé de la capture
    /// pour `late` : la maquette n'écrit jamais « en retard ».
    static func etatDeJalon(depuis texte: String) -> MilestoneState? {
        let clef = normalise(texte)
        if clef == "bloque" { return .late }
        for etat in MilestoneState.allCases
        where normalise(etat.label) == clef || normalise(etat.rawValue) == clef {
            return etat
        }
        return nil
    }

    /// Lit un montant en euros : « 48 000 € », « 48000 », « 48 k€ ».
    /// Rend `nil` plutôt que de deviner — un budget faux est pire qu'un budget
    /// non mis à jour.
    static func montant(depuis texte: String) -> Double? {
        let sansEspaces = texte
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let milliers = sansEspaces.lowercased().hasSuffix("k")
        let chiffres = milliers ? String(sansEspaces.dropLast()) : sansEspaces
        guard !chiffres.isEmpty,
              chiffres.allSatisfy({ $0.isNumber || $0 == "." }),
              let valeur = Double(chiffres) else { return nil }
        return milliers ? valeur * 1_000 : valeur
    }

    /// Retrouve le jalon désigné par un libellé approximatif (« jalon
    /// Marine »). Compare sans casse ni accents, dans les deux sens : le modèle
    /// abrège autant qu'il rallonge.
    static func indexDeJalon(nomme libelle: String,
                             dans draft: ProjectCardDraft) -> Int? {
        let mots = normalise(libelle)
            .split(separator: " ")
            .filter { $0.count > 2 && $0 != "jalon" }
        guard !mots.isEmpty else { return nil }
        return draft.milestones.firstIndex { jalon in
            let cible = normalise(jalon.label)
            return mots.allSatisfy { cible.contains($0) }
        }
    }

    private static func normalise(_ texte: String) -> String {
        texte
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Encart

    /// « L'assistant propose 2 mises à jour depuis cette séance : budget
    /// consommé et statut du jalon Marine. » (capture 3b). Vide sans
    /// proposition : l'encart n'existe alors pas.
    static func summary(_ updates: [ProjectCardUpdate]) -> String {
        guard !updates.isEmpty else { return "" }
        let noms = updates.map(\.displayLabel)
        let enumeration: String
        if noms.count == 1 {
            enumeration = noms[0]
        } else {
            enumeration = noms.dropLast().joined(separator: ", ") + " et " + noms[noms.count - 1]
        }
        let pluriel = updates.count == 1 ? "mise à jour" : "mises à jour"
        return "L'assistant propose \(updates.count) \(pluriel) depuis cette séance : \(enumeration)."
    }

    // MARK: - Timeout

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
