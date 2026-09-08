import SwiftUI
import SwiftData

/// Les lignes de notes d'un entretien, **par section** (capture 2a, colonne
/// centrale).
///
/// Un fichier d'extension, et non une modification de `TimedNotesColumn` :
/// cette colonne-là appartient au lot 2, elle porte son propre filtre, son
/// composeur et son bandeau, et elle sert tous les autres types. Le 1:1 en
/// diffère sur trois points qui touchent chacun son corps :
/// - elle est **sectionnée** (`①②③`), avec un composeur unique en pied de
///   colonne et non un par section ;
/// - un bloc `private` est **isolé** visuellement (spec §3.2 : fond
///   `bg/canvas`, barre gauche 2 px `accent/oneonone`, libellé
///   `● NOTE PRIVÉE — VOUS SEUL`) ;
/// - la nature d'une ligne ne pose plus de barre rouge : en 1:1, c'est la
///   confidentialité qui se signale, pas la décision.
struct OneOnOneNotesSection: View {

    let meeting: Meeting
    let section: OneOnOneNoteSections.Section
    let screen: MeetingScreenModel
    /// Faux quand le libellé de section est déjà rendu par la vue qui
    /// enveloppe celle-ci.
    ///
    /// C'est le cas d'un seul appelant : `① COMMENT ÇA VA` titre l'échelle
    /// d'humeur **et** les notes de ce temps-là, sous un seul en-tête, comme le
    /// montre la capture 2a. `MoodScale` le rendait déjà, et cette vue le
    /// rendait une seconde fois : la recette finale a lu deux fois
    /// « ① COMMENT ÇA VA » dans la colonne centrale, l'un sous l'autre.
    var montreLeLibelle: Bool = true

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
            if montreLeLibelle { SectionLabel(section.label) }
            let notes = OneOnOneNoteSections.notes(meeting, in: section)
            if notes.isEmpty {
                Text(OneOnOneNoteSections.emptyInvite(for: section))
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

    // MARK: - Ligne ordinaire

    @ViewBuilder
    private func ligne(_ note: MeetingNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timecode(note)
            corps(note)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu { menu(note) }
    }

    /// Le bloc d'une ligne qui ne sortira pas : fond `bg/canvas`, barre gauche
    /// 2 px `accent/oneonone`, libellé en tête.
    ///
    /// Le libellé nomme l'audience réelle (`VOUS SEUL`, `RH / N+1`) plutôt
    /// qu'un niveau technique : c'est la seule information qui compte au moment
    /// où l'on écrit une ligne devant la personne concernée.
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
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu { menu(note) }
    }

    private func libelle(for visibility: Visibility) -> String {
        switch visibility {
        case .private:   return OneOnOneNoteSections.privateLabel
        case .escalated: return "● ESCALADÉ — RH / N+1"
        case .shared:    return ""
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

    /// Le texte de la ligne. Une nature autre que `note` ou `feedback` garde son
    /// préfixe (`Décision — …`) : elle est rare en 1:1, et la perdre rendrait
    /// la ligne incompréhensible dans `② SES SUJETS`.
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
        Button(note.visibility == .private ? "Rendre partagé" : "Rendre privé") {
            // La bascule passe par le service du lot 10 : depuis `escalated`,
            // on redescend vers `private` et jamais vers `shared`.
            note.visibility = OneOnOneConfidentiality.toggledPrivacy(note.visibility,
                                                                      role: .manager)
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
