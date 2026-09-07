import Foundation
import SwiftData

/// Ce qu'une ligne du composeur écrit **en 1:1**, hors de la vue.
///
/// Le composeur du lot 2 (`NoteComposer`) ne connaît qu'un effet : créer une
/// `MeetingNote`. En 1:1, trois des six commandes produisent autre chose —
/// `/engagement` et `/promesse` créent un `Commitment`, `/demande` crée en plus
/// un `OneOnOneAgendaItem` (cf. `NoteCommandParser+OneOnOne`, lot 10). Les
/// **effets** sont ici, et le composeur ne gagne qu'un paramètre optionnel :
/// son fichier appartient au lot 2 et il sert tous les autres types.
///
/// Partagé (`Shared/`) : les captures 5a et 5b passent par le même chemin, avec
/// `role: .collaborator` (lot 13).
@MainActor
struct OneOnOneComposerContext {

    /// Ce qu'une ligne a produit. Trois effets possibles, chacun optionnel :
    /// `/demande` en produit deux, et les séparer en deux appels obligerait
    /// chaque vue à s'en souvenir.
    struct Applied {
        var note: MeetingNote?
        var commitment: Commitment?
        var agenda: OneOnOneAgendaItem?
        /// `/privé` : la vue peut aussi basculer la ligne courante.
        var togglesPrivacy = false
        /// `/action` : le composeur du rail prend la suite.
        var opensActionComposer = false
    }

    let thread: OneOnOneThread
    /// Mon rôle dans le fil : il décide de la visibilité par défaut et du
    /// porteur par défaut d'un engagement.
    let role: OneOnOneSide
    /// La carte de `③ FEEDBACK` où la ligne est saisie — c'est elle qui dit
    /// **qui parle**, pas la commande.
    var section: NoteCommandParser.FeedbackSection = .given

    /// La visibilité par défaut **de la séance** (les pilules `Partagé` /
    /// `Privé` de l'en-tête, spec §3.2 : « la bascule se fait par ligne […] et
    /// par défaut au niveau de la réunion »).
    ///
    /// `nil` = le défaut du rôle. `/privé` prime toujours : une commande
    /// explicite ne se fait pas contredire par un réglage d'en-tête.
    var defaultVisibility: Visibility?

    /// Les pilules à afficher sous le champ.
    var commands: [NoteCommandCatalog.Entry] {
        NoteCommandCatalog.commands(for: OneOnOneThreadStore.meetingKind(for: role), role: role)
    }

    /// Applique la ligne saisie au timecode courant.
    ///
    /// Une seule sauvegarde en fin de course : `/demande` insère deux objets
    /// liés, et sauver entre les deux laisserait un instant une demande sans
    /// note dans l'index RAG.
    @discardableResult
    func apply(_ line: String,
               at t: Double,
               to meeting: Meeting,
               in context: ModelContext) -> Applied {
        let parsed = NoteCommandParser.parseOneOnOne(line, role: role, section: section)
        var resultat = Applied(togglesPrivacy: parsed.togglesPrivacy,
                               opensActionComposer: parsed.opensActionComposer)

        if let brouillon = parsed.note {
            let note = MeetingNote(t: t,
                                   text: brouillon.text,
                                   kind: brouillon.kind,
                                   visibility: resolved(brouillon.visibility, parsed),
                                   authorSide: brouillon.authorSide,
                                   orderIndex: MeetingNoteStore.nextOrderIndex(at: t, in: meeting))
            context.insert(note)
            note.meeting = meeting
            resultat.note = note
        }

        if let brouillon = parsed.commitment {
            let engagement = Commitment(text: brouillon.text,
                                        ownerSide: brouillon.ownerSide,
                                        promisedAt: meeting.date,
                                        visibility: resolved(brouillon.visibility, parsed))
            context.insert(engagement)
            engagement.thread = thread
            engagement.promisedInMeeting = meeting
            resultat.commitment = engagement
        }

        if let brouillon = parsed.agenda {
            let sujet = OneOnOneAgendaItem(text: brouillon.text,
                                           addedBySide: brouillon.addedBySide,
                                           order: nextAgendaOrder(),
                                           visibility: resolved(brouillon.visibility, parsed),
                                           kind: brouillon.kind,
                                           requestStatus: .pending,
                                           requestedAt: meeting.date)
            context.insert(sujet)
            sujet.thread = thread
            sujet.meeting = meeting
            resultat.agenda = sujet
        }

        if resultat.note != nil || resultat.commitment != nil || resultat.agenda != nil {
            try? context.save()
        }
        return resultat
    }

    /// La visibilité effective d'une ligne : celle de la commande quand elle
    /// est explicite (`/privé`), sinon le défaut de la séance, sinon celui du
    /// rôle (que le parseur a déjà résolu).
    private func resolved(_ fromCommand: Visibility,
                          _ parsed: NoteCommandParser.OneOnOneParsed) -> Visibility {
        guard parsed.basePill != .secret else { return fromCommand }
        return defaultVisibility ?? fromCommand
    }

    /// Le rang du prochain sujet d'ordre du jour : à la fin, comme une saisie
    /// au clavier le laisse attendre.
    func nextAgendaOrder() -> Int {
        (thread.agendaItems.map(\.order).max() ?? -1) + 1
    }
}
