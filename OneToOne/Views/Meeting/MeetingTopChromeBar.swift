import SwiftUI
import SwiftData

/// Barre supérieure (« chrome ») de l'écran réunion : fil d'Ariane, pill
/// d'enregistrement/lecture, capture, sélecteur de template, génération de
/// rapport et menu « … ». Vue purement présentationnelle : toute la logique
/// métier est déléguée au parent via les callbacks `on…`.
struct MeetingTopChromeBar: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @Query private var allTemplates: [ReportTemplate]
    @ObservedObject var recorder: AudioRecorderService
    @ObservedObject var stt: TranscriptionService
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var captureService: ScreenCaptureService
    /// Vrai si l'enregistrement en cours appartient à la réunion affichée.
    /// ⚠️ Pour l'affichage (pastille rouge, chrono), ne pas utiliser
    /// `recorder.isRecording` : le service est un singleton et la pastille
    /// apparaîtrait dans toutes les fenêtres réunion ouvertes.
    let isRecordingThisMeeting: Bool
    let isGeneratingReport: Bool
    let reportProgressChars: Int
    let reportElapsedSeconds: Int
    let reportStatus: String
    let reportWaitWarning: String?
    let capturedSlidesCount: Int

    /// Source d'actions partagée avec les menus natifs (cf. MeetingMenuActions).
    let actions: MeetingMenuActions

    // Closures propres à la barre (absentes des menus natifs) :
    /// Bascule lecture/pause de l'audio enregistré.
    let onTogglePlay: () -> Void
    /// Ouvre la configuration de la source de capture d'écran.
    let onShowCaptureSetup: () -> Void
    /// Ouvre la galerie des slides capturées.
    let onShowSlides: () -> Void

    /// Retour vers l'écran d'où l'on vient, quand la réunion a été **poussée**
    /// dans une pile (depuis la fiche d'un collaborateur). `nil` quand elle est
    /// ouverte seule : il n'y a alors rien derrière, et un chevron mentirait.
    var onBack: (() -> Void)?

    /// Thèmes proposés par l'IA, en attente d'acceptation (éphémères).
    @Binding var suggestedTagNames: [String]
    /// Une suggestion de thèmes est en cours.
    let isSuggestingTags: Bool
    /// Relance manuellement la suggestion de thèmes.
    let onRequestTagSuggestions: () -> Void

    /// Affiche le popover de choix du type de rapport avant génération.
    @State private var showReportTypePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                breadcrumb
                Spacer()
                // Une note n'a ni audio, ni transcription, ni rapport : ses
                // onglets Transcription et Rapport sont masqués par
                // `MeetingView.visibleSections(for:)`. Laisser ces contrôles
                // produirait un enregistrement et un rapport invisibles et
                // ingérables. Même règle côté actions partagées, par deux
                // mécanismes distincts et **visiblement différents** : le menu
                // natif « Réunion » garde ses huit items d'enregistrement et
                // de rapport, seulement grisés
                // (`MeetingMenuActions.disabledForNote`) ; `moreMenu`, lui,
                // retire entièrement ses deux entrées Audio et Import WAV sur
                // `actions.isNote` — les six autres, il ne les a jamais
                // portées. Sur une note, l'un montre huit lignes estompées et
                // l'autre aucune. Seule la règle est commune : rien de ce qui
                // touche à l'audio ou au rapport n'est actionnable.
                if meeting.kind != .note {
                    recorderPill
                    captureButton
                    templatePickerButton
                    reportButton
                }
                moreMenu
            }
            // Rangée des thèmes, sous le fil d'Ariane : elle a besoin de toute
            // la largeur pour passer à la ligne (FlowLayout).
            MeetingTagEditor(
                meeting: meeting,
                suggestions: $suggestedTagNames,
                isSuggesting: isSuggestingTags,
                onRequestSuggestions: onRequestTagSuggestions
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MeetingTheme.canvasCream)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MeetingTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            if let onBack {
                // Le retour vit dans le fil d'Ariane : c'est le seul endroit
                // de l'écran qui dit déjà « où je suis ». `⌘[` fait la même
                // chose, comme partout sur macOS.
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                .help("Retour (⌘[)")
            }
            Text("One2One").font(.caption).foregroundColor(.secondary)
            chevron
            if let project = meeting.project {
                Text(project.name).font(.caption).foregroundColor(.secondary)
                chevron
            }
            // Titre de la réunion, éditable en ligne (déplacé ici depuis l'en-tête éditorial).
            EditableTextField(placeholder: "Titre de la réunion…", text: $meeting.title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            // Badge de type de réunion — éditable (source unique du type, remplace le
            // picker du bloc Détails).
            Menu {
                Picker("Type de réunion", selection: Binding(
                    get: { meeting.kind },
                    set: { meeting.kind = $0; try? modelContext.save() }
                )) {
                    ForEach(MeetingKind.allCases) { k in
                        Label(k.label, systemImage: k.sfSymbol).tag(k)
                    }
                }
            } label: {
                Label(meeting.kind.label, systemImage: meeting.kind.sfSymbol)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            audioStatusBadge
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// Badge d'état de disponibilité de l'audio dans le fil d'Ariane.
    /// - `.original` : audio intact → aucun badge affiché.
    /// - `.compressed` : audio recompressé (AAC) → badge informatif (qualité STT dégradée).
    /// - `.deleted` : audio purgé par la politique de rétention → badge « archivé ».
    @ViewBuilder
    private var audioStatusBadge: some View {
        switch meeting.audioAvailability {
        case .original:
            EmptyView()
        case .compressed:
            Label("Audio compressé", systemImage: "archivebox")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .help("Audio compressé (AAC 32 kbps mono) — qualité STT dégradée si re-transcription")
        case .deleted:
            Label("Audio archivé", systemImage: "trash")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .help("Audio supprimé après 30 jours (politique de rétention). Rapport et transcription conservés.")
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
    }

    // MARK: - Recorder pill

    @ViewBuilder
    private var recorderPill: some View {
        if isRecordingThisMeeting {
            recordingPill
        } else if actions.hasWav {
            playbackPill
        } else {
            idlePill
        }
    }

    private var idlePill: some View {
        // `recorder.isRecording` (global) ici et non `isRecordingThisMeeting` :
        // une autre réunion enregistre déjà, le service ne peut pas en démarrer
        // un second — le bouton est grisé plutôt qu'échouer au clic.
        let otherMeetingIsRecording = recorder.isRecording && !isRecordingThisMeeting
        return Button(action: actions.startRecording) {
            Label("Enregistrer", systemImage: "record.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.red))
        }
        .buttonStyle(.plain)
        .disabled(stt.isTranscribing || isGeneratingReport || otherMeetingIsRecording)
        .opacity(otherMeetingIsRecording ? 0.4 : 1.0)
        .help(otherMeetingIsRecording
              ? "Un enregistrement est déjà en cours pour une autre réunion"
              : "Démarrer l'enregistrement")
    }

    private var recordingPill: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(formatDuration(recorder.elapsedSeconds))
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
            Button(action: actions.togglePause) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            Button(action: actions.stopRecording) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(MeetingTheme.badgeBlack))
    }

    private var playbackPill: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlay) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .disabled(!meeting.hasPlayableAudio)
            .opacity(meeting.hasPlayableAudio ? 1.0 : 0.4)
            .help(meeting.hasPlayableAudio ? "Lecture" : "Audio supprimé après politique de rétention")
            Text("\(formatDuration(player.currentTime)) / \(formatDuration(max(player.duration, TimeInterval(meeting.durationSeconds))))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
            Button(action: actions.appendRecording) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Reprendre l'enregistrement (concaténation)")
            .disabled(stt.isTranscribing || isGeneratingReport)
            Button(action: actions.retranscribe) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .disabled(stt.isTranscribing)
            // Bouton visible pour éditer l'audio (couper début/fin, diviser).
            // Restauré ici : l'action était enfouie dans ⋯ → Audio et introuvable.
            Button(action: actions.editAudio) {
                Image(systemName: "scissors")
                    .foregroundColor(.white).font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Éditer l'audio — couper le début/la fin ou diviser")
            .disabled(!meeting.hasPlayableAudio || stt.isTranscribing || isGeneratingReport)
            .opacity(meeting.hasPlayableAudio ? 1.0 : 0.4)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(MeetingTheme.badgeBlack))
    }

    // MARK: - Capture button

    @ViewBuilder
    private var captureButton: some View {
        if captureService.hasOpenSession {
            HStack(spacing: 4) {
                Button(action: onShowSlides) {
                    HStack(spacing: 4) {
                        Circle().fill(captureStatusColor).frame(width: 6, height: 6)
                        Text(captureStatusText)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(captureStatusColor.opacity(0.15)))
                    .foregroundColor(captureStatusColor)
                }
                .buttonStyle(.plain)
                .help(captureStatusHelp)

                Menu {
                    Button { onShowCaptureSetup() } label: {
                        Label("Configurer…", systemImage: "rectangle.dashed.badge.record")
                    }
                    if captureService.isCapturing {
                        Button { captureService.stop() } label: {
                            Label("Arrêter la capture", systemImage: "stop.circle")
                        }
                    } else {
                        Button { captureService.resume() } label: {
                            Label("Reprendre la capture", systemImage: "play.circle")
                        }
                        Button(role: .destructive) { Task { await captureService.finish() } } label: {
                            Label("Terminer le lot", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(captureStatusColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Options de capture")
            }
        } else if capturedSlidesCount > 0 {
            Button(action: onShowSlides) {
                Label("Capture", systemImage: "camera.viewfinder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .overlay(alignment: .topTrailing) {
                Text("\(capturedSlidesCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 4, y: -4)
            }
        } else {
            Button(action: onShowCaptureSetup) {
                Label("Capture", systemImage: "camera.viewfinder").font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Bleu en cours, orange en pause, gris arrêtée : l'état réel, pas déduit.
    private var captureStatusColor: Color {
        switch captureService.state {
        case .running: return .blue
        case .paused: return .orange
        case .stopped, .idle: return .gray
        }
    }

    private var captureStatusText: String {
        let count = captureService.capturedSlidesCount
        switch captureService.state {
        case .running: return "\(count) slides"
        case .paused: return "En pause · \(count)"
        case .stopped: return "Arrêtée · \(count)"
        case .idle: return ""
        }
    }

    private var captureStatusHelp: String {
        if case .paused(let reason) = captureService.state { return reason }
        return "Voir les slides capturées"
    }

    // MARK: - Report button

    @ViewBuilder
    private var reportButton: some View {
        // Le rapport a besoin d'une transcription OU d'un audio à transcrire.
        // Sans transcript mais avec audio, le clic enchaîne transcription + rapport.
        let needsTranscription = meeting.rawTranscript.isEmpty
        let hasSource = !needsTranscription || meeting.hasPlayableAudio
        let disabled = !hasSource || recorder.isRecording || stt.isTranscribing || isGeneratingReport
        Button(action: { showReportTypePicker = true }) {
            HStack(spacing: 6) {
                if isGeneratingReport {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("\(reportStatus) · \(formatElapsed(reportElapsedSeconds))")
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                    if reportWaitWarning != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                } else if stt.isTranscribing {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Transcription…").font(.caption)
                } else {
                    Image(systemName: "wand.and.stars")
                    if needsTranscription {
                        Text("Transcrire + Rapport")
                    } else if meeting.summary.isEmpty {
                        Text("Rapport")
                    } else if meeting.reportGenerationDurationSeconds > 0 {
                        Text("Rapport ✓ (\(formatElapsed(Int(meeting.reportGenerationDurationSeconds.rounded()))))")
                    } else {
                        Text("Rapport ✓")
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(disabled ? Color.secondary.opacity(0.4) : MeetingTheme.accentOrange)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(reportWaitWarning ?? reportStatus)
        .popover(isPresented: $showReportTypePicker, arrowEdge: .bottom) {
            reportTypePicker
        }
    }

    /// Popover de choix du type de rapport, affiché au clic sur « Rapport ».
    /// Propose « Auto » puis les templates compatibles ; la sélection fixe
    /// `meeting.reportTemplate` puis lance la génération.
    private var reportTypePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Type de rapport")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10).padding(.bottom, 6)
            reportTypeRow(name: "Auto (selon type)", template: nil)
            if !compatibleTemplates.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(compatibleTemplates) { t in
                    reportTypeRow(name: t.name, template: t)
                }
            }
        }
        .frame(minWidth: 240)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func reportTypeRow(name: String, template: ReportTemplate?) -> some View {
        let isSelected = meeting.reportTemplate?.persistentModelID == template?.persistentModelID
        Button {
            meeting.reportTemplate = template
            try? modelContext.save()
            showReportTypePicker = false
            actions.generateReport()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: template == nil ? "wand.and.stars" : "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name).lineLimit(1)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark").font(.caption2).foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Template picker

    private var templatePickerButton: some View {
        Menu {
            Button("Auto (selon type)") {
                meeting.reportTemplate = nil
                try? modelContext.save()
            }
            Divider()
            ForEach(compatibleTemplates) { t in
                Button(t.name) {
                    meeting.reportTemplate = t
                    try? modelContext.save()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                Text(meeting.reportTemplate?.name ?? "Auto")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Template de rapport — modifie la structure du compte-rendu généré")
    }

    /// Templates non archivés proposés dans le sélecteur, triés par priorité :
    /// d'abord le `ReportTemplateKind` correspondant au type de la réunion,
    /// puis par ordre alphabétique (insensible à la casse).
    private var compatibleTemplates: [ReportTemplate] {
        let mapping: [MeetingKind: ReportTemplateKind] = [
            .global: .general,
            .oneToOne: .oneToOne,
            .manager: .manager,
            .project: .copil,
            .work: .general
        ]
        let preferred = mapping[meeting.kind] ?? .general
        return allTemplates
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let li = lhs.kind == preferred ? 0 : 1
                let ri = rhs.kind == preferred ? 0 : 1
                if li != ri { return li < ri }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - More menu

    private var moreMenu: some View {
        Menu {
            Menu {
                Button(action: actions.exportMarkdown) { Label("Copier Markdown", systemImage: "doc.text") }
                Button(action: actions.exportPDF) { Label("Exporter PDF", systemImage: "doc.richtext") }
                Menu {
                    Button { actions.exportMail([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportMail(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportMail([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportMail([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Apple Mail", systemImage: "envelope") }
                Menu {
                    Button { actions.exportOutlook([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportOutlook(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportOutlook([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportOutlook([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Microsoft Outlook", systemImage: "paperplane") }
                Menu {
                    Button { actions.exportAppleNotes([]) } label: { Label("Rapport seul", systemImage: "note.text") }
                    Button { actions.exportAppleNotes(.includeSlidesPDF) } label: { Label("Rapport + slides", systemImage: "note.text.badge.plus") }
                    Button { actions.exportAppleNotes([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "note.text") }
                    Button { actions.exportAppleNotes([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "note.text.badge.plus") }
                } label: { Label("Exporter vers Apple Notes", systemImage: "note.text") }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }
            .disabled(!actions.hasReport)

            Divider()
            Button(action: actions.toggleCustomPrompt) { Label("Détails de la réunion…", systemImage: "slider.horizontal.3") }
            // Une note n'a pas d'audio : l'import WAV et tout le sous-menu
            // Audio disparaissent (cf. `MeetingMenuActions.isEnabled`, qui
            // grise les mêmes items côté menu natif). L'import Calendrier
            // reste : dater une note sur un événement a un sens.
            Menu {
                Button(action: actions.importCalendar) { Label("Importer Calendrier", systemImage: "calendar.badge.plus") }
                if !actions.isNote {
                    Button(action: actions.importExistingWAV) { Label("Importer un WAV existant", systemImage: "waveform.badge.plus") }
                }
            } label: { Label("Importer", systemImage: "square.and.arrow.down") }
            if !actions.isNote {
                Menu {
                    Button(action: actions.editAudio) { Label("Éditer l'audio…", systemImage: "scissors") }
                        .disabled(!actions.hasPlayableAudio)
                    Button(action: actions.revealWAV) { Label("Révéler le WAV dans Finder", systemImage: "folder") }
                        .disabled(!actions.hasPlayableAudio)
                } label: { Label("Audio", systemImage: "waveform") }
            }

            Divider()
            Button(role: .destructive, action: actions.deleteMeeting) {
                Label("Supprimer la réunion…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
