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

    /// Vrai quand une note n'a rien reçu depuis sa fabrication : ni titre, ni
    /// corps (aux espaces près), ni pièce jointe. Prédicat exact inverse de
    /// `make` — il vit donc ici, avec la fabrique, plutôt que dans la vue.
    ///
    /// Les cinq chemins de création insèrent, sauvegardent et indexent
    /// immédiatement (l'ouverture de `MeetingView` est le seul « éditeur ») :
    /// sans nettoyage, un clic malheureux laisserait une note vide persistée
    /// **et** indexée dans Spotlight. `MeetingView` s'appuie dessus à sa
    /// fermeture pour la reprendre.
    ///
    /// Ne regarde que ce que l'écran d'une note permet de saisir — corps et
    /// documents (cf. `MeetingView.visibleSections(for:)`). Le projet ou le
    /// participant, posés par la fabrique elle-même, ne comptent pas comme une
    /// saisie de l'utilisateur.
    static func isDiscardableEmptyNote(_ meeting: Meeting) -> Bool {
        guard meeting.kind == .note else { return false }
        guard meeting.attachments.isEmpty else { return false }
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = meeting.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty && body.isEmpty
    }
}
