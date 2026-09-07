import Foundation
import SwiftData
import os

private let noteStoreLog = Logger(subsystem: "com.onetoone.app", category: "notes")

/// Les règles des notes horodatées, hors de toute vue : tri, filtres,
/// exportabilité, mise en forme, et la reprise unique de `Meeting.liveNotes`.
///
/// Tout ce qui décide **quel texte sort** passe par
/// `ConfidentialityFilter` — jamais par une comparaison de `visibility` écrite
/// dans un lecteur. Les cinq lecteurs de texte de l'app (prompt de rapport,
/// HTML, export markdown, index RAG, contexte des chats) appellent
/// `contextBlock(for:audience:)` ou `exportable(_:for:)`.
enum MeetingNoteStore {

    // MARK: - Fonctions pures

    /// Classe par timecode croissant, puis par ordre manuel à timecode égal —
    /// le cas courant à `t = 0` (notes reprises, notes hors séance).
    static func sorted(_ notes: [MeetingNote]) -> [MeetingNote] {
        notes.sorted { gauche, droite in
            if gauche.t != droite.t { return gauche.t < droite.t }
            if gauche.orderIndex != droite.orderIndex { return gauche.orderIndex < droite.orderIndex }
            return gauche.createdAt < droite.createdAt
        }
    }

    /// Ne garde que les lignes de nature `kind`. `nil` ne filtre rien — les
    /// vues passent directement leur sélection courante.
    static func filtered(_ notes: [MeetingNote], kind: MeetingNoteKind?) -> [MeetingNote] {
        guard let kind else { return notes }
        return notes.filter { $0.kind == kind }
    }

    /// Regroupe par la clé donnée, chaque groupe restant trié.
    static func grouped<Clef: Hashable>(by clef: KeyPath<MeetingNote, Clef>,
                                        _ notes: [MeetingNote]) -> [Clef: [MeetingNote]] {
        Dictionary(grouping: sorted(notes)) { $0[keyPath: clef] }
    }

    /// Les lignes qui peuvent sortir vers `audience`, triées.
    static func exportable(_ notes: [MeetingNote], for audience: Audience) -> [MeetingNote] {
        sorted(notes).filter { ConfidentialityFilter.isExportable($0, for: audience) }
    }

    /// Les lignes qui peuvent entrer dans l'index sémantique, triées.
    static func indexable(_ notes: [MeetingNote]) -> [MeetingNote] {
        sorted(notes).filter { ConfidentialityFilter.isIndexable($0) }
    }

    /// Une ligne par note, horodatée : `- [04:12] (Décision) texte`. La nature
    /// n'est rendue que quand elle n'est pas `note`, pour ne pas alourdir la
    /// liste courante.
    static func markdown(_ notes: [MeetingNote]) -> String {
        sorted(notes).map { note in
            let nature = note.kind == .note ? "" : "(\(note.kind.label)) "
            return "- [\(MeetingPlayhead.mmss(note.t))] \(nature)\(note.text)"
        }
        .joined(separator: "\n")
    }

    /// Bloc de contexte prêt à injecter dans un prompt, un HTML ou un export —
    /// **filtré** pour `audience`. Chaîne vide quand rien ne sort : un en-tête
    /// « Notes de la séance » suivi du vide invite un modèle à combler le trou.
    static func contextBlock(for meeting: Meeting, audience: Audience) -> String {
        let notes = exportable(meeting.timedNotes, for: audience)
        guard !notes.isEmpty else { return "" }
        return markdown(notes)
    }

    /// Visibilité par défaut d'une ligne selon le type de réunion (spec §3.2).
    ///
    /// Le côté **collaborateur** (`.manager` : mon 1:1 avec mon manager) est
    /// privé par défaut : ce que j'écris sur mon propre entretien ne doit pas
    /// se retrouver dans un récap sans un geste explicite. Le côté manager
    /// (`.oneToOne`) est partagé, le récap étant destiné au collaborateur.
    static func defaultVisibility(for kind: MeetingKind) -> Visibility {
        switch kind {
        case .manager:
            return .private
        case .oneToOne, .global, .project, .work, .note, .workshop:
            return .shared
        }
    }

    // MARK: - Reprise des notes libres

    /// Reprend `meeting.liveNotes` en **une** note `t = 0` à la première
    /// ouverture d'une réunion non migrée (D1), puis pose `notesMigrated`.
    ///
    /// Trois garde-fous :
    /// - `liveNotes` **n'est pas effacé** : l'éditeur markdown des réunions de
    ///   type `Note`, les gabarits de rapport et `NoteMergeService` le lisent
    ///   encore. Il ne peut donc pas servir de marqueur de reprise, d'où le
    ///   drapeau `notesMigrated`.
    /// - Aucune ligne n'est créée pour un `liveNotes` vide ou blanc — mais le
    ///   drapeau est quand même posé, sinon chaque ouverture rejouerait la
    ///   tentative.
    /// - Idempotent : un second appel rend `nil` sans rien écrire. L'appel vit
    ///   dans le `onAppear` de `MeetingView`, qui se rejoue à chaque
    ///   remontage de la vue.
    ///
    /// - Returns: la note créée, ou `nil` si rien n'était à reprendre.
    @MainActor
    @discardableResult
    static func importLiveNotesIfNeeded(_ meeting: Meeting,
                                        in context: ModelContext) -> MeetingNote? {
        guard !meeting.notesMigrated else { return nil }

        let corps = meeting.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corps.isEmpty else {
            meeting.notesMigrated = true
            try? context.save()
            return nil
        }

        let note = MeetingNote(t: 0,
                               text: corps,
                               kind: .note,
                               visibility: defaultVisibility(for: meeting.kind))
        note.meeting = meeting
        context.insert(note)
        meeting.notesMigrated = true
        try? context.save()
        noteStoreLog.info("importLiveNotes: meeting=\(meeting.ensuredStableID.uuidString, privacy: .public) chars=\(corps.count)")
        return note
    }
}
