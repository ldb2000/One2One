import Foundation

/// Les trois temps de la colonne centrale d'un entretien (spec §3.3 : « notes
/// en trois temps ») — **pur**.
///
/// La spec ne crée pas de colonne « section » : elle décrit une progression
/// (comment ça va → ses sujets → feedback dans les deux sens) que l'écran rend
/// visible. La répartition se déduit donc de ce que les notes portent déjà :
///
/// - `③` prend les notes `kind: .feedback` — c'est la seule section que la
///   nature de la note désigne sans ambiguïté ;
/// - `①` prend la **première ligne** de la séance, chronologiquement : la
///   question « comment ça va » est la première posée, et sa réponse est la
///   première chose écrite. C'est une convention, assumée, et c'est celle que
///   montre la capture (`02:40` sous `① COMMENT ÇA VA`, tout le reste sous
///   `②`) ;
/// - `②` prend tout le reste, y compris une décision ou un risque tapés en
///   séance : aucune ligne ne doit pouvoir n'apparaître dans aucune section.
///
/// Partagé (`Shared/`) : la capture 5a a la même structure, avec deux cartes de
/// feedback inversées (lot 13).
@MainActor
enum OneOnOneNoteSections {

    /// Les trois sections, dans leur ordre d'affichage.
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case howAreYou, topics, feedback

        var id: String { rawValue }

        /// Le libellé de section, numéro compris : c'est le numéro qui dit que
        /// l'entretien a un ordre.
        var label: String {
            switch self {
            case .howAreYou: return "① COMMENT ÇA VA"
            case .topics:    return "② SES SUJETS"
            case .feedback:  return "③ FEEDBACK — DANS LES DEUX SENS"
            }
        }
    }

    // MARK: - Répartition

    /// Les notes d'une section, dans l'ordre du temps.
    static func notes(_ meeting: Meeting, in section: Section) -> [MeetingNote] {
        let toutes = ordered(meeting)
        let feedback = toutes.filter { $0.kind == .feedback }
        let autres = toutes.filter { $0.kind != .feedback }

        switch section {
        case .feedback:
            return feedback
        case .howAreYou:
            return Array(autres.prefix(1))
        case .topics:
            return Array(autres.dropFirst())
        }
    }

    /// Les notes triées et **nettoyées des lignes vides**.
    ///
    /// Une ligne vide est un marqueur posé par `⌘M` en mode séance (lot 4,
    /// D4.1) : elle porte un repère sur l'axe temps, pas une phrase. La compter
    /// comme « première ligne » enverrait la réponse à `① COMMENT ÇA VA` dans
    /// `② SES SUJETS`.
    private static func ordered(_ meeting: Meeting) -> [MeetingNote] {
        MeetingNoteStore.sorted(meeting.timedNotes)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Feedback dans les deux sens

    /// Les notes d'une des deux cartes de `③`.
    ///
    /// C'est `authorSide` qui décide, pas la commande : la même `/feedback`
    /// sert dans les deux cartes (cf. `NoteCommandParser.FeedbackSection`).
    static func feedback(_ meeting: Meeting,
                         _ card: NoteCommandParser.FeedbackSection) -> [MeetingNote] {
        notes(meeting, in: .feedback).filter { note in
            switch card {
            case .given:    return note.authorSide == .me
            case .received: return note.authorSide != .me
            }
        }
    }

    /// `CE QUE JE LUI DIS` / `CE QU'IL ME DIT` — les titres de la capture 2a.
    static func cardLabel(_ card: NoteCommandParser.FeedbackSection) -> String {
        switch card {
        case .given:    return "CE QUE JE LUI DIS"
        case .received: return "CE QU'IL ME DIT"
        }
    }

    // MARK: - Complétude

    /// Vrai quand les **deux** cartes de feedback sont renseignées (spec §3.3 :
    /// « les deux sont obligatoires pour marquer le 1:1 complet — indicateur de
    /// qualité, non bloquant »).
    static func isComplete(_ meeting: Meeting) -> Bool {
        !feedback(meeting, .given).isEmpty && !feedback(meeting, .received).isEmpty
    }

    /// `1:1 complet`, ou `nil`.
    ///
    /// Rien à afficher tant que ce n'est pas complet : un « incomplet »
    /// permanent en tête d'écran deviendrait du décor qu'on ne lit plus, et
    /// l'indicateur n'est pas bloquant.
    static func completenessLabel(_ meeting: Meeting) -> String? {
        isComplete(meeting) ? "1:1 complet" : nil
    }

    // MARK: - Invites (chantier 1, critère n° 1)

    /// L'invite d'une section vide : toujours une action, jamais le constat du
    /// manque.
    static func emptyInvite(for section: Section) -> String {
        switch section {
        case .howAreYou:
            return "Choisissez un cran ci-dessus, puis écrivez ce qu'il en dit."
        case .topics:
            return "Un sujet abordé, une ligne : tapez dans le composeur en bas."
        case .feedback:
            return "Deux cartes à remplir : ce que vous lui dites, ce qu'il vous dit."
        }
    }

    /// L'invite d'une carte de feedback vide.
    static func feedbackEmptyInvite(for card: NoteCommandParser.FeedbackSection) -> String {
        switch card {
        case .given:    return "/feedback — ce que vous avez à lui dire"
        case .received: return "/feedback — ce qu'il vous dit, tel qu'il le dit"
        }
    }

    /// Le libellé du bloc privé (spec §3.2 : « point 6 px `accent/oneonone` +
    /// barre gauche 2 px sur le bloc de note »).
    static let privateLabel = "● NOTE PRIVÉE — VOUS SEUL"
}
