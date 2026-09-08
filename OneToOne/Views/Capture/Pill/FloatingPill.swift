import SwiftUI

/// Le contenu de la pastille flottante : 300 × 40, sombre, posée sur Teams
/// (spec §5.4, capture `4b-pastille-flottante.png`).
///
/// `● mm:ss | ◫ Capturer | ✎ Note | n`, plus deux surfaces qui se déplient sous elle :
/// le champ de note et la carte de confirmation.
///
/// Copié de `Teams-Capture/Sources/TeamsCapture/Pill/FloatingPill.swift` pour la mise
/// en page (capsule, séparateur, `TimelineView` pour le chrono, point pulsant réarmé) ;
/// `✎ Note` et `＋ Action depuis la capture` sont **propres à OneToOne** — Teams-Capture
/// n'a ni notes ni actions et refusait un bouton mort.
///
/// La vue ne décide rien : tout est dans `SessionPillModel`.
struct FloatingPill: View {

    let model: SessionPillModel
    /// Le tracé d'une zone à la souris (`⌥⌘⇧S` ou l'entrée `Zone…`).
    let onSelectRegion: () -> Void

    /// Piloté à **chaque** transition de `isRecording`, jamais une seule fois pour de
    /// bon : `.animation(value:)` ne réarme l'animation que quand la valeur change, et
    /// un premier jet qui ne basculait qu'à l'apparition laissait le point figé après
    /// une reprise d'enregistrement (défaut relevé dans Teams-Capture).
    @State private var pulses = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pastille
            if model.isEditingNote { champDeNote }
            if let confirmation = model.confirmation { carte(confirmation) }
        }
        // Hauteur explicite, la **même** que celle que le contrôleur donne au panneau :
        // le contenu est ainsi ancré en haut de la fenêtre, et les surfaces dépliées
        // apparaissent bien sous la pastille quel que soit le sens dans lequel la
        // fenêtre a grandi.
        .frame(width: One2OneToken.pillWidth, height: model.panelHeight, alignment: .topLeading)
    }

    // MARK: - La pastille

    private var pastille: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isRecording ? One2OneToken.railElapsed : One2OneToken.darkInk4)
                .frame(width: 8, height: 8)
                .opacity(pulses ? 0.35 : 1)
                .animation(model.isRecording
                           ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                           : .default,
                           value: pulses)
                .onAppear { pulses = model.isRecording }
                .onChange(of: model.isRecording) { _, enregistre in pulses = enregistre }

            // `TimelineView` et non une simple lecture : le `t` de la séance se
            // calcule depuis l'horloge (`MeetingPlayhead.currentTime`), pas depuis
            // un état observé — rien ne provoquerait la réévaluation de cette vue,
            // et le chrono resterait figé entre deux captures. La lecture est
            // **pure** : la version qui appelait `refresh()` ici écrivait `t`
            // pendant le rendu et bouclait (gel du 2026-09-08).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(model.timecode)
                    .font(.plexMono(11, .medium))
                    .foregroundStyle(One2OneToken.darkInk1)
                    .monospacedDigit()
            }

            Rectangle()
                .fill(One2OneToken.darkInk4.opacity(0.4))
                .frame(width: 1, height: 16)

            Button("◫ Capturer") { Task { await model.capture() } }
                .buttonStyle(SessionPillButtonStyle(tint: One2OneToken.action))
                .help("Capturer la source configurée (⌘⇧S) — ⌥ pour tracer une zone")
                .contextMenu {
                    Button("Zone…") { onSelectRegion() }
                }

            Button("✎ Note") { note() }
                .buttonStyle(SessionPillButtonStyle(tint: nil))
                .help("Nouvelle note au timecode courant (⌘⇧N)")

            Spacer(minLength: 0)

            Text("\(model.captureCount)")
                .font(.plexMono(11, .medium))
                .foregroundStyle(One2OneToken.darkInk3)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(width: One2OneToken.pillWidth, height: One2OneToken.pillHeight)
        .background(Capsule().fill(One2OneToken.pillBackground))
    }

    private func note() {
        model.beginNote()
        noteFocused = true
    }

    // MARK: - Le champ de note

    private var champDeNote: some View {
        HStack(spacing: 6) {
            Text("✎")
                .font(.plexSans(11))
                .foregroundStyle(One2OneToken.darkInk4)
            TextField("Note au timecode \(model.timecode)", text: Binding(
                get: { model.noteDraft },
                set: { model.noteDraft = $0 }))
                .textFieldStyle(.plain)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.darkInk1)
                .focused($noteFocused)
                // `⌘⏎` crée, `Esc` referme (spec §1.4). `onSubmit` seul ne suffit pas :
                // il se déclenche sur `⏎` nu, qui doit rester une simple validation.
                .onSubmit { _ = model.submitNote() }
                .onExitCommand { model.cancelNote() }
                .overlay {
                    Button("") { _ = model.submitNote() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            Text("⌘⏎")
                .font(.plexMono(9.5))
                .foregroundStyle(One2OneToken.darkInk4)
        }
        .padding(.horizontal, 10)
        .frame(width: One2OneToken.pillConfirmationWidth + 60, height: 34)
        .background(RoundedRectangle(cornerRadius: One2OneToken.radiusPanel).fill(One2OneToken.darkPill))
        .padding(.top, 6)
        .padding(.leading, 12)
        .onAppear { noteFocused = true }
    }

    // MARK: - La carte de confirmation

    private func carte(_ confirmation: SessionPillConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(confirmation.capture == nil ? One2OneToken.warn : One2OneToken.ok)
                    .frame(width: 6, height: 6)
                Text(confirmation.header)
                    .font(.plexMono(9.5, .semibold))
                    .foregroundStyle(confirmation.capture == nil ? One2OneToken.darkWarn : One2OneToken.ok)
            }

            if let capture = confirmation.capture {
                vignette(capture)
            }

            Text(confirmation.textLine)
                .font(.plexSans(11))
                .foregroundStyle(One2OneToken.darkInk3)
                .lineLimit(1)
                .truncationMode(.tail)

            if confirmation.offersAction {
                Button("＋ Action depuis la capture") {
                    _ = model.createActionFromConfirmation()
                }
                .buttonStyle(SessionPillButtonStyle(tint: One2OneToken.action, fillsWidth: true))
            }
        }
        .padding(10)
        .frame(width: One2OneToken.pillConfirmationWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: One2OneToken.radiusPanel).fill(One2OneToken.darkCard))
        .padding(.top, 6)
        .padding(.leading, 12)
        .transition(.opacity)
    }

    /// La vignette de la capture, servie par le cache du lot 7 : sans lui, la carte
    /// redécoderait un PNG plein écran à chaque rendu.
    private func vignette(_ capture: SessionPillCapture) -> some View {
        Group {
            if let image = CaptureThumbnailCache.shared.thumbnail(forPath: capture.thumbnailPath) {
                Image(decorative: image, scale: 2, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fichier illisible : un cadre muet plutôt qu'un cadre vide qui
                // laisserait croire à une capture noire.
                RoundedRectangle(cornerRadius: One2OneToken.radiusPreview)
                    .fill(One2OneToken.darkPill)
            }
        }
        .frame(width: One2OneToken.pillThumbnailWidth, height: One2OneToken.pillThumbnailHeight)
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview))
    }
}

/// Bouton de la pastille : compact, plein quand il porte l'action principale, nu
/// sinon. Le style primaire du lot 7 (`CapturePrimaryButtonStyle`) occupe toute la
/// largeur disponible — dans une pastille de 300 px, il chasserait tout le reste.
struct SessionPillButtonStyle: ButtonStyle {

    /// Teinte du fond plein. `nil` = bouton nu (`✎ Note`).
    var tint: Color?
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plexSans(11.5, .medium))
            .foregroundStyle(tint == nil ? One2OneToken.darkInk2 : One2OneToken.onFilledButton)
            .padding(.horizontal, tint == nil ? 4 : 9)
            .padding(.vertical, 4)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background {
                if let tint {
                    Capsule().fill(tint.opacity(configuration.isPressed ? 0.8 : 1))
                }
            }
            .opacity(configuration.isPressed && tint == nil ? 0.6 : 1)
    }
}
