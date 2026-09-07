import Foundation
import SwiftData

/// Une phrase de transcription devient une action, une décision ou une
/// citation (spec §2.4, critère d'acceptation n° 2 du chantier 1 : « créer une
/// action depuis une phrase de transcription prend un clic et conserve
/// `sourceRef` »).
///
/// Le nettoyage est **pur** et le lexique **court** : trois amorces
/// d'obligation, une poignée d'hésitations, un test de terminaison
/// d'infinitif. Une liste longue finirait par réécrire des phrases qu'elle n'a
/// pas comprises — et un titre d'action faux est pire qu'un titre verbeux.
/// Aucun modèle de langue ici : la création doit rester instantanée et
/// fonctionner hors ligne.
enum ActionFromPhrase {

    /// Longueur maximale d'un titre. Au-delà, coupe sur une frontière de mot et
    /// ajoute `…` : la carte du rail affiche deux lignes de 11,5 px, et un
    /// titre de trois cents caractères y devient illisible.
    static let maxTitleLength = 120

    /// Titre de secours quand la phrase ne laisse rien d'exploitable — une
    /// action sans titre serait introuvable dans le rail.
    static let fallbackTitle = "Action depuis la transcription"

    // MARK: - Nettoyage (pur)

    /// Phrase → titre d'action : hésitations retirées, guillemets encadrants
    /// retirés, amorce d'obligation remplacée par l'infinitif qu'elle
    /// annonce, ponctuation finale retirée, majuscule initiale, longueur
    /// bornée.
    static func title(from phrase: String) -> String {
        clean(phrase, dropObligationPrefix: true)
    }

    /// Phrase → texte de décision. **Sans** mise à l'infinitif : une décision
    /// se lit telle qu'elle a été prononcée (« le partenaire finalise »), et
    /// l'infinitif en ferait une action.
    static func decisionText(from phrase: String) -> String {
        clean(phrase, dropObligationPrefix: false)
    }

    /// Texte inséré par `Citer dans la note` : `« texte » — Locuteur, mm:ss`.
    /// La phrase est reprise **telle quelle**, ponctuation comprise : une
    /// citation qu'on nettoie n'est plus une citation.
    static func quotation(phrase: String, speakerName: String?, t: Double) -> String {
        let texte = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let timecode = MeetingPlayhead.mmss(t)
        if let speakerName, !speakerName.isEmpty {
            return "« \(texte) » — \(speakerName), \(timecode)"
        }
        return "« \(texte) » — \(timecode)"
    }

    /// Brouillon depuis les valeurs brutes d'une phrase — la forme testable,
    /// sans avoir à monter une vue.
    ///
    /// Rend l'`ActionDraft` du lot 3 : le contrat vers le composeur du rail est
    /// unique, et `suggestedOwner` porte un `Collaborator` plutôt qu'un nom —
    /// le composeur doit pouvoir l'affecter, pas seulement l'afficher.
    @MainActor
    static func draft(phrase: String,
                      kind: SourceRef.Kind = .transcript,
                      stableID: UUID,
                      t: Double,
                      speaker: Collaborator? = nil) -> ActionDraft {
        ActionDraft(title: title(from: phrase),
                    sourceRef: SourceRef(kind: kind, stableID: stableID, t: t),
                    suggestedOwner: speaker)
    }

    // MARK: - Fabriques

    /// Brouillon depuis un segment de transcription : la source est le segment,
    /// le responsable suggéré son locuteur (règle 1 d'`OwnerSuggestion`).
    @MainActor
    static func draft(from segment: TranscriptSegment) -> ActionDraft {
        draft(phrase: segment.text,
              kind: .transcript,
              stableID: segment.ensuredStableID,
              t: segment.startSeconds,
              speaker: segment.speaker)
    }

    /// Crée l'action et la rattache à la réunion. **Un seul appel** : c'est le
    /// clic du bouton `＋ Action` de la colonne de transcription.
    ///
    /// L'action naît en **tête** du rail (`sortOrder` minimal − 1), comme la
    /// spec §2.4 l'exige (« l'action apparaît immédiatement en tête du rail »).
    @MainActor
    @discardableResult
    static func createAction(from segment: TranscriptSegment,
                             in meeting: Meeting,
                             context: ModelContext) -> ActionTask {
        let brouillon = draft(from: segment)
        let action = ActionTask(title: brouillon.title.isEmpty ? fallbackTitle : brouillon.title)
        action.sourceRef = brouillon.sourceRef
        action.collaborator = segment.speaker
        action.sortOrder = (meeting.tasks.map(\.sortOrder).min() ?? 0) - 1
        context.insert(action)
        action.meeting = meeting
        try? context.save()
        return action
    }

    /// Crée la note de décision au timecode du segment, avec la même source.
    @MainActor
    @discardableResult
    static func createDecision(from segment: TranscriptSegment,
                               in meeting: Meeting,
                               context: ModelContext) -> MeetingNote {
        let texte = decisionText(from: segment.text)
        let note = MeetingNote(
            t: segment.startSeconds,
            text: texte,
            kind: .decision,
            visibility: MeetingNoteStore.defaultVisibility(for: meeting.kind),
            orderIndex: MeetingNoteStore.nextOrderIndex(at: segment.startSeconds, in: meeting)
        )
        note.sourceRef = SourceRef(kind: .transcript,
                                   stableID: segment.ensuredStableID,
                                   t: segment.startSeconds)
        context.insert(note)
        note.meeting = meeting
        try? context.save()
        return note
    }

