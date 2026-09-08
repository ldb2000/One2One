import SwiftUI

/// La frise audio en pied du poste de pilotage (spec §2.7 : « frise audio en
/// pied d'écran, pleine largeur, avec étiquettes de marqueurs (`04:12`,
/// `DÉCISION`) et bouton `✂ Éditer` qui ouvre la modale d'édition audio
/// existante »).
///
/// Elle n'est pas une seconde frise : c'est `AudioTimelineStrip` du lot 2, avec
/// son mode étiqueté allumé. Ce fichier n'ajoute que ce que la capture montre
/// autour d'elle — le bouton de lecture et `✂ Éditer`.
///
/// `✂ Éditer` passe par `MeetingMenuActions.editAudio`, la même closure que le
/// menu `⋯` et le menu natif : la feuille d'édition audio est présentée par
/// `MeetingView`, et une seconde présentation ici en ferait deux.
struct ReviewAudioTimeline: View {

    /// Diamètre du bouton de lecture (capture 1c : un rond noir plein).
    static let taillePlay: CGFloat = 30

    let meeting: Meeting
    let screen: MeetingScreenModel
    let menuActions: MeetingMenuActions

    @ObservedObject private var lecteur: AudioPlayerService

    init(meeting: Meeting, screen: MeetingScreenModel, menuActions: MeetingMenuActions) {
        self.meeting = meeting
        self.screen = screen
        self.menuActions = menuActions
        self.lecteur = screen.playhead.player
    }

    private var playhead: MeetingPlayhead { screen.playhead }

    var body: some View {
        HStack(spacing: 10) {
            boutonLecture
            // Les deux bornes de temps (`00:00` … `23:24`) sont celles de la
            // frise elle-même : les redoubler ici en afficherait quatre.
            AudioTimelineStrip(meeting: meeting, screen: screen, labelled: true)
                .frame(maxWidth: .infinity)
            boutonEditer
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(One2OneToken.bgCanvas)
    }

    // MARK: - Lecture

    /// Charge le fichier au premier clic puis bascule lecture/pause.
    ///
    /// Le lecteur est celui de `MeetingScreenModel.playhead` — pas un second :
    /// deux lecteurs pour une réunion, ce sont deux positions, et la frise
    /// n'afficherait plus celle qu'on entend.
    private var boutonLecture: some View {
        Button(action: basculerLecture) {
            Image(systemName: lecteur.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .frame(width: Self.taillePlay, height: Self.taillePlay)
                .background(Circle().fill(One2OneToken.ink1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!menuActions.hasPlayableAudio)
        .help(menuActions.hasPlayableAudio
              ? (lecteur.isPlaying ? "Mettre en pause" : "Écouter l'enregistrement")
              : "Aucun enregistrement à écouter")
    }

    private func basculerLecture() {
        guard let url = meeting.wavFileURL else { return }
        if lecteur.loadedURL != url {
            do {
                try lecteur.load(url: url)
            } catch {
                // Un fichier illisible ne doit pas faire basculer l'axe en
                // relecture : `t` resterait figé sur un lecteur muet.
                return
            }
        }
        playhead.beginPlayback()
        lecteur.toggle()
    }

    // MARK: - Édition

    private var boutonEditer: some View {
        Button(action: menuActions.editAudio) {
            Text("✂ Éditer")
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .fill(One2OneToken.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!menuActions.isEnabled(.editAudio))
        .help(menuActions.hasPlayableAudio
              ? "Rogner ou diviser l'enregistrement"
              : "Aucun enregistrement à éditer")
    }
}
