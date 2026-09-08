import Foundation

/// Les commandes `/` du composeur de notes (spec §1.4, §2.4).
///
/// Pur et sans état : c'est ici que se décide la **nature** d'une ligne — donc
/// sa barre de couleur dans la colonne, son comptage dans le bandeau
/// d'indicateurs et, pour `/privé`, sa sortie ou non vers un rapport. Cette
/// décision ne doit dépendre d'aucun état de vue.
///
/// Deux règles qui n'ont l'air de rien :
/// - la reconnaissance ignore la casse **et les accents** (`/decision` en
///   séance, quand on tape vite, doit marcher comme `/décision`) ;
/// - une commande **inconnue** n'est pas mangée : `« /décison X »` reste du
///   texte, il n'est pas silencieusement transformé ni effacé.
enum NoteCommandParser {

    /// Les commandes de la palette de la spec §1.4. `engagement` est au lot 10
    /// (il crée un `Commitment`, pas une note) et n'est donc pas ici.
    enum Command: String, CaseIterable, Sendable {
        case action
        case decision
        case risk
        case quote
        /// `/privé` : la ligne reste une note, sa visibilité devient `private`.
        case secret
        case feedback
        case promise
        case request
        case proof

        /// Libellé affiché sur la pilule du composeur.
        var pill: String {
            switch self {
            case .action:   return "/action"
            case .decision: return "/décision"
            case .risk:     return "/risque"
            case .quote:    return "/citer"
            case .secret:   return "/privé"
            case .feedback: return "/feedback"
            case .promise:  return "/promesse"
            case .request:  return "/demande"
            case .proof:    return "/preuve"
            }
        }

        /// Nature de note produite. `nil` pour `.action`, qui n'écrit pas de
        /// note mais ouvre le composeur d'action du rail.
        var noteKind: MeetingNoteKind? {
            switch self {
            case .action:   return nil
            case .decision: return .decision
            case .risk:     return .risk
            case .quote:    return .note
            case .secret:   return .note
            case .feedback: return .feedback
            case .promise:  return .promise
            case .request:  return .request
            case .proof:    return .proof
            }
        }

        /// Écritures acceptées, sous forme repliée (sans accent, minuscules).
        var aliases: [String] {
            switch self {
            case .action:   return ["action"]
            case .decision: return ["decision"]
            case .risk:     return ["risque", "risk"]
            case .quote:    return ["citer", "quote"]
            case .secret:   return ["prive", "private"]
            case .feedback: return ["feedback"]
            case .promise:  return ["promesse", "promise"]
            case .request:  return ["demande", "request"]
            case .proof:    return ["preuve", "proof"]
            }
        }
    }

    /// Résultat de l'analyse d'une ligne de composeur.
    struct Parsed: Equatable, Sendable {
        var command: Command?
        /// Nature de la ligne à créer. `.note` par défaut.
        var kind: MeetingNoteKind = .note
        /// Texte débarrassé de la commande.
        var text: String = ""
        /// Visibilité imposée par la commande ; `nil` = défaut du type de
        /// réunion (`MeetingNoteStore.defaultVisibility(for:)`).
        var visibility: Visibility?
        /// Vrai pour `/action` seulement : le composeur du rail prend la suite.
        var opensActionComposer: Bool = false
    }

    /// Les quatre pilules **toujours visibles** sous le composeur (spec §2.4 :
    /// « les commandes `/` visibles en permanence, pas de découverte cachée »).
    static let visiblePills: [Command] = [.action, .decision, .risk, .quote]

    /// Analyse une ligne de composeur.
    static func parse(_ raw: String) -> Parsed {
        let ligne = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ligne.hasPrefix("/") else {
            return Parsed(command: nil, kind: .note, text: ligne)
        }

        let sansBarre = ligne.dropFirst()
        // La commande s'arrête au premier blanc ; le reste est le texte.
        let separateur = sansBarre.firstIndex(where: { $0.isWhitespace })
        let mot = String(separateur.map { sansBarre[..<$0] } ?? sansBarre)
        let reste = separateur.map { String(sansBarre[$0...]) } ?? ""
        let texte = reste.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let commande = command(matching: mot) else {
            // Commande inconnue : la ligne reste telle qu'elle a été tapée.
            return Parsed(command: nil, kind: .note, text: ligne)
        }

        return Parsed(command: commande,
                      kind: commande.noteKind ?? .note,
                      text: texte,
                      visibility: commande == .secret ? .private : nil,
                      opensActionComposer: commande == .action)
    }

    /// Commande correspondant à un mot tapé, accents et casse ignorés.
    static func command(matching word: String) -> Command? {
        let replie = fold(word)
        guard !replie.isEmpty else { return nil }
        return Command.allCases.first { $0.aliases.contains(replie) }
    }

    /// Forme comparable d'un mot : sans accent, en minuscules.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
    }
}
