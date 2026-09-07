import SwiftUI
import SwiftData

/// La colonne **MES NOTES** de la carte notes ↔ transcription (spec §2.4,
/// capture `1a-cockpit.png`).
///
/// « Lignes `timecode | texte`, timecode en `accent/action`, cliquable. Une
/// note `decision` porte une barre gauche 2 px `accent/report` ; `risk` en
/// `accent/warn`. Composeur en bas avec les commandes `/` visibles en
/// permanence. »
///
/// Les lignes sont des `MeetingNote` (D1) : cette colonne ne passe **pas** par
/// `Meeting.liveNotes` ni par les chemins `adoptPendingLiveNotes()` /
/// `discardEmptyNoteIfNeeded()` de `MeetingView`, qui dépendent de l'ordre de
/// démontage SwiftUI (programme §2.4 point 2).
struct TimedNotesColumn: View {

    let meeting: Meeting
    let screen: MeetingScreenModel

    /// Thème de l'écran hôte. La colonne est identique en clair (espace
    /// Réunion, capture 1a) et en sombre (mode séance plein écran, capture
    /// 1b) : seules ses couleurs changent, et elle ne les choisit pas.
    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }

    @Environment(\.modelContext) private var context
    /// Les collaborateurs mentionnables : même prédicat que l'éditeur markdown
    /// (`EditableTextField.mentionableCollaborators`), pour qu'un `@Prénom`
    /// reconnu dans une note le soit aussi dans un document.
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived })
    private var mentionnables: [Collaborator]
    /// Ligne en cours d'édition inline. Une seule à la fois : deux champs
    /// ouverts en même temps sur la même colonne, c'est une saisie perdue.
    @State private var editing: PersistentIdentifier?
    @State private var editingText = ""
    @State private var hovered: PersistentIdentifier?

    /// Vrai quand la réunion a un axe temps : un enregistrement en cours, une
    /// durée connue ou un fichier audio. Décide de `--:--`.
    private var hasTimeline: Bool {
        meeting.durationSeconds > 0
            || meeting.recordingStartedAt != nil
            || meeting.wavFileURL != nil
    }

    private var notes: [MeetingNote] {
        MeetingNoteStore.filtered(MeetingNoteStore.sorted(meeting.timedNotes),
                                  kind: screen.noteFilter)
            // Une ligne vide est un **marqueur** posé par `⌘M` en mode séance
            // (lot 4, décision D4.1) : elle porte un repère sur l'axe temps,
            // pas une phrase. L'afficher produirait une ligne muette dont
            // seul le timecode se lit, et qu'on ne saurait pas supprimer.
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let filtre = screen.noteFilter {
                bandeauDeFiltre(filtre)
            }
            if theme == .session {
                // Capture 1b : le composeur suit la dernière note **dans le
                // flot**, la ligne en cours de saisie prolongeant la colonne.
                // En 1a il est ancré en pied d'une colonne courte ; ici la
                // colonne occupe toute la hauteur de l'écran et un composeur
                // collé en bas serait à trente centimètres du regard.
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(notes, id: \.persistentModelID) { ligne(for: $0) }
                        NoteComposer(meeting: meeting, screen: screen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else if notes.isEmpty {
                MeetingEmptyInvite(space: .meeting, mode: .live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                NoteComposer(meeting: meeting, screen: screen)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(notes, id: \.persistentModelID) { ligne(for: $0) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                NoteComposer(meeting: meeting, screen: screen)
            }
        }
    }

    // MARK: - Filtre

    /// Le filtre posé par la carte Décisions du bandeau (spec §2.3). Sans ce
    /// bandeau, une colonne filtrée se lirait comme une colonne vide.
    private func bandeauDeFiltre(_ kind: MeetingNoteKind) -> some View {
        HStack(spacing: 6) {
            Chip("kind:\(kind.label.lowercased())", ton: kind == .decision ? .report : .warn)
            Button("tout afficher") { screen.noteFilter = nil }
                .buttonStyle(.plain)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(c.actionInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Ligne

    @ViewBuilder
    private func ligne(for note: MeetingNote) -> some View {
        let id = note.persistentModelID
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let teinte = barre(for: note.kind) {
                Rectangle()
                    .fill(teinte)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            Button {
                seek(to: note.t)
            } label: {
                Text(MeetingNoteStore.timecodeLabel(t: note.t, hasTimeline: hasTimeline))
                    .font(.plexMono(10, .medium))
                    .monospacedDigit()
                    .foregroundStyle(note.kind == .decision
                                     ? c.report
                                     : c.action)
                    .frame(width: TimecodeLabel.width, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasTimeline)
            .help(hasTimeline
                  ? "Replacer la lecture à \(MeetingPlayhead.mmss(note.t))"
                  : "Aucun axe temps sur cette réunion")

            if editing == id {
                EditableTextField(placeholder: "Texte de la note",
                                  text: Binding(get: { editingText },
                                                set: { editingText = $0 }))
                    .frame(height: 22)
                    .onDisappear { commitEdition(note) }
                Button("OK") { commitEdition(note) }
                    .buttonStyle(.plain)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(c.actionInk)
            } else {
                texte(for: note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) {
                        editingText = note.text
                        editing = id
                    }
                if hovered == id { menuDeLigne(note) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onHover { survole in
            if survole { hovered = id } else if hovered == id { hovered = nil }
        }
        .contextMenu { itemsDeMenu(note) }
    }

    /// Le texte de la ligne. Une décision porte son préfixe en gras, comme la
    /// capture (`11:03 | **Décision** — le partenaire finalise…`) ; en mode
    /// séance, le libellé passe **au-dessus** en mono, comme la capture 1b.
    @ViewBuilder
    private func texte(for note: MeetingNote) -> some View {
        if note.kind == .note {
            corps(of: note)
        } else if theme == .session {
            // Capture 1b : `DÉCISION` sur sa propre ligne, en libellé mono
            // `accent/report`, puis le texte en dessous. La colonne y est plus
            // large qu'en 1a et la ligne respire ; le préfixe inline y
            // écraserait le texte contre la barre rouge.
            VStack(alignment: .leading, spacing: 3) {
                Text(note.kind.label)
                    .sectionLabel()
                    .foregroundStyle(note.kind == .decision ? c.reportInk : c.warnInk)
                corps(of: note)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(note.kind.label) ").font(.plexSans(12, .semibold))
                    .foregroundStyle(note.kind == .decision ? c.reportInk : c.warnInk)
                Text("— ").font(.plexSans(12)).foregroundStyle(c.ink4)
                corps(of: note)
            }
        }
    }

    /// Le corps de la ligne, mentions `@Prénom` rendues en pilule (capture 1b :
    /// « Qui donne le feu vert ? `@Yann` »).
    ///
    /// Les pilules ne sont posées qu'en mode séance : le rendu clair du lot 2
    /// ne change pas, et une pilule dans une colonne de 1a n'a pas été
    /// dessinée. Le découpage est `SessionMentionRuns`, testé à part — c'est
    /// « ce qui est une mention » qui est difficile, pas la pilule.
    @ViewBuilder
    private func corps(of note: MeetingNote) -> some View {
        if theme == .session {
            let fragments = SessionMentionRuns.runs(in: note.text) {
                SessionMentionRuns.estConnu($0, parmi: mentionnables)
            }
            if fragments.contains(where: { if case .mention = $0 { return true } else { return false } }) {
                MentionFlow(fragments: fragments, couleurs: c)
            } else {
                Text(note.text)
                    .font(.plexSans(12))
                    .foregroundStyle(c.ink2)
                    .textSelection(.enabled)
            }
        } else {
            Text(note.text)
                .font(.plexSans(12))
                .foregroundStyle(c.ink2)
                .textSelection(.enabled)
        }
    }

    /// Barre gauche de 2 px : `accent/report` pour une décision, `accent/warn`
    /// pour un risque, rien pour le reste (spec §2.4).
    private func barre(for kind: MeetingNoteKind) -> Color? {
        switch kind {
        case .decision: return c.report
        case .risk:     return c.warn
        case .note, .feedback, .promise, .request, .proof: return nil
        }
    }

    private func menuDeLigne(_ note: MeetingNote) -> some View {
        Menu {
            itemsDeMenu(note)
        } label: {
            Text("⋯")
                .font(.plexSans(12, .medium))
                .foregroundStyle(c.ink4)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func itemsDeMenu(_ note: MeetingNote) -> some View {
        Button("Modifier le texte") {
            editingText = note.text
            editing = note.persistentModelID
        }
        Menu("Nature") {
            ForEach(MeetingNoteKind.allCases) { kind in
                Button {
                    note.kind = kind
                    save()
                } label: {
                    Text(note.kind == kind ? "✓ \(kind.label)" : kind.label)
                }
            }
        }
        Menu("Visibilité") {
            ForEach(Visibility.allCases, id: \.rawValue) { niveau in
                Button {
                    note.visibility = niveau
                    save()
                } label: {
                    Text(note.visibility == niveau ? "✓ \(niveau.label)" : niveau.label)
                }
            }
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            context.delete(note)
            save()
        }
    }

    // MARK: - Actions

    /// Le timecode replace la lecture (spec §2.4 : « timecode en
    /// `accent/action`, cliquable »). En relecture, le lecteur suit ; en
    /// séance, seul le curseur bouge — c'est `MeetingPlayhead.seek` qui tient
    /// cette règle.
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

    private func commitEdition(_ note: MeetingNote) {
        guard editing == note.persistentModelID else { return }
        let texte = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Vider une ligne n'est pas une façon de la supprimer : le menu le
        // fait, et un texte vide laisserait une ligne muette dans la colonne.
        if !texte.isEmpty { note.text = texte }
        editing = nil
        editingText = ""
        save()
    }

    private func save() {
        try? context.save()
        NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
    }
}