    // MARK: - Lexique

    /// Hésitations et chevilles de langage retirées en tête de phrase.
    private static let hesitations = [
        "euh", "bah", "ben", "donc", "alors", "hein", "voila", "bon",
        "du coup", "en fait", "je pense que", "je crois que"
    ]

    /// Amorces d'obligation, de la plus longue à la plus courte (l'ordre
    /// compte : « il faudrait » avant « il faut »).
    private static let obligationPrefixes = [
        "il faudrait", "il faudra", "il faut", "on devrait", "on doit",
        "je dois", "tu dois", "on va", "on peut", "faudrait", "faut"
    ]

    /// Mots qui finissent comme un infinitif sans en être un. Sans cette
    /// liste, « il faut notre accord » deviendrait « Notre accord ».
    private static let falseInfinitives: Set<String> = [
        "notre", "votre", "autre", "autres", "encore", "ordre", "cadre",
        "chiffre", "titre", "centre", "membre", "nombre", "livre", "lettre",
        "affaire", "histoire", "memoire", "arbre", "sucre", "hier", "premier",
        "dernier", "cher", "fier", "noir", "soir", "air"
    ]

    /// Terminaisons d'infinitif du français (1er, 2e et 3e groupes).
    private static let infinitiveEndings = ["er", "ir", "re", "oir"]

    // MARK: - Implémentation

    private static func clean(_ phrase: String, dropObligationPrefix: Bool) -> String {
        var texte = normalizeSpaces(phrase)
        texte = stripSurroundingQuotes(texte)
        texte = stripHesitations(texte)
        if dropObligationPrefix { texte = stripObligation(texte) }
        texte = stripTrailingPunctuation(texte)
        texte = capitalizeFirst(texte)
        return truncate(texte)
    }

    private static func normalizeSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func stripSurroundingQuotes(_ text: String) -> String {
        var t = text
        let paires: [(Character, Character)] = [
            ("«", "»"), ("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'"), ("\u{2018}", "\u{2019}")
        ]
        var change = true
        while change {
            change = false
            for (ouvrant, fermant) in paires
            where t.first == ouvrant && t.last == fermant && t.count > 1 {
                t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                change = true
            }
        }
        return t
    }

    private static func stripHesitations(_ text: String) -> String {
        var t = text
        var change = true
        while change {
            change = false
            for mot in hesitations where startsWithWord(t, mot) {
                t = String(t.dropFirst(mot.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:…").union(.whitespaces))
                change = true
                break
            }
        }
        return t
    }

    private static func stripObligation(_ text: String) -> String {
        guard let amorce = obligationPrefixes.first(where: { startsWithWord(text, $0) }) else {
            return text
        }
        let reste = String(text.dropFirst(amorce.count))
            .trimmingCharacters(in: .whitespaces)
        // « il faut que le partenaire finalise » n'est pas une construction
        // infinitive : l'amorce reste, sinon le titre change de sujet.
        let repliee = fold(reste)
        guard !startsWithWord(reste, "que"),
              !repliee.hasPrefix("qu'"),
              !repliee.hasPrefix("qu\u{2019}") else { return text }
        guard let premier = reste.split(whereSeparator: { $0.isWhitespace }).first,
              looksInfinitive(String(premier)) else { return text }
        return reste
    }

    /// Vrai quand le mot ressemble à un infinitif : terminaison du 1er, 2e ou
    /// 3e groupe, et absent de la liste des faux amis.
    static func looksInfinitive(_ word: String) -> Bool {
        let replie = fold(word).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…'"))
        guard replie.count >= 4, !falseInfinitives.contains(replie) else { return false }
        return infinitiveEndings.contains { replie.hasSuffix($0) }
    }

    private static func stripTrailingPunctuation(_ text: String) -> String {
        var t = text
        let ponctuation = CharacterSet(charactersIn: ".,;:!?…")
        while let derniere = t.unicodeScalars.last, ponctuation.contains(derniere) {
            t = String(t.unicodeScalars.dropLast())
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let premiere = text.first else { return text }
        return String(premiere).uppercased() + text.dropFirst()
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxTitleLength else { return text }
        let coupe = text.prefix(maxTitleLength)
        // Couper au mot : un titre tronqué au milieu d'un mot se lit comme une
        // faute de saisie, pas comme une coupe.
        let auMot = coupe.lastIndex(of: " ").map { coupe[..<$0] } ?? coupe
        return stripTrailingPunctuation(String(auMot)) + "…"
    }

    /// Vrai si `text` commence par `word` **suivi d'une frontière de mot** :
    /// « bonjour » ne commence pas par « bon ».
    private static func startsWithWord(_ text: String, _ word: String) -> Bool {
        let replie = fold(text)
        guard replie.hasPrefix(word) else { return false }
        let suite = replie.dropFirst(word.count)
        guard let prochain = suite.first else { return true }
        return prochain.isWhitespace || ",;:.…!?'".contains(prochain)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
    }
}
