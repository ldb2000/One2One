import Foundation
import SwiftData
import SwiftUI

enum AIProvider: String, Codable, CaseIterable {
    case claudeOAuth = "Claude OAuth (setup-token)"
    case anthropic = "Claude (API Key)"
    case geminiOAuth = "Gemini OAuth (CLI)"
    case openai = "OpenAI"
    case ollama = "Ollama"
    case gemini = "Gemini (API Key)"

    /// Display name shown in the UI (can differ from rawValue which is stored in DB)
    var displayName: String {
        switch self {
        case .claudeOAuth: return "Claude (setup-token / CLI)"
        case .anthropic: return "Claude (API Key)"
        case .geminiOAuth: return "Gemini OAuth (CLI)"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        case .gemini: return "Gemini (API Key)"
        }
    }
}

@Model
final class AppSettings {
    var singletonKey: String = "default"
    var cloudToken: String = ""
    var apiEndpoint: String = "https://api.openai.com/v1"
    var modelName: String = "gpt-4o"
    var provider: AIProvider = AIProvider.claudeOAuth

    // Per-feature AI toggles
    var useAIForImport: Bool = true
    var useAIForReformulation: Bool = true
    var useAIForWeeklyExport: Bool = true

    // Prompts configurables
    var importPrompt: String = AppSettings.defaultImportPrompt
    var reformulatePrompt: String = AppSettings.defaultReformulatePrompt
    var weeklyExportPrompt: String = AppSettings.defaultWeeklyExportPrompt

    // Meeting chip colors (stored as hex, displayed as Color)
    var meetingParticipantColorHex: String = AppSettings.defaultMeetingParticipantColorHex
    var meetingAbsentColorHex: String = AppSettings.defaultMeetingAbsentColorHex
    var meetingCollaboratorColorHex: String = AppSettings.defaultMeetingCollaboratorColorHex

    static let defaultMeetingParticipantColorHex  = "#C7E8B6"
    static let defaultMeetingAbsentColorHex       = "#F4C7C7"
    static let defaultMeetingCollaboratorColorHex = "#C6D8F0"

    var meetingParticipantColor: Color {
        Color(hex: meetingParticipantColorHex) ?? Color(hex: Self.defaultMeetingParticipantColorHex) ?? .green
    }

    var meetingAbsentColor: Color {
        Color(hex: meetingAbsentColorHex) ?? Color(hex: Self.defaultMeetingAbsentColorHex) ?? .red
    }

    var meetingCollaboratorColor: Color {
        Color(hex: meetingCollaboratorColorHex) ?? Color(hex: Self.defaultMeetingCollaboratorColorHex) ?? .blue
    }

    init(cloudToken: String = "", apiEndpoint: String = "https://api.anthropic.com/v1", modelName: String = "claude-sonnet-4-5", provider: AIProvider = .claudeOAuth) {
        self.cloudToken = cloudToken
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.provider = provider
    }

    static let defaultImportPrompt = """
    Analyse le contenu suivant extrait du fichier "{{fileName}}" (dashboard projets / présentation / compte-rendu).
    Extrais TOUS les projets, collaborateurs, risques et points clés au format JSON structuré.
    Pour chaque projet: code, nom, domaine, phase (Cadrage/Design/Build/Run), statut (Green/Yellow/Red/Unknown), riskLevel (Critique/Élevé/Modéré/Faible), riskDescription, keyPoints, commentaire, collaborateurs.
    Réponds UNIQUEMENT avec le JSON.
    """

    static let defaultReformulatePrompt = """
    Tu es un assistant de prise de notes pour un architecte IT. Reformule et structure les notes d'entretien suivantes.

    Règles:
    - Améliore la clarté et la structure
    - Identifie les points d'action (préfixe: [ACTION])
    - Identifie les décisions prises (préfixe: [DÉCISION])
    - Identifie les risques (préfixe: [RISQUE])
    - Identifie les points importants pour les projets (préfixe: [PROJET: nom])
    - Garde le sens original, ne fabrique pas d'information
    - Format Markdown

    Notes originales:
    {{notes}}
    """

    static let defaultWeeklyExportPrompt = """
    À partir des entretiens de la semaine suivante, génère un rapport hebdomadaire des modifications d'architecture et de l'avancement des projets.

    Règles:
    - Résume les changements d'architecture par projet
    - Liste les décisions prises
    - Liste les risques identifiés
    - Liste les actions en cours
    - Format Markdown structuré

    Entretiens de la semaine:
    {{interviews}}
    """
}

extension Collection where Element == AppSettings {
    var canonicalSettings: AppSettings? {
        first { $0.singletonKey == "default" } ?? first
    }
}
