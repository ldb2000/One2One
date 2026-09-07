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

    /// `player` reste injectable, mais sans valeur par défaut évaluée hors de
    /// l'acteur principal : `AudioPlayerService()` est `@MainActor`, et un
    /// argument par défaut est évalué dans le contexte de l'appelant.
    init(meetingStableID: UUID,
         player: AudioPlayerService? = nil,
         now: @escaping () -> Date = Date.init) {
        self.meetingStableID = meetingStableID
        self.player = player ?? AudioPlayerService()
        self.now = now
    }

    // MARK: - Sources

    /// Passe l'axe en mode séance. Idempotent sur la même origine : un
    /// enregistrement complémentaire ne doit pas décaler les notes déjà posées.
    func beginRecording(startedAt: Date) {
        if case .recording(let existant) = source, existant == startedAt { return }
        source = .recording(startedAt: startedAt)
        refresh()
        playheadLog.info("beginRecording: meeting=\(self.meetingStableID.uuidString, privacy: .public)")
    }

    /// Passe l'axe en mode relecture (le lecteur devient la source de `t`).
    func beginPlayback() {
        source = .playback
        refresh()
    }

    /// Repasse à l'arrêt : `t` reste où il est, plus rien ne le fait avancer.
    func stop() {
        source = .idle
    }

    /// Relit la source active. Appelée par les surfaces qui affichent `t` (un
    /// `TimelineView` en séance, le rafraîchissement du lecteur en relecture) —
    /// et par les tests, avec leur propre horloge.
    func refresh() {
        switch source {
        case .idle:
            break
        case .recording(let startedAt):
            t = max(0, now().timeIntervalSince(startedAt))
            duration = max(duration, t)
        case .playback:
            t = player.currentTime
            duration = player.duration
        }
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

    // MARK: - Registre

    /// Nombre de têtes de lecture retenues simultanément.
    ///
    /// Le registre garde des références **fortes**, bornées en LRU. Un cache
    /// faible se viderait aussitôt : `MeetingView` est une `struct` qui ne peut
    /// retenir l'instance sans initialiseur explicite, et ce fichier est
    /// réécrit en parallèle par le lot 0A. Quatre réunions ouvertes couvrent
    /// l'usage réel (une fenêtre principale plus quelques fenêtres détachées) ;
    /// l'éviction met le lecteur en pause pour ne pas laisser un fichier jouer
    /// sans surface pour l'arrêter.
    static let registryCapacity = 4

    private static var registry: [(id: UUID, playhead: MeetingPlayhead)] = []

    /// Nombre d'entrées actuellement retenues (diagnostic et tests).
    static var registryCount: Int { registry.count }

    /// La tête de lecture de `meeting`, créée à la demande. Deux appels pour la
    /// même réunion rendent la même instance : c'est ce qui fait que toutes les
    /// surfaces partagent une position.
    static func `for`(meeting: Meeting) -> MeetingPlayhead {
        let id = meeting.ensuredStableID
        if let index = registry.firstIndex(where: { $0.id == id }) {
            let entry = registry.remove(at: index)
            registry.append(entry)          // le plus récemment utilisé en queue
            return entry.playhead
        }
        let playhead = MeetingPlayhead(meetingStableID: id)
        if let startedAt = meeting.recordingStartedAt,
           AudioRecorderService.shared.isRecording(for: id) {
            playhead.beginRecording(startedAt: startedAt)
        }
        registry.append((id: id, playhead: playhead))
        while registry.count > registryCapacity {
            let evincee = registry.removeFirst()
            evincee.playhead.player.pause()
        }
        return playhead
    }

    /// Vide le registre. Réservé aux tests : en production, l'éviction LRU
    /// suffit.
    static func resetRegistryForTesting() {
        for entry in registry { entry.playhead.player.pause() }
        registry.removeAll()
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
