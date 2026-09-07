import Foundation
import SwiftData

/// Import et resynchronisation d'une réunion depuis le calendrier.
///
/// Ces trois fonctions vivaient dans `MeetingView` : elles n'ont rien d'une
/// vue — elles lisent EventKit, résolvent des collaborateurs et écrivent le
/// modèle. Le programme de refonte interdit d'ajouter à `MeetingView`, et
/// laisser là de la logique de données rendait le fichier illisible.
///
/// Comportement **inchangé**, y compris les subtilités qui étaient documentées
/// sur place : l'identité d'une occurrence est le couple (identifiant, date de
/// début), la déduplication se fait par email puis par nom, et la sauvegarde
/// précède la programmation de la notification pour que `storeIdentifier`
/// reste stable.
@MainActor
enum MeetingCalendarSync {

    /// Applique un événement choisi dans le sélecteur à une réunion.
    static func apply(event: CalendarMeetingEvent,
                      to meeting: Meeting,
                      knownCollaborators: [Collaborator],
                      in context: ModelContext) {
        meeting.title = event.title
        meeting.date = event.startDate
        meeting.calendarEventID = event.id
        // Identité d'une occurrence = (identifiant, date de début) : sans
        // `scheduledStart`, le parcours Teams ne retrouverait pas cette réunion
        // et en créerait un doublon (cf. CalendarMeetingImportService.findExisting).
        meeting.scheduledStart = event.startDate
        meeting.scheduledEnd = event.endDate
        meeting.calendarEventTitle = event.title
        meeting.meetingDurationSeconds = max(
            0, Int(event.endDate.timeIntervalSince(event.startDate).rounded()))

        for attendee in event.attendees {
            let collaborator = resolve(attendee: attendee,
                                       among: knownCollaborators,
                                       in: context)
            if !meeting.participants.contains(where: {
                $0.persistentModelID == collaborator.persistentModelID
            }) {
                meeting.participants.append(collaborator)
            }
            meeting.setParticipantStatus(attendee.status, for: collaborator)
        }
    }

    /// Recharge titre, dates, lien Teams et participants depuis l'événement
    /// calendrier correspondant à `meeting.calendarEventID`, puis sauvegarde et
    /// reprogramme la notification. Sans correspondance, ne fait rien.
    ///
    /// Logique partagée (DRY) entre le bouton Resync de `MeetingDetailsBlock`
    /// et celui de `ManageParticipantsSheet` — les deux passent par ici.
    static func resync(meeting: Meeting,
                       settings: AppSettings,
                       in context: ModelContext) {
        let eventID = meeting.calendarEventID
        guard !eventID.isEmpty else { return }
        let importer = CalendarMeetingImportService()
        let now = Date()
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let end = cal.date(byAdding: .day, value: 60, to: now) ?? now
        let events = importer.fetchEvents(start: start, end: end)
        guard let match = events.first(where: { $0.id == eventID }) else { return }

        meeting.title = match.title
        meeting.scheduledStart = match.startDate
        meeting.scheduledEnd = match.endDate
        meeting.teamsJoinURL = match.teamsJoinURL
        meeting.date = match.startDate
        if !match.title.isEmpty { meeting.calendarEventTitle = match.title }
        meeting.meetingDurationSeconds = max(
            0, Int(match.endDate.timeIntervalSince(match.startDate).rounded()))

        // Ré-import des participants manquants (dédup par email puis par nom).
        let me = settings.userEmail.lowercased()
        let allCollabs = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
        for attendee in match.attendees {
            let email = (attendee.email ?? "").lowercased()
            if !me.isEmpty && email == me { continue }
            let name = attendee.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let collab: Collaborator
            if !email.isEmpty,
               let m = allCollabs.first(where: { $0.email.lowercased() == email }) {
                collab = m
            } else if !name.isEmpty,
                      let m = allCollabs.first(where: {
                          $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                      }) {
                collab = m
            } else {
                let c = Collaborator(name: name.isEmpty ? "Participant" : name)
                c.email = attendee.email ?? ""
                context.insert(c)
                collab = c
            }
            if !meeting.participants.contains(where: {
                $0.persistentModelID == collab.persistentModelID
            }) {
                meeting.participants.append(collab)
            }
            meeting.setParticipantStatus(attendee.status, for: collab)
        }

        // Sauvegarde **avant** la programmation, pour que `storeIdentifier`
        // reste stable.
        try? context.save()
        MeetingNotificationService.shared.schedule(for: meeting, settings: settings)
    }

    /// Le collaborateur correspondant à un participant d'événement, créé en
    /// ad hoc s'il est inconnu. La comparaison ignore casse et diacritiques :
    /// « Cédric » et « cedric » sont la même personne.
    static func resolve(attendee: CalendarMeetingAttendee,
                        among knownCollaborators: [Collaborator],
                        in context: ModelContext) -> Collaborator {
        let normalizedName = attendee.name.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if let existing = knownCollaborators.first(where: {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                            locale: .current) == normalizedName
        }) {
            // Compléter l'email s'il était vide.
            if existing.email.isEmpty, let email = attendee.email, !email.isEmpty {
                existing.email = email
            }
            return existing
        }

        let collaborator = Collaborator(name: attendee.name, role: "Calendrier")
        collaborator.email = attendee.email ?? ""
        collaborator.isAdhoc = true
        collaborator.pinLevel = 0
        context.insert(collaborator)
        return collaborator
    }
}
