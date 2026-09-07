import Foundation
import SwiftData

/// La poignée d'une réunion ouverte : tout ce dont une surface **hors hiérarchie
/// SwiftUI** a besoin pour agir sur elle.
///
/// La pastille flottante vit dans un `NSPanel`, sans environnement, sans `@Query` et
/// sans le `@StateObject` de `MeetingView` qui porte le `ScreenCaptureService`. Sans
/// cette poignée, elle ne pourrait ni capturer, ni lire le chrono, ni écrire une note :
/// elle devrait ouvrir la fenêtre de l'application — exactement ce que le critère n° 2
/// du chantier 4 interdit.
///
/// Le coordinateur de capture est un **fournisseur** et non une valeur retenue :
/// `CaptureSessionCoordinator` est une valeur reconstruite à chaque rendu (lot 7), et en
/// garder une copie figerait la réunion et le contexte d'il y a dix minutes.
@MainActor
final class ActiveMeetingHandle {

    let meetingStableID: UUID
    let meeting: Meeting
    let screen: MeetingScreenModel
    let context: ModelContext
    /// Instant d'entrée en séance : c'est lui qui départage deux réunions ouvertes.
    let enteredAt: Date
    private let captureProvider: @MainActor () -> CaptureSessionCoordinator

    init(meeting: Meeting,
         screen: MeetingScreenModel,
         context: ModelContext,
         enteredAt: Date = Date(),
         capture: @escaping @MainActor () -> CaptureSessionCoordinator) {
        self.meetingStableID = meeting.ensuredStableID
        self.meeting = meeting
        self.screen = screen
        self.context = context
        self.enteredAt = enteredAt
        self.captureProvider = capture
    }

    var capture: CaptureSessionCoordinator { captureProvider() }

    /// La réunion est en mode séance plein écran (lot 4).
    var isSessionFullscreen: Bool { screen.session.isPresented }
}

/// Ce que la règle de priorité a besoin de savoir d'une réunion ouverte. Un type nu,
/// sans SwiftData : la règle se teste sans store ni conteneur.
struct ActiveMeetingSession: Equatable, Sendable {
    let meetingStableID: UUID
    let enteredAt: Date
}

/// La « réunion active » de l'application : celle sur laquelle la pastille flottante,
/// `⌘⇧S` et `⌘⇧N` agissent.
///
/// Il en faut une notion **globale** parce que les trois surfaces qui en dépendent
/// vivent hors de toute vue : un `NSPanel` et deux rappels Carbon. `FocusedValues`,
/// qu'utilise le menu Réunion, ne convient pas : la pastille sert précisément quand
/// One2One n'a **pas** le focus.
@MainActor
@Observable
final class ActiveMeetingRegistry {

    static let shared = ActiveMeetingRegistry()

    /// Les réunions ouvertes en séance, dans l'ordre où elles se sont enregistrées.
    private(set) var handles: [ActiveMeetingHandle] = []

    /// Qui enregistre, en dernier ressort. Injectable pour les tests ; en production,
    /// c'est `AudioRecorderService`, seul détenteur de la vérité (`activeMeetingID`).
    var recordingMeetingID: @MainActor () -> UUID?

    init(recordingMeetingID: @escaping @MainActor () -> UUID? = { AudioRecorderService.shared.activeMeetingID }) {
        self.recordingMeetingID = recordingMeetingID
    }

    // MARK: - Table des poignées

    /// Enregistre — ou remplace — la poignée d'une réunion.
    ///
    /// Idempotent par réunion : le modificateur qui appelle est posé sur une vue dont
    /// `onAppear` se déclenche plusieurs fois, et deux poignées pour la même réunion
    /// laisseraient la seconde décider avec le contexte de la première.
    func register(_ handle: ActiveMeetingHandle) {
        handles.removeAll { $0.meetingStableID == handle.meetingStableID }
        handles.append(handle)
    }

    /// Retire une réunion. Ne retire que **sa** poignée : deux fenêtres réunion
    /// ouvertes ne doivent pas se désenregistrer l'une l'autre.
    func unregister(meetingStableID: UUID) {
        handles.removeAll { $0.meetingStableID == meetingStableID }
    }

    var sessions: [ActiveMeetingSession] {
        handles.map { ActiveMeetingSession(meetingStableID: $0.meetingStableID, enteredAt: $0.enteredAt) }
    }

    /// La poignée de la réunion active, `nil` quand aucune réunion n'est ouverte en
    /// séance — même si un enregistrement tourne : sans poignée, il n'y a rien à
    /// piloter, et une pastille sans cible serait un bouton mort.
    var activeHandle: ActiveMeetingHandle? {
        guard let id = Self.activeID(recording: recordingMeetingID(), sessions: sessions) else { return nil }
        return handles.first { $0.meetingStableID == id }
    }

    /// Les conditions d'affichage de la pastille pour l'état courant.
    var pillConditions: SessionPillConditions {
        guard let handle = activeHandle else { return SessionPillConditions() }
        return SessionPillConditions(
            hasActiveMeeting: true,
            isSessionFullscreen: handle.isSessionFullscreen,
            isRecording: recordingMeetingID() == handle.meetingStableID)
    }

    // MARK: - La règle

    /// Quelle réunion est active.
    ///
    /// 1. Celle qui **enregistre** : c'est le seul état de l'application qui parle d'une
    ///    séance en cours indépendamment de ce qui est affiché.
    /// 2. Sinon la **dernière entrée en séance** : deux réunions peuvent être ouvertes
    ///    (fenêtre principale + fenêtre dédiée), et la plus récemment ouverte est celle
    ///    qu'on regarde.
    /// 3. Sinon aucune.
    ///
    /// À égalité d'instant d'entrée, la dernière enregistrée gagne : l'ordre de la table
    /// est l'ordre d'ouverture, et un départage par identifiant donnerait un résultat
    /// stable mais arbitraire.
    ///
    /// La réunion qui enregistre ne l'emporte que si elle est **dans** la table : un
    /// enregistrement lancé depuis le tableau de bord, sur une réunion dont aucun écran
    /// n'est ouvert, ne donne aucune prise — désigner cette réunion ferait disparaître
    /// la pastille de la séance qu'on a effectivement sous les yeux.
    static func activeID(recording: UUID?, sessions: [ActiveMeetingSession]) -> UUID? {
        if let recording, sessions.contains(where: { $0.meetingStableID == recording }) {
            return recording
        }
        var meilleure: ActiveMeetingSession?
        for session in sessions {
            if let courante = meilleure, session.enteredAt < courante.enteredAt { continue }
            meilleure = session
        }
        return meilleure?.meetingStableID
    }
}
