import SwiftUI
import SwiftData

/// Les lignes de notes d'un 1:1 **subi**, par section (capture 5a, colonne
/// centrale) : `CE QU'IL M'A DIT` et `CE QUE J'AI DIT`.
///
/// Un fichier d'extension, comme `TimedNotesColumn+OneOnOne.swift` du lot 11 :
/// `TimedNotesColumn` appartient au lot 2, elle sert tous les autres types, et
/// la sectionner de trois façons différentes dans le même fichier la rendrait
/// illisible.
///
/// Trois différences avec la section du 1:1 mené, et chacune vient du rôle :
/// - le libellé du bloc privé est `● POUR MOI SEUL` — ici **toutes** les lignes
///   sont privées, le bloc n'a pas à répéter le mot « privée » ;
/// - une ligne est **désignable** : `Partager la ligne` agit sur celle-là et
///   sur aucune autre (critère chantier 5 n° 2) ;
/// - la bascule du menu passe `role: .collaborator`, ce qui ne change pas la
///   table mais dit qui la demande.
struct CollaboratorNotesSection: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Le titre de la section (`CE QU'IL M'A DIT`).
    let titre: String
    /// Les lignes à rendre, déjà réparties par `CollaboratorSessionModel`.
    let notes: [MeetingNote]
    /// L'invite quand la section est vide (« aucune zone vide sans invite »).
    let invite: String
    /// La section que **cette** vue représente.
    let cible: NoteCommandParser.FeedbackSection
    /// La section où le composeur écrira la prochaine ligne. Cliquer le titre
    /// la change — c'est la section, et non la commande, qui dit qui parle
    /// (même mécanique que `FeedbackCards` au lot 11).
    @Binding var section: NoteCommandParser.FeedbackSection

    @Environment(\.modelContext) private var context
    @State private var editing: PersistentIdentifier?
    @State private var editingText = ""

    /// Vrai quand la réunion a un axe temps. Même règle que `TimedNotesColumn` :
    /// sans axe, le timecode s'écrit `--:--` et ne replace rien.
    private var hasTimeline: Bool {
        meeting.durationSeconds > 0
            || meeting.recordingStartedAt != nil
            || meeting.wavFileURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            entete
            if notes.isEmpty {
                Text(invite)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(notes, id: \.persistentModelID) { note in
                    if note.visibility == .shared {
                        ligne(note)
                    } else {
                        blocConfidentiel(note)
                    }
                }
            }
        }
    }

    // MARK: - En-tête de section

    /// Le titre désigne la section : la prochaine ligne du composeur y va, et
    /// la pastille dit laquelle est armée. Sans ce geste, une seule des deux
    /// sections serait accessible au clavier — le parseur du lot 10 déduit
    /// l'auteur d'une ligne de la **section**, pas de la commande.
    private var entete: some View {
        let active = section == cible
        return Button {
            section = cible
        } label: {
            HStack(spacing: 6) {
                if active {
                    Circle()
                        .fill(One2OneToken.oneOnOne)
                        .frame(width: 5, height: 5)
                }
                SectionLabel(titre)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(active
              ? "Le composeur écrit dans cette section"
              : "Écrire la prochaine ligne dans cette section")
    }

    // MARK: - Ligne partagée

    @ViewBuilder
    private func ligne(_ note: MeetingNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timecode(note)
            corps(note)
            Spacer(minLength: 0)
            Pill("Partagé", ton: .oneOnOne)
                .help("Vous avez choisi de partager cette ligne : elle partira dans le récap")
        }
        .padding(.vertical, 2)
        .background(selection(note))
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture { designer(note) }
        .contextMenu { menu(note) }
    }

    // MARK: - Bloc privé

    /// Le bloc d'une ligne qui ne sortira pas : fond `bg/canvas`, barre gauche
    /// 2 px `accent/oneonone`, libellé en tête (spec §3.2).
    private func blocConfidentiel(_ note: MeetingNote) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(One2OneToken.oneOnOne)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    timecode(note)
                    Text(libelle(for: note.visibility))
                        .font(.plexMono(9.5, .semibold))
                        .tracking(9.5 * 0.07)
                        .foregroundStyle(One2OneToken.oneOnOneInk)
                    Spacer(minLength: 0)
                }
                corps(note)
                    .padding(.leading, TimecodeLabel.width + 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(One2OneToken.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                    style: .continuous))
        .overlay(selectionBorder(note))
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture { designer(note) }
        .contextMenu { menu(note) }
    }

    private func libelle(for visibility: Visibility) -> String {
        switch visibility {
        case .private:   return CollaboratorSessionModel.privateBlockLabel
        case .escalated: return "● ESCALADÉ — RH / N+1"
        case .shared:    return ""
        }
    }

    // MARK: - Désignation de la ligne courante

    /// Un clic désigne la ligne : c'est elle que la pilule `Partager la ligne`
    /// vise. Un second clic la désélectionne — partager par mégarde une ligne
    /// qu'on croyait désignée serait précisément l'accident que le critère
    /// n° 2 interdit.
    private func designer(_ note: MeetingNote) {
        let id = note.persistentModelID
        screen.oneOnOne.collabSelectedNoteID =
            screen.oneOnOne.collabSelectedNoteID == id ? nil : id
    }

    private func estDesignee(_ note: MeetingNote) -> Bool {
        screen.oneOnOne.collabSelectedNoteID == note.persistentModelID
    }

    @ViewBuilder
    private func selection(_ note: MeetingNote) -> some View {
        if estDesignee(note) {
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .fill(One2OneToken.oneOnOneBg)
        }
    }

    @ViewBuilder
    private func selectionBorder(_ note: MeetingNote) -> some View {
        if estDesignee(note) {
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(One2OneToken.oneOnOne, lineWidth: 1)
        }
    }

    // MARK: - Fragments

    private func timecode(_ note: MeetingNote) -> some View {
        Button {
            seek(to: note.t)
        } label: {
            Text(MeetingNoteStore.timecodeLabel(t: note.t, hasTimeline: hasTimeline))
                .font(.plexMono(10, .medium))
                .monospacedDigit()
                .foregroundStyle(One2OneToken.action)
                .frame(width: TimecodeLabel.width, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasTimeline)
        .help(hasTimeline
              ? "Replacer la lecture à \(MeetingPlayhead.mmss(note.t))"
              : "Aucun axe temps sur cette réunion")
    }

    @ViewBuilder
    private func corps(_ note: MeetingNote) -> some View {
        if editing == note.persistentModelID {
            HStack(spacing: 6) {
                OneOnOneInlineComposer(placeholder: "Texte de la note",
                                       text: $editingText) { commit(note) }
                Button("OK") { commit(note) }
                    .buttonStyle(.plain)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.actionInk)
            }
        } else {
            Text(texte(of: note))
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(count: 2) {
                    editingText = note.text
                    editing = note.persistentModelID
                }
        }
    }

    /// Le texte de la ligne. Une `promise`, une `request` ou une `proof` gardent
    /// leur préfixe : ce sont les trois natures du composeur de cet écran, et
    /// savoir qu'une ligne **est** une promesse change ce qu'on en fait.
    private func texte(of note: MeetingNote) -> String {
        switch note.kind {
        case .note, .feedback: return note.text
        default:               return "\(note.kind.label) — \(note.text)"
        }
    }

    // MARK: - Menu

    @ViewBuilder
    private func menu(_ note: MeetingNote) -> some View {
        Button("Modifier le texte") {
            editingText = note.text
            editing = note.persistentModelID
        }
        Button(note.visibility == .private ? "Partager cette ligne" : "Rendre privé") {
            // La bascule passe par le service du lot 10 : depuis `escalated`, on
            // redescend vers `private` et jamais vers `shared`.
            note.visibility = OneOnOneConfidentiality.toggledPrivacy(note.visibility,
                                                                      role: .collaborator)
            save(note)
        }
        Menu("Nature") {
            ForEach(MeetingNoteKind.allCases) { kind in
                Button(note.kind == kind ? "✓ \(kind.label)" : kind.label) {
                    note.kind = kind
                    save(note)
                }
            }
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            if screen.oneOnOne.collabSelectedNoteID == note.persistentModelID {
                screen.oneOnOne.collabSelectedNoteID = nil
            }
            context.delete(note)
            save(note)
        }
    }

    // MARK: - Actions

    private func seek(to t: Double) {
        let playhead = screen.playhead
        if playhead.duration <= 0 {
            playhead.duration = Double(meeting.durationSeconds)
        }
        if let url = meeting.wavFileURL, playhead.player.loadedURL != url {
            try? playhead.player.load(url: url)
            playhead.beginPlayback()
        }
        playhead.seek(to: t)
    }

    private func commit(_ note: MeetingNote) {
        guard editing == note.persistentModelID else { return }
        let propre = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Vider une ligne n'est pas une façon de la supprimer : le menu le
        // fait, et un texte vide laisserait une ligne muette dans la section.
        if !propre.isEmpty { note.text = propre }
        editing = nil
        editingText = ""
        save(note)
    }

    private func save(_ note: MeetingNote) {
        try? context.save()
        NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
    }
}
