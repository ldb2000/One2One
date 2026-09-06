import Foundation

/// Phase de traitement d'une question posée à l'assistant IA, affichée comme indicateur inline
/// pendant l'attente (`ChatbotView`, `MeetingChatView`) : l'utilisateur ne voit sinon qu'un
/// spinner, sans savoir si le pré-fetch RAG tourne ou si le LLM génère (jusqu'à plusieurs
/// minutes sur Ollama).
enum LoadingPhase: Equatable {
    case idle
    /// Construction du prompt (contexte base, pré-fetch RAG, historique) — avant l'appel réseau.
    case loadingContext
    /// Appel au fournisseur IA en cours (LM Studio / Ollama / OpenRouter…).
    case waitingLLM

    /// Libellé affiché ; `nil` pour `.idle` (aucun indicateur à montrer).
    var label: String? {
        switch self {
        case .idle: return nil
        case .loadingContext: return "Chargement du contexte…"
        case .waitingLLM: return "Génération en cours…"
        }
    }

    /// Icône SF Symbols associée ; `nil` pour `.idle`.
    var systemImage: String? {
        switch self {
        case .idle: return nil
        case .loadingContext: return "doc.text.magnifyingglass"
        case .waitingLLM: return "sparkles"
        }
    }
}
