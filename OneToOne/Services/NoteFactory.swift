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

    /// Vrai quand une note n'a rien reçu depuis sa fabrication. Prédicat exact
    /// inverse de `make` — il vit donc ici, avec la fabrique, plutôt que dans
    /// la vue.
    ///
    /// Les cinq chemins de création insèrent, sauvegardent et indexent
    /// immédiatement (l'ouverture de `MeetingView` est le seul « éditeur ») :
    /// sans nettoyage, un clic malheureux laisserait une note vide persistée
    /// **et** indexée dans Spotlight. `MeetingView` s'appuie dessus à sa
    /// fermeture pour la reprendre.
    ///
    /// **La liste des champs regardés est celle de ce que l'écran réduit d'une
    /// note permet de remplir** — deux onglets (« Note », « Documents »), le
    /// fil d'Ariane et le menu « ⋯ ». Soit, dans l'ordre du code ci-dessous :
    /// les documents et les thèmes (`MeetingTagEditor` est rendu hors de la
    /// garde de kind du chrome, donc éditable sur une note), le prompt
    /// spécifique (le `TextEditor` de `MeetingDetailsBlock`, atteint par
    /// « ⋯ → Détails de la réunion… », n'est lui non plus sous aucune garde),
    /// le lien calendrier (« ⋯ → Importer Calendrier », que la règle des menus
    /// laisse délibérément actif sur une note), puis le titre et le corps.
    ///
    /// Chacun est une saisie délibérée : la supprimer en silence serait le
    /// dommage même que ce nettoyage cherche à éviter. À l'inverse, ce que la
    /// note tient de sa **création** et non d'une saisie — son projet, son
    /// participant, sa date — ne la retient pas : ils viennent du bouton
    /// cliqué, pas d'une intention de la garder.
    ///
    /// ⚠️ Tout nouvel onglet ou contrôle ouvert à une note doit repasser ici.
    static func isDiscardableEmptyNote(_ meeting: Meeting) -> Bool {
        guard meeting.kind == .note else { return false }
        guard meeting.attachments.isEmpty else { return false }
        guard meeting.tags.isEmpty else { return false }
        // Non vide ⇒ un événement a été importé. C'est le seul marqueur fiable :
        // l'import recopie aussi le titre, mais un événement sans titre laisserait
        // le reste du prédicat vide alors que la note porte désormais un lien.
        guard meeting.calendarEventID.isEmpty else { return false }
        let prompt = meeting.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty else { return false }
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = meeting.liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty && body.isEmpty
    }
}
