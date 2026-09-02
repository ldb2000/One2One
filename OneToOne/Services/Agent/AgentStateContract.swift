import Foundation

// MARK: - Types du contrat

/// Ce que l'agent dit avoir fait à la fin d'un tour.
enum AgentTurnState: String, Sendable, CaseIterable {
    case question
    case deliverable = "livrable"
    case blocked = "bloque"
}

/// Nature d'un livrable, qui décide de son atterrissage (brouillon de mail,
/// prompt enregistré, aperçu Markdown, pièce jointe…).
enum AgentDeliverableKind: String, Sendable, CaseIterable {
    case mail
    case prompt
    case markdown = "md"
    case docx
    case pptx
    case xlsx
    case pdf
    /// Repli : tout type que l'on ne sait pas router reste un fichier joint.
    case attachment = "piece-jointe"
}

/// Un fichier déposé par l'agent dans son dossier de travail.
struct AgentDeliverableRef: Equatable, Sendable {
    let path: String       // relatif au dossier de travail
    let kind: AgentDeliverableKind
    let title: String
}

/// Le bilan d'un tour, tel que l'agent l'a écrit dans `etat.json`.
struct AgentTurnReport: Equatable, Sendable {
    let state: AgentTurnState
    let question: String?
    let deliverables: [AgentDeliverableRef]
    let assumptions: [String]
    let summary: String?
}

// MARK: - Lecture

/// Lit `etat.json`, le contrat que l'agent honore à la fin de chaque tour.
///
/// Pourquoi un fichier plutôt que l'outil `AskUserQuestion` : en mode headless
/// sans TTY, `AskUserQuestion` s'auto-résout avec des réponses vides
/// (claude-code#50728). Un fichier est robuste, observable, et survit à un
/// plantage de l'app.
///
/// Les clés sont en français parce que l'agent est instruit en français ; les
/// symboles Swift restent en anglais (`CLAUDE.md`).
enum AgentStateContract {

    enum Failure: Error, Equatable {
        /// Le fichier n'est pas du JSON exploitable.
        case unreadable
        /// Un champ obligatoire manque — le nom est celui de la clé JSON.
        case missingField(String)
        /// `etat` porte une valeur qu'on ne connaît pas.
        case unknownState(String)
        /// Un livrable désigne un fichier hors du dossier de travail.
        case pathOutsideWorkspace(String)
    }

    static func read(_ data: Data) throws -> AgentTurnReport {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.unreadable
        }

        guard let rawState = root["etat"] as? String else { throw Failure.missingField("etat") }
        guard let state = AgentTurnState(rawValue: rawState) else { throw Failure.unknownState(rawState) }

        let question = nonEmpty(root["question"] as? String)
        if state == .question && question == nil { throw Failure.missingField("question") }

        let deliverables = try (root["livrables"] as? [[String: Any]] ?? []).map(deliverable(from:))

        return AgentTurnReport(
            state: state,
            question: question,
            deliverables: deliverables,
            assumptions: (root["hypotheses"] as? [String]) ?? [],
            summary: nonEmpty(root["resume"] as? String)
        )
    }

    // MARK: - Détail

    private static func deliverable(from raw: [String: Any]) throws -> AgentDeliverableRef {
        guard let path = nonEmpty(raw["fichier"] as? String) else { throw Failure.missingField("fichier") }
        try assertConfined(path)

        return AgentDeliverableRef(
            path: path,
            kind: (raw["type"] as? String).flatMap(AgentDeliverableKind.init(rawValue:)) ?? .attachment,
            title: nonEmpty(raw["titre"] as? String) ?? (path as NSString).lastPathComponent
        )
    }

    /// Un livrable doit rester sous le dossier de travail. On **refuse** plutôt
    /// que d'assainir : un chemin qui s'échappe est le signe d'un agent qui a
    /// mal compris sa consigne, pas d'une coquille à rattraper.
    private static func assertConfined(_ path: String) throws {
        let escapes = path.hasPrefix("/")
            || path.hasPrefix("~")
            || (path as NSString).pathComponents.contains("..")
        if escapes { throw Failure.pathOutsideWorkspace(path) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
