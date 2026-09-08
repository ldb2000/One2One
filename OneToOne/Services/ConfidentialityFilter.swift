import Foundation

/// À qui un contenu est destiné. Ce n'est **pas** un compte utilisateur : l'app
/// est mono-utilisateur, l'audience décrit la sortie visée (un rapport de 1:1
/// part vers le collaborateur, un export d'escalade vers les RH).
enum Audience: String, CaseIterable, Sendable {
    /// Moi seul — l'écran, mes archives, mon dossier annuel.
    case me
    /// Le collaborateur du fil 1:1.
    case collaborator
    /// Mon manager (N+1).
    case manager
    /// Les participants d'une réunion projet / équipe.
    case projectTeam
    /// Ressources humaines — n'accède qu'à l'escalade explicite.
    case hr
}

/// Trois niveaux de confidentialité par ligne (spec §3.2). Valeurs brutes
/// persistées, à ne pas renommer.
enum Visibility: String, Codable, CaseIterable, Sendable {
    /// Jamais dans un récap, un export, un rapport ni une réponse de
    /// l'assistant partagé. Défaut du côté collaborateur.
    case `private` = "private"
    /// Visible par les deux personnes du fil. Défaut du côté manager.
    case shared = "shared"
    /// Visible RH / N+1, sur confirmation explicite (D9).
    case escalated = "escalated"

    var label: String {
        switch self {
        case .private:   return "Privé"
        case .shared:    return "Partagé"
        case .escalated: return "Escaladé"
        }
    }
}

/// Porté par toute ligne dont la sortie dépend d'un niveau de confidentialité :
/// `MeetingNote`, `Commitment`, `OneOnOneAgendaItem`.
protocol Confidential {
    var visibility: Visibility { get }
}

/// **La** règle de sortie, écrite une seule fois (spec §8 : « une seule
/// fonction `isExportable(item, audience)` traverse rapport, export, récap 1:1
/// et assistant. Aucune vue ne réimplémente la règle »).
///
/// Cinq lecteurs de texte l'appellent — le prompt de rapport
/// (`AIReportService`), le HTML (`ReportHTMLBuilder`), l'export markdown
/// (`ExportService`), l'indexation RAG (`RAGIndexer`) et le contexte des chats
/// (`ChatbotView`, `MeetingChatView`). Un sixième lecteur ajouté sans passer
/// par ici serait une fuite ; c'est ce que garde
/// `Tests/ConfidentialityFilterTests.swift`.
enum ConfidentialityFilter {

    /// Vrai quand `item` peut sortir vers `audience`.
    ///
    /// La table est exhaustive et sans `default` : un niveau ou une audience
    /// ajoutés doivent obliger à trancher, jamais retomber sur « autorisé ».
    static func isExportable(_ item: some Confidential, for audience: Audience) -> Bool {
        switch item.visibility {
        case .private:
            switch audience {
            case .me: return true
            case .collaborator, .manager, .projectTeam, .hr: return false
            }
        case .shared:
            switch audience {
            case .me, .collaborator, .manager, .projectTeam: return true
            case .hr: return false
            }
        case .escalated:
            switch audience {
            case .me, .manager, .hr: return true
            case .collaborator, .projectTeam: return false
            }
        }
    }

    /// Vrai quand `item` peut être découpé en chunks et indexé (RAG).
    ///
    /// L'index sert l'assistant local, donc l'audience effective est `.me` —
    /// sauf pour les lignes **privées**, que la spec exclut aussi des réponses
    /// de l'assistant. Une ligne privée n'entre donc jamais dans l'index :
    /// c'est plus sûr que de compter sur un filtrage à la lecture, que chaque
    /// nouveau chemin de recherche devrait réappliquer.
    static func isIndexable(_ item: some Confidential) -> Bool {
        item.visibility != .private
    }

    /// Audience implicite d'une réunion, quand aucune n'est choisie
    /// explicitement : un 1:1 côté manager s'adresse au collaborateur, un 1:1
    /// avec mon manager s'adresse à lui, tout le reste à l'équipe projet.
    static func audience(for kind: MeetingKind) -> Audience {
        switch kind {
        case .oneToOne: return .collaborator
        case .manager:  return .manager
        case .global, .project, .work, .note, .workshop: return .projectTeam
        }
    }
}
