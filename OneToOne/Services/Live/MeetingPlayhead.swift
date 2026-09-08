import Foundation
import os

private let playheadLog = Logger(subsystem: "com.onetoone.app", category: "playhead")

/// L'axe temps **partagé** d'une réunion : `t` en secondes depuis le début de
/// l'enregistrement (spec §1.3, §2.4).
///
/// Avant ce service, `AudioPlayerService` était instancié **deux fois** —
/// `MeetingView` et `AudioWaveformEditor` — sans aucune position commune : un
/// clic sur un timecode de note ne pouvait pas déplacer le curseur de la frise,
/// et rien ne reliait une capture à l'audio. Ici, une réunion possède **un**
/// lecteur et **une** position, que toutes les surfaces lisent.
///
/// Deux sources selon le moment :
/// - **en séance** : `t = maintenant − Meeting.recordingStartedAt` (horloge
///   injectable `now`, pour que les tests n'attendent pas) ;
/// - **en relecture** : `t = player.currentTime`.
///
/// `@MainActor` : la tête de lecture est lue par des vues et possède un
/// `AudioPlayerService`, lui-même `@MainActor`.
@Observable
@MainActor
final class MeetingPlayhead {

    // MARK: - Marqueurs

    /// Un repère sur la frise. Le losange (décision), le rond (note) et le
    /// carré (capture) de la spec §2.4.
    struct Marker: Identifiable, Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case note
            case decision
            case risk
            case capture
            case board
        }

        var id: UUID = UUID()
        var t: Double
        var kind: Kind
        var label: String = ""
    }

    // MARK: - Source de l'axe

    enum Source: Equatable {
        /// Ni enregistrement, ni lecture : `t` ne bouge pas.
        case idle
        /// Séance en cours ; l'origine est l'instant de démarrage.
        case recording(startedAt: Date)
        /// Relecture ; l'origine est le fichier chargé dans `player`.
        case playback
    }

    // MARK: - État

    /// `stableID` de la réunion à laquelle cette tête de lecture appartient.
    let meetingStableID: UUID

    /// Le lecteur audio **unique** de la réunion. Exposé pour que les vues
    /// existantes (`MeetingTopChromeBar`, `MeetingContextualRecorderBar`,
    /// `AudioWaveformEditor`) le reçoivent en `@ObservedObject` sans changer
    /// leur contrat.
    let player: AudioPlayerService

    /// Horloge injectable. Les tests la remplacent ; la production garde `Date`.
    var now: () -> Date

    private(set) var source: Source = .idle

    /// Position courante, en secondes.
    private(set) var t: Double = 0

    /// Durée connue de l'axe : celle du fichier en relecture, celle écoulée en
    /// enregistrement. Zéro tant que rien n'est chargé ni enregistré.
    var duration: Double = 0

    /// Vrai quand l'audio tourne. Dérivé du lecteur : pas de second drapeau à
    /// tenir en phase.
    var isPlaying: Bool { player.isPlaying }

    /// Le défilement suit-il la position ? (`Suivre` / `Reprendre le suivi`
    /// des colonnes de notes et de transcription.) Actif par défaut.
    var follow: Bool = true

    /// Repères de la frise, **toujours triés par timecode** : les vues les
    /// dessinent dans l'ordre reçu.
    var markers: [Marker] = [] {
        didSet {
            if !markers.isSorted(by: { $0.t < $1.t }) {
                markers.sort { $0.t < $1.t }
            }
        }
    }

    /// `t` formaté pour l'affichage (`04:12`).
    var formatted: String { Self.mmss(t) }

    // MARK: - Lecture d'affichage

    /// La position **calculée** depuis la source, sans rien écrire.
    ///
    /// Distincte de `t`, qui est la position *publiée*. C'est la seule lecture
    /// autorisée depuis un rendu SwiftUI : appeler `refresh()` dans un corps de
    /// vue écrivait `t` et `duration` pendant l'évaluation de ce corps, donc
    /// invalidait la vue qui venait de les lire — chaque rendu en produisait un
    /// autre. C'est le gel du 2026-09-08, observé au démarrage de
    /// l'enregistrement (100 % du thread principal dans
    /// `GraphHost.flushTransactions`, sous `FloatingPill.pastille`).
    ///
    /// Aucune dépendance d'observation n'y est prise en séance : la valeur vient
    /// de l'horloge, et c'est le battement (`refresh()`) qui réveille les vues.
    var currentTime: Double {
        switch source {
        case .idle:
            return t
        case .recording(let startedAt):
            return max(0, now().timeIntervalSince(startedAt))
        case .playback:
            return player.currentTime
        }
    }

    /// Le timecode à porter sur une note ou une capture. `nil` quand la réunion
    /// n'a pas d'axe temps — ni enregistrement, ni lecture, ni position
    /// acquise : la note est alors écrite **sans** `t` plutôt qu'à `00:00`, où
    /// son marqueur désignerait un instant où rien ne s'est passé.
    var elapsedIfAny: Double? {
        let valeur = currentTime
        if case .idle = source, valeur <= 0 { return nil }
        return valeur
    }

    /// `player` reste injectable, mais sans valeur par défaut évaluée hors de
    /// l'acteur principal : `AudioPlayerService()` est `@MainActor`, et un
    /// argument par défaut est évalué dans le contexte de l'appelant.
    ///
    /// `recordingTick` est la cadence du battement en séance. Une seconde
    /// suffit à un chrono `mm:ss`, et chaque écriture de `t` invalide **toutes**
    /// les surfaces qui le lisent (frise, colonne de transcription, composeur de
    /// note) : la relever serait payé à chaque rendu. Les tests la raccourcissent.
    init(meetingStableID: UUID,
         player: AudioPlayerService? = nil,
         now: @escaping () -> Date = Date.init,
         recordingTick: Duration = .seconds(1),
         playbackTick: Duration = .milliseconds(250)) {
        self.meetingStableID = meetingStableID
        self.player = player ?? AudioPlayerService()
        self.now = now
        self.recordingTick = recordingTick
        self.playbackTick = playbackTick
    }

    deinit {
        ticker?.cancel()
    }

    // MARK: - Sources

    /// Passe l'axe en mode séance. Idempotent sur la même origine : un
    /// enregistrement complémentaire ne doit pas décaler les notes déjà posées.
    func beginRecording(startedAt: Date) {
        if case .recording(let existant) = source, existant == startedAt {
            // Idempotent sur l'origine, mais le battement doit tourner : un
            // écran remonté rappelle `beginRecording` sans rien changer.
            if ticker == nil { startTicking() }
            return
        }
        source = .recording(startedAt: startedAt)
        refresh()
        startTicking()
        playheadLog.info("beginRecording: meeting=\(self.meetingStableID.uuidString, privacy: .public)")
    }

    /// Passe l'axe en mode relecture (le lecteur devient la source de `t`).
    func beginPlayback() {
        source = .playback
        refresh()
        startTicking()
    }

    /// Repasse à l'arrêt : `t` reste où il est, plus rien ne le fait avancer.
    func stop() {
        source = .idle
        stopTicking()
    }

    /// Publie la position de la source active dans `t`.
    ///
    /// Appelée par le **battement** et par les tests, avec leur propre horloge
    /// — jamais depuis un corps de vue : c'est une écriture, et une écriture
    /// pendant un rendu invalide ce rendu (cf. `currentTime`).
    ///
    /// Les deux affectations sont gardées par une comparaison : `@Observable`
    /// notifie toute écriture, même d'une valeur identique, et une notification
    /// pour rien réveille la frise, la transcription et le composeur de note.
    func refresh() {
        switch source {
        case .idle:
            break
        case .recording:
            let valeur = currentTime
            if t != valeur { t = valeur }
            if valeur > duration { duration = valeur }
        case .playback:
            let valeur = player.currentTime
            if t != valeur { t = valeur }
            if duration != player.duration { duration = player.duration }
        }
    }

    // MARK: - Battement

    /// La cadence du battement en séance, et celle en relecture.
    @ObservationIgnored private let recordingTick: Duration
    @ObservationIgnored private let playbackTick: Duration

    /// Le battement qui fait avancer `t`.
    ///
    /// C'est lui, et non un rendu de vue, qui publie le temps : avant le
    /// correctif du 2026-09-08, `t` n'avançait que parce que le corps de la
    /// pastille flottante appelait `refresh()` — donc jamais quand la pastille
    /// était masquée (les notes de séance étaient horodatées à `00:00`), et en
    /// boucle infinie quand elle était visible.
    ///
    /// `nonisolated(unsafe)` : lu et écrit uniquement depuis le `MainActor`,
    /// mais le `deinit` d'une classe `@MainActor` n'est pas lui-même isolé.
    @ObservationIgnored private nonisolated(unsafe) var ticker: Task<Void, Never>?

    private var tick: Duration? {
        switch source {
        case .idle:      return nil
        case .recording: return recordingTick
        case .playback:  return playbackTick
        }
    }

    private func startTicking() {
        stopTicking()
        guard let tick else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Déplacement

    /// Place la position à `seconds`, bornée à `0…duration`. En relecture, le
    /// lecteur suit ; en séance, seul le curseur de lecture bouge (on ne
    /// remonte pas le temps d'un enregistrement en cours).
    func seek(to seconds: Double) {
        let borne = max(0, min(seconds, max(duration, 0)))
        t = borne
        if case .playback = source {
            player.seek(to: borne)
        }
    }

    /// Le marqueur le plus proche de `t`, dans `tolerance` secondes. `nil` si
    /// aucun n'est assez près — l'appelant ne doit pas afficher un repère
    /// arbitraire à la place.
    func marker(at t: Double, tolerance: Double = 0.5) -> Marker? {
        markers
            .filter { abs($0.t - t) <= tolerance }
            .min { abs($0.t - t) < abs($1.t - t) }
    }

    // MARK: - Formatage

    /// `mm:ss`, ou `h:mm:ss` au-delà de l'heure. Une position négative — une
    /// horloge qui recule, un fichier vide — s'affiche `00:00` plutôt que de
    /// produire un temps absurde.
    /// `nonisolated` : formatage pur, appelé aussi depuis des services non
    /// isolés (`MeetingNoteStore`, les constructeurs de rapport).
    nonisolated static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Marqueurs

    /// Pose un marqueur sur la frise. Le tableau reste trié (`didSet`), donc
    /// l'ordre d'appel n'a pas d'importance.
    func addMarker(at t: Double, kind: Marker.Kind, label: String = "") {
        markers.append(Marker(t: t, kind: kind, label: label))
    }
}

private extension Array {
    /// Vrai si le tableau est déjà trié selon `areInIncreasingOrder` — évite un
    /// `sort` (et la récursion du `didSet`) quand l'appelant a déjà trié.
    func isSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> Bool {
        guard count > 1 else { return true }
        for i in 1..<count where areInIncreasingOrder(self[i], self[i - 1]) {
            return false
        }
        return true
    }
}
