import Foundation

/// Fabrique la même note quel que soit le point d'entrée : note rapide du
/// menubar, écran « Notes », section Notes d'une fiche, commandes `/ajout-*`
/// de l'assistant. Une note est un `Meeting` de kind `.note`.
///
/// Le corps va dans `liveNotes` — le champ que relie l'onglet du corps de
/// `MeetingView`. Le nom de ce champ est un héritage (« notes live » d'une
/// réunion enregistrée) ; le renommer traverserait la sauvegarde et les
/// gabarits de rapport, il est donc conservé tel quel.
enum NoteFactory {

    /// Crée une note **sans l'insérer** dans un contexte : l'appelant
    /// `insert` puis `save`, ce qui lui laisse le choix du moment.
    static func make(body: String = "",
                     title: String = "",
                     date: Date = Date(),
                     project: Project? = nil,
                     collaborator: Collaborator? = nil) -> Meeting {
        let note = Meeting(title: title, date: date)
        note.kind = .note
        note.liveNotes = body
        note.project = project
        if let collaborator {
            note.participants = [collaborator]
        }
        return note
    }

    /// Vrai quand une réunion de kind `.note` **ne porte rien** : aucun texte,
    /// aucun fichier, aucune relation. C'est la seule propriété dont une
    /// suppression sans confirmation ait besoin, et c'est celle-ci qu'il faut
    /// lire — pas « ce que l'écran d'une note permet de remplir ».
    ///
    /// ⚠️ **Une note n'est pas forcément née note.** Le badge de type du fil
    /// d'Ariane (`MeetingTopChromeBar`) est un `Picker` sur
    /// `MeetingKind.allCases`, rendu sans garde sur **toutes** les réunions :
    /// n'importe quelle réunion peut devenir une note après coup, en portant
    /// tout ce qu'une vraie réunion accumule. Et les réunions naissent sans
    /// titre (`MeetingsListView.addMeeting`). Un prédicat calqué sur l'écran
    /// réduit d'une note supprimerait donc, sans un mot, une réunion
    /// enregistrée, transcrite et rapportée que personne n'a jamais renommée.
    ///
    /// L'asymétrie du risque commande la prudence : une note retenue à tort
    /// n'est qu'une ligne vide de plus dans une liste, tandis qu'une note
    /// supprimée à tort est une perte définitive — et l'autre chemin de
    /// suppression, `MeetingView.deleteMeeting`, passe lui par un
    /// `confirmationDialog` explicite. En cas de doute sur un champ, le retenir.
    ///
    /// Les chemins de création insèrent, sauvegardent et indexent immédiatement :
    /// sans nettoyage, un clic malheureux laisserait une note vide persistée
    /// **et** indexée dans Spotlight. Portée réelle du nettoyage, à ne pas
    /// surestimer — il n'a lieu qu'à la fermeture de `MeetingView` :
    /// - `AllNotesView` est le **seul** chemin qui ouvre la note qu'il crée ;
    ///   c'est celui que ce prédicat protège ;
    /// - les deux chemins de `NotesSection` n'ouvrent plus rien (arbitrage de
    ///   la correction D) : leurs notes vides s'accumulent en liste, sans perte ;
    /// - le popover du menubar et les commandes `/ajout-*` créent la note avec
    ///   un corps déjà saisi, donc jamais vide, et n'ouvrent aucun écran.
    ///
    /// Le nettoyage s'applique par ailleurs à **toute** note ouverte puis
    /// fermée, pas seulement à celle qu'on vient de créer.
    ///
    /// **Ne comptent pas**, parce qu'ils viennent du geste de création et non
    /// d'une saisie : le projet, les participants (y compris ad hoc), la date,
    /// le gabarit de rapport. **Couverts indirectement** : les slides (ce sont
    /// des `MeetingAttachment` de kind « slides »), les métadonnées calendrier
    /// (toutes écrites par les chemins qui posent `calendarEventID`), les
    /// assignations de locuteur (sans objet sans segments) et les drapeaux de
    /// préparation (sans objet sans `prepNotes`).
    static func isDiscardableEmptyNote(_ meeting: Meeting) -> Bool {
        guard meeting.kind == .note else { return false }

        // Relations : toutes en `.cascade`, donc toute collection non vide est
        // du contenu qu'une suppression emporterait avec elle.
        guard meeting.attachments.isEmpty,
              meeting.tags.isEmpty,
              meeting.tasks.isEmpty,
              meeting.transcriptChunks.isEmpty,
              meeting.transcriptSegments.isEmpty,
              meeting.reportRevisions.isEmpty,
              meeting.meetingAlerts.isEmpty
        else { return false }

        // Audio, et lien calendrier. Non vide ⇒ un événement a été importé :
        // c'est le marqueur fiable, l'import recopie bien le titre mais un
        // événement sans titre laisserait le reste du prédicat vide.
        guard (meeting.wavFilePath ?? "").isEmpty, meeting.calendarEventID.isEmpty else { return false }

        // Champs structurés du rapport (façades JSON).
        guard meeting.keyPoints.isEmpty,
              meeting.decisions.isEmpty,
              meeting.openQuestions.isEmpty
        else { return false }

        // Tout le texte libre que `Meeting` peut porter, quel que soit l'écran
        // qui l'a rempli avant la conversion en note.
        let freeText = [
            meeting.title, meeting.liveNotes, meeting.notes, meeting.customPrompt,
            meeting.rawTranscript, meeting.mergedTranscript,
            meeting.summary, meeting.shortSummary,
            meeting.prepNotes, meeting.referencedAbsent, meeting.nextDeadline
        ]
        return freeText.allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

}
