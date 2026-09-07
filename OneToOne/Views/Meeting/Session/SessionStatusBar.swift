import SwiftUI

/// La barre d'état du mode séance plein écran — **le seul chrome de l'écran**
/// (spec §2.6 : « Aucun chrome hors la barre d'état (point d'enregistrement,
/// titre, temps, avatars, locuteur courant, `Clore la séance`) »).
///
/// Ni fil d'Ariane, ni barre d'espaces, ni sélecteur de mode, ni menu `⋯` : on
/// est en séance, et chaque commande visible est une occasion de cliquer
/// ailleurs qu'à l'endroit où l'on prend des notes.
struct SessionStatusBar: View {

    /// Hauteur de la barre (capture 1b).
    static let height: CGFloat = 46

    /// La référence du projet, telle qu'elle est écrite dans le titre
    /// (`[P25_110] Partage statut final…` → `P25_110`).
    ///
    /// Le titre entier ne tient pas dans une barre d'état de séance et n'y
    /// sert à rien : on sait de quelle réunion il s'agit, on y est. La
    /// référence, elle, sert à la nommer à voix haute.
    static func reference(title: String, projectCode: String?) -> String {
        if let debut = title.firstIndex(of: "["),
           let fin = title.firstIndex(of: "]"),
           debut < fin {
            let interieur = title[title.index(after: debut)..<fin]
                .trimmingCharacters(in: .whitespaces)
            if !interieur.isEmpty { return interieur }
        }
        if let projectCode, !projectCode.isEmpty { return projectCode }
        let propre = title.trimmingCharacters(in: .whitespaces)
        return propre.isEmpty ? "Réunion" : propre
    }

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Vrai quand l'enregistrement de **cette** réunion tourne : le point rouge
    /// pulse alors. `AudioRecorderService.isRecording` seul allumerait la
    /// pastille dans toutes les fenêtres ouvertes.
    let isRecording: Bool
    /// Le locuteur courant, `nil` quand il n'est pas résolu — la mention est
    /// alors masquée plutôt que rendue en `?? parle`.
    let locuteur: SessionCurrentSpeaker.Locuteur?
    let onClose: () -> Void

    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }
    /// Phase du battement du point d'enregistrement.
    @State private var pulse = false

    private var duree: Double {
        max(screen.playhead.duration, Double(meeting.durationSeconds))
    }

    var body: some View {
        HStack(spacing: 12) {
            pointDEnregistrement
            Text("En séance · \(Self.reference(title: meeting.title, projectCode: meeting.project?.code))")
                .font(.plexSans(13, .semibold))
                .foregroundStyle(c.ink1)
                .lineLimit(1)
            Text("\(MeetingPlayhead.mmss(screen.playhead.t)) / \(MeetingPlayhead.mmss(duree))")
                .font(.plexMono(12, .medium))
                .monospacedDigit()
                .foregroundStyle(c.ink4)
            Spacer(minLength: 12)
            avatars
            if let locuteur {
                Text(locuteur.libelle)
                    .font(.plexSans(11.5))
                    .foregroundStyle(c.ink3)
                    .lineLimit(1)
                    .help("\(locuteur.nom) parle")
                    .transition(.opacity)
            }
            boutonDeCloture
        }
        .padding(.horizontal, 18)
        .frame(height: Self.height)
        .background(c.base)
    }

    // MARK: - Pastille d'enregistrement

    /// Le point rouge, qui **pulse** pendant l'enregistrement et reste fixe
    /// sinon. Un point rouge immobile pendant une séance non enregistrée est
    /// exactement le malentendu qui fait perdre une réunion.
    @ViewBuilder
    private var pointDEnregistrement: some View {
        Circle()
            .fill(isRecording ? One2OneToken.railElapsed : c.ink4)
            .frame(width: 12, height: 12)
            .opacity(isRecording && pulse ? 0.35 : 1)
            .animation(isRecording
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                       : .default,
                       value: pulse)
            .onAppear { pulse = isRecording }
            .onChange(of: isRecording) { _, enCours in pulse = enCours }
            .help(isRecording ? "Enregistrement en cours" : "Aucun enregistrement en cours")
    }

    // MARK: - Avatars

    /// Les pastilles des participants (`PY NL CP LS CA LD` sur la capture). La
    /// pastille du locuteur courant est remplie : c'est la même information que
    /// « CP parle », donnée là où l'œil est déjà.
    private var avatars: some View {
        HStack(spacing: 4) {
            ForEach(meeting.participants.prefix(8), id: \.persistentModelID) { participant in
                AvatarCircle(collaborator: participant,
                             size: 24,
                             tint: participant.name == locuteur?.nom
                                 // Aucune encre « tenu » dans la palette
                                 // `dark/*` (cf. `One2OneTheme`), mais un
                                 // **fond** vert profond porte des initiales
                                 // blanches sans difficulté.
                                 ? One2OneToken.okDeep
                                 : c.pill)
            }
            if meeting.participants.count > 8 {
                Text("+\(meeting.participants.count - 8)")
                    .font(.plexSans(10, .medium))
                    .foregroundStyle(c.ink3)
            }
        }
    }

    // MARK: - Clore la séance

    /// `Clore la séance` en `accent/report` plein (capture 1b). Ne coupe pas
    /// l'enregistrement : ce bouton **sort du mode**, l'arrêt de
    /// l'enregistrement reste la pilule audio de la barre du haut. Un bouton
    /// qui ferait les deux serait irréversible sans le dire.
    private var boutonDeCloture: some View {
        Button(action: onClose) {
            Text("Clore la séance")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.report)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Quitter le mode séance et revenir au cockpit (Esc)")
    }
}
