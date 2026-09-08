import SwiftUI
import SwiftData

/// Le moteur de transcription, tel que la colonne l'annonce (capture
/// `1a-cockpit.png` : `TRANSCRIPTION  Cohere MLX`).
extension STTEngineKind {
    var refonteLabel: String {
        switch self {
        case .cohere:  return "Cohere MLX"
        case .voxtral: return "Voxtral"
        case .qwen3:   return "Qwen3-ASR"
        }
    }
}

/// La colonne **TRANSCRIPTION** de la carte notes ↔ transcription (spec §2.4,
/// capture `1a-cockpit.png`).
///
/// « Fond `surface/alt`, segments `timecode | Locuteur — texte`. Au survol, le
/// segment prend le fond `accent/action bg` et révèle une rangée d'actions :
/// `＋ Action` (plein), `Décision`, `Citer dans la note`. `⌘⇧A` agit sur le
/// segment survolé ou la sélection de texte. »
///
/// Remplace `MeetingView.transcriptView` : la transcription live, les segments,
/// les locuteurs et la suppression de passage vivent ici ; `MeetingView` ne
/// garde que la diarisation et la ré-identification, reçues en closures.
struct TranscriptColumn: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    let onDiarize: () -> Void
    let onReidentify: () -> Void
    /// Ajout d'un extrait au CR manager (`MeetingView.startManagerReportFlow`).
    /// Conservé tel quel : c'est le seul chemin qui alimente le rapport 1:1
    /// manager depuis la transcription.
    let onAddToManagerReport: (NSRange, String, String) -> Void

    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived })
    private var allCollaborators: [Collaborator]
    @ObservedObject private var live = LiveTranscriptionService.shared

    @State private var hovered: PersistentIdentifier?
    @State private var lastHovered: TranscriptSegment?
    @State private var segmentToDelete: TranscriptSegment?
    @State private var erreur: String?

    /// Vrai tant qu'une session live tourne ou qu'un texte live existe (avant
    /// que le transcript final ne soit produit au `stop()`).
    private var isLiveActive: Bool {
        live.isLive || !live.liveTranscript.isEmpty
    }

    private var segments: [TranscriptSegment] {
        meeting.transcriptSegments.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var showsSpeakers: Bool {
        settings.transcriptionMode == .diarizeFirst && screen.showSpeakers
    }

    /// La réunion a un audio à lire — testé sur le **chemin**, pas sur l'URL.
    ///
    /// `Meeting.wavFileURL` construit un `URL(fileURLWithPath:)`, ce qui coûte
    /// un `lstat`. La rangée l'interrogeait trois fois (teinte, `disabled`,
    /// infobulle) : sur une transcription de cent segments, trois cents appels
    /// système à chaque rendu de la colonne — et la colonne se réévalue à chaque
    /// avancée de la tête de lecture, un appel du `sample` du gel du 2026-09-08
    /// sur deux passait là.
    private var aUnAudio: Bool {
        !(meeting.wavFilePath ?? "").isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            barreDOutils
            contenu
        }
        .overlay { raccourciAction }
        .alert("Supprimer ce passage ?",
               isPresented: Binding(get: { segmentToDelete != nil },
                                    set: { if !$0 { segmentToDelete = nil } }),
               presenting: segmentToDelete) { segment in
            Button("Annuler", role: .cancel) { segmentToDelete = nil }
            Button("Supprimer", role: .destructive) {
                let cible = segment
                segmentToDelete = nil
                Task { await supprimer(cible) }
            }
        } message: { _ in
            Text("Le texte et la portion audio correspondante seront supprimés définitivement.")
        }
    }

    // MARK: - En-tête de colonne

    /// Le moteur, l'état du suivi et les deux commandes de locuteurs. La
    /// bascule `Speakers` et le bouton `Résumer` sont dans l'en-tête de la
    /// carte (`MeetingLiveSpace`), comme sur la capture.
    private var barreDOutils: some View {
        HStack(spacing: 8) {
            MonoMeta(settings.transcriptionEngine.refonteLabel)
            if !segments.isEmpty {
                MonoMeta("\(segments.count) segments")
            }
            Spacer(minLength: 4)
            if !segments.isEmpty {
                Button {
                    screen.follow = TranscriptFollow.next(
                        following: screen.follow,
                        on: screen.follow ? .manualScroll : .resumeRequested)
                } label: {
                    Text(TranscriptFollow.label(following: screen.follow))
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(screen.follow
                                         ? c.actionInk
                                         : c.ink3)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(screen.follow
                                           ? c.actionBg
                                           : c.card)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(screen.follow
                      ? "La transcription suit la tête de lecture"
                      : "Reprendre le défilement lié à la tête de lecture")
            }
            if settings.transcriptionMode == .diarizeFirst {
                Button(action: onDiarize) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 10))
                        .foregroundStyle(c.ink3)
                }
                .buttonStyle(.plain)
                .disabled(segments.isEmpty || !aUnAudio)
                .help("Détecter les locuteurs (VAD) puis réattribuer les tours de parole")

                Button(action: onReidentify) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 10))
                        .foregroundStyle(c.ink3)
                }
                .buttonStyle(.plain)
                .disabled(!aUnAudio)
                .help("Ré-identifier les locuteurs depuis les empreintes vocales")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Contenu

    @ViewBuilder
    private var contenu: some View {
        if let erreur {
            Text(erreur)
                .font(.plexSans(11))
                .foregroundStyle(c.reportInk)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        if segments.isEmpty && !isLiveActive && meeting.rawTranscript.isEmpty {
            MeetingEmptyInvite(
                titre: "Aucune transcription",
                invite: "Démarre un enregistrement : la transcription s'écrit ici, segment par segment, et chaque phrase devient une action en un clic."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if isLiveActive { sectionLive }
                        if !segments.isEmpty {
                            ForEach(segments, id: \.persistentModelID) { rangee(for: $0) }
                        } else if !meeting.rawTranscript.isEmpty {
                            transcriptionAPlat
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: screen.playhead.t) { _, t in
                    guard screen.follow, !segments.isEmpty else { return }
                    guard let index = TranscriptFollow.target(
                        startTimes: segments.map(\.startSeconds), t: t) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(segments[index].persistentModelID, anchor: .center)
                    }
                }
            }
        }
    }

    /// Aperçu de la transcription en direct, dans la **même** colonne que les
    /// segments (spec §2.4, lot 2 périmètre n° 6).
    private var sectionLive: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(live.isLive ? c.report : c.ink4)
                    .frame(width: 6, height: 6)
                Text("En direct")
                    .font(.plexSans(11, .semibold))
                    .foregroundStyle(c.ink2)
                if let statut = live.statusMessage {
                    MonoMeta(statut)
                }
            }
            Text(live.liveTranscript.isEmpty ? "En écoute…" : live.liveTranscript)
                .font(.plexSans(12.5))
                .foregroundStyle(live.liveTranscript.isEmpty
                                 ? c.inkMuted
                                 : c.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.bottom, 2)
    }

    /// Transcription sans segments : le texte à plat, avec le surlignage du CR
    /// manager conservé (c'est le seul endroit qui l'offre sur la
    /// transcription).
    private var transcriptionAPlat: some View {
        let champ = meeting.mergedTranscript.isEmpty ? "transcript" : "mergedTranscript"
        let texte = meeting.mergedTranscript.isEmpty
            ? meeting.rawTranscript
            : meeting.mergedTranscript
        return MeetingHighlightableTextView(
            text: .constant(texte),
            isEditable: false,
            highlightedRanges: ManagerReportService.highlightedRanges(
                meeting: meeting, field: champ, in: context),
            onAddToManagerReport: { range, extrait in
                onAddToManagerReport(range, extrait, champ)
            }
        )
        .frame(minHeight: 240)
    }

    // MARK: - Rangée de segment

    @ViewBuilder
    private func rangee(for segment: TranscriptSegment) -> some View {
        let id = segment.persistentModelID
        let survole = hovered == id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    lire(segment)
                } label: {
                    Text(TimecodeLabel.format(segment.startSeconds))
                        .font(.plexMono(10, .medium))
                        .monospacedDigit()
                        .foregroundStyle(aUnAudio ? c.action : c.ink4)
                        .frame(width: TimecodeLabel.width, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!aUnAudio)
                .help(aUnAudio
                      ? "Lire à partir de \(TimecodeLabel.format(segment.startSeconds))"
                      : "Aucun audio attaché à la réunion")

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if showsSpeakers {
                            TranscriptSpeakerBadge(
                                segment: segment,
                                meeting: meeting,
                                screen: screen,
                                settings: settings,
                                allCollaborators: allCollaborators,
                                segmentMenu: { AnyView(menuDeSegment(segment)) }
                            )
                            Text("—")
                                .font(.plexSans(12))
                                .foregroundStyle(c.ink4)
                        }
                        if segment.isHighlighted {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8.5))
                                .foregroundStyle(c.warn)
                        }
                        Text(segment.text)
                            .font(.plexSans(12.5))
                            .foregroundStyle(c.ink2)
                            .lineSpacing(TimedNotesColumn.interligne)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if survole { rangeeDActions(segment) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id(id)
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .fill(survole ? c.actionBg : Color.clear)
        )
        .contextMenu { menuDeSegment(segment) }
        .onHover { entre in
            if entre {
                hovered = id
                lastHovered = segment
            } else if hovered == id {
                hovered = nil
            }
        }
    }

    /// `＋ Action` (plein) · `Décision` · `Citer dans la note` — la rangée
    /// révélée au survol (spec §2.4).
    private func rangeeDActions(_ segment: TranscriptSegment) -> some View {
        HStack(spacing: 6) {
            Button { creerAction(from: segment) } label: {
                Text("＋ Action")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                         style: .continuous)
                            .fill(c.action)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Créer une action depuis cette phrase (⌘⇧A)")

            boutonSecondaire("Décision") { creerDecision(from: segment) }
                .help("Noter une décision au timecode de cette phrase")
            boutonSecondaire("Citer dans la note") { citer(segment) }
                .help("Insérer la citation dans le composeur de notes")
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    private func boutonSecondaire(_ titre: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(c.ink2)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                     style: .continuous)
                        .fill(c.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                     style: .continuous)
                        .strokeBorder(c.strongBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menuDeSegment(_ segment: TranscriptSegment) -> some View {
        Button {
            creerAction(from: segment)
        } label: {
            Label("Créer une action depuis cette phrase", systemImage: "plus.circle")
        }
        Button {
            creerDecision(from: segment)
        } label: {
            Label("Noter une décision", systemImage: "checkmark.seal")
        }
        Button {
            citer(segment)
        } label: {
            Label("Citer dans la note", systemImage: "text.quote")
        }
        Divider()
        Button {
            segment.isHighlighted.toggle()
            try? context.save()
        } label: {
            Label(segment.isHighlighted ? "Retirer l'importance" : "Marquer comme important",
                  systemImage: segment.isHighlighted ? "star.slash" : "star.fill")
        }
        Divider()
        Button(role: .destructive) {
            segmentToDelete = segment
        } label: {
            Label("Supprimer ce passage", systemImage: "trash")
        }
    }

    /// `⌘⇧A` (spec §1.4) : agit sur le segment survolé, à défaut sur le dernier
    /// survolé. Le raccourci vit dans la colonne qui le rend possible plutôt
    /// que dans un item de menu — `MeetingView` n'a pas à porter une closure
    /// de plus (programme §2.4 point 1).
    private var raccourciAction: some View {
        Button("") {
            guard let cible = segments.first(where: { $0.persistentModelID == hovered })
                ?? lastHovered else { return }
            creerAction(from: cible)
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Gestes

    /// `＋ Action` sur une phrase : **pose l'intention**, elle ne crée rien.
    ///
    /// Le composeur du rail la reçoit préremplie — titre nettoyé, locuteur
    /// suggéré, source du segment — et `⌘⏎` crée l'action en tête de son
    /// groupe (spec §2.4 : « ouvre le composeur d'action prérempli »). Créer
    /// ici **et** laisser le composeur créer donnerait deux actions pour un
    /// clic.
    private func creerAction(from segment: TranscriptSegment) {
        screen.requestAction(from: ActionFromPhrase.draft(from: segment))
    }

    private func creerDecision(from segment: TranscriptSegment) {
        ActionFromPhrase.createDecision(from: segment, in: meeting, context: context)
        NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
    }

    /// `Citer dans la note` : le composeur reçoit `« texte » — Locuteur, mm:ss`
    /// et le clavier, plutôt que d'écrire la note d'office — la citation est
    /// presque toujours commentée.
    private func citer(_ segment: TranscriptSegment) {
        screen.pendingNoteText = ActionFromPhrase.quotation(
            phrase: segment.text,
            speakerName: segment.speaker?.name,
            t: segment.startSeconds
        )
        screen.focusNoteComposer()
    }

    /// Charge le WAV si besoin, place la tête de lecture sur le début du
    /// segment, joue. Reprend `MeetingView.playSegmentAudio` : la pause avant
    /// le saut est nécessaire, sinon `AVAudioPlayer` continue parfois depuis
    /// l'ancienne position avant de prendre le `seek` en compte.
    private func lire(_ segment: TranscriptSegment) {
        guard let url = meeting.wavFileURL else { return }
        let playhead = screen.playhead
        do {
            if playhead.player.loadedURL != url { try playhead.player.load(url: url) }
        } catch {
            erreur = "Lecture impossible : \(error.localizedDescription)"
            return
        }
        if playhead.player.isPlaying { playhead.player.pause() }
        playhead.beginPlayback()
        playhead.seek(to: segment.startSeconds)
        playhead.player.play()
        // Cliquer un segment est une interaction manuelle : le défilement lié
        // ne doit pas reprendre la main juste après.
        screen.follow = TranscriptFollow.next(following: screen.follow, on: .manualScroll)
    }

    private func supprimer(_ segment: TranscriptSegment) async {
        do {
            try await TranscriptEditService.deleteSegment(segment, in: meeting, context: context)
        } catch {
            erreur = error.localizedDescription
        }
    }
}
