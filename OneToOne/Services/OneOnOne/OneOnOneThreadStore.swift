import Foundation
import SwiftData
import os

private let threadLog = Logger(subsystem: "com.onetoone.app", category: "oneonone")

/// Le magasin du fil des tête-à-tête : **le seul service du domaine 1:1 qui
/// écrit en base**. Tout le reste (`CommitmentLedger`, `AgendaCarryover`,
/// `MoodTrend`, `RecurringTopicsBuilder`, `ReminderRules`,
/// `OneOnOneRecapBuilder`) est pur et se contente de lire ce qu'il reçoit.
///
/// Le fil est créé **paresseusement**, au premier tête-à-tête d'une personne
/// (D3) : créer un fil par fiche de l'annuaire remplirait la base de 372 fils
/// vides, dont ceux des personnes rencontrées une fois dans un import
/// calendrier.
///
/// Les réunions du fil ne sont **pas** une relation persistée : elles se
/// déduisent de `Meeting.participants` et du `kind`. Une relation de plus
/// serait un second endroit à tenir en phase avec les participants, et c'est
/// exactement le genre de doublon qui se désynchronise.
@MainActor
enum OneOnOneThreadStore {

    /// Les types de réunion où l'on se parle en face. Même définition que
    /// `OneToOneRhythm.faceToFace` et `EngagementLedger.faceToFace` : une
    /// réunion projet n'est pas un tête-à-tête.
    static let faceToFace: Set<MeetingKind> = [.oneToOne, .manager]

    // MARK: - Rôle (D4)

    /// Le rôle que **j'endosse** dans une réunion de ce type.
    ///
    /// `nil` hors tête-à-tête : il n'y a alors pas de fil, et rendre `.manager`
    /// par défaut ferait naître un fil au premier comité.
    static func role(for kind: MeetingKind) -> OneOnOneSide? {
        switch kind {
        case .oneToOne: return .manager
        case .manager:  return .collaborator
        case .global, .project, .work, .note, .workshop: return nil
        }
    }

    /// L'inverse de `role(for:)` : le type de réunion d'un fil.
    static func meetingKind(for role: OneOnOneSide) -> MeetingKind {
        switch role {
        case .manager:      return .oneToOne
        case .collaborator: return .manager
        }
    }

    /// Cadence convenue, en jours. `0` = aucun rythme convenu, et alors rien
    /// n'est jamais en retard (même règle que `OneToOneCadence.periodInDays`).
    static func cadenceDays(for collaborator: Collaborator) -> Int {
        collaborator.oneToOneCadence.periodInDays ?? 0
    }

    // MARK: - Création paresseuse

    /// Le fil de `collaborator` pour le rôle qu'implique `kind`, créé s'il
    /// n'existe pas encore.
    ///
    /// Deux fils peuvent coexister pour la même personne : celui où je la
    /// manage (`.oneToOne`) et celui où elle me manage (`.manager`). Ce n'est
    /// pas un cas d'école — c'est la situation d'un manager intermédiaire.
    ///
    /// La cadence est **remise en phase** avec l'annuaire à chaque appel : le
    /// fil en garde un miroir requêtable, la fiche reste la source de vérité.
    ///
    /// - Returns: le fil, ou `nil` si `kind` n'est pas un tête-à-tête.
    @discardableResult
    static func thread(for collaborator: Collaborator,
                       kind: MeetingKind,
                       in context: ModelContext) -> OneOnOneThread? {
        guard let role = role(for: kind) else { return nil }
        let cadence = cadenceDays(for: collaborator)

        if let existant = existingThread(for: collaborator, role: role, in: context) {
            if existant.cadenceDays != cadence {
                existant.cadenceDays = cadence
                try? context.save()
            }
            return existant
        }

        let fil = OneOnOneThread(collaborator: collaborator, myRole: role, cadenceDays: cadence)
        context.insert(fil)
        fil.collaborator = collaborator
        try? context.save()
        threadLog.info("fil créé: role=\(role.rawValue, privacy: .public) cadence=\(cadence)")
        return fil
    }

    /// Le fil auquel appartient une réunion de tête-à-tête.
    ///
    /// La personne du fil est le **premier participant** de la réunion : un
    /// tête-à-tête n'en a qu'un, et un import calendrier qui en aurait ajouté
    /// deux ne doit pas empêcher d'ouvrir le fil.
    ///
    /// - Returns: `nil` si la réunion n'est pas un tête-à-tête ou n'a aucun
    ///   participant — il n'y a alors personne avec qui tenir un fil.
    @discardableResult
    static func thread(for meeting: Meeting, in context: ModelContext) -> OneOnOneThread? {
        guard faceToFace.contains(meeting.kind),
              let personne = meeting.participants.first else { return nil }
        return thread(for: personne, kind: meeting.kind, in: context)
    }

    /// Le fil déjà en base, sans en créer. Sert aux lectures d'écran, qui ne
    /// doivent pas écrire.
    static func existingThread(for collaborator: Collaborator,
                               role: OneOnOneSide,
                               in context: ModelContext) -> OneOnOneThread? {
        let cible = collaborator.persistentModelID
        let brut = role.rawValue
        let tous = (try? context.fetch(
            FetchDescriptor<OneOnOneThread>(predicate: #Predicate { $0.myRoleRaw == brut })
        )) ?? []
        return tous.first { $0.collaborator?.persistentModelID == cible }
    }

    // MARK: - Réunions du fil

    /// Les réunions du fil **tenues** à `now`, par date croissante.
    ///
    /// Filtre sur le type qui correspond au rôle du fil, et pas seulement sur
    /// `faceToFace` : mes 1:1 avec mon manager n'ont rien à faire dans le fil
    /// des 1:1 que je mène avec la même personne.
    static func meetings(of thread: OneOnOneThread, now: Date) -> [Meeting] {
        guard let collaborateur = thread.collaborator else { return [] }
        let attendu = meetingKind(for: thread.myRole)
        return collaborateur.meetings
            .filter { $0.kind == attendu && $0.date <= now }
            .sorted { $0.date < $1.date }
    }

    /// Toutes les réunions du fil, y compris celles à venir (pour le rang de
    /// séance et l'historique).
    static func allMeetings(of thread: OneOnOneThread) -> [Meeting] {
        guard let collaborateur = thread.collaborator else { return [] }
        let attendu = meetingKind(for: thread.myRole)
        return collaborateur.meetings
            .filter { $0.kind == attendu }
            .sorted { $0.date < $1.date }
    }

    /// La séance qui précède immédiatement `meeting` dans le fil.
    static func previousMeeting(before meeting: Meeting, in thread: OneOnOneThread) -> Meeting? {
        allMeetings(of: thread)
            .filter { $0.date < meeting.date }
            .last
    }

    /// La séance qui suit immédiatement `meeting` dans le fil — la cible d'un
    /// report d'ordre du jour.
    static func nextMeeting(after meeting: Meeting, in thread: OneOnOneThread) -> Meeting? {
        allMeetings(of: thread)
            .first { $0.date > meeting.date }
    }

    /// Rang de la séance dans le fil, à partir de 1 (« 14ᵉ 1:1 », capture 2b).
    /// `0` si la réunion n'appartient pas au fil.
    static func sessionNumber(of meeting: Meeting, in thread: OneOnOneThread) -> Int {
        let toutes = allMeetings(of: thread)
        guard let index = toutes.firstIndex(where: { $0.persistentModelID == meeting.persistentModelID })
        else { return 0 }
        return index + 1
    }

    // MARK: - Dates

    /// Date du dernier tête-à-tête tenu du fil.
    static func lastMeetingDate(of thread: OneOnOneThread, now: Date) -> Date? {
        meetings(of: thread, now: now).last?.date
    }

    /// Date proposée pour le prochain entretien : le dernier tenu, plus la
    /// cadence convenue.
    ///
    /// `nil` sans cadence **ou** sans séance tenue : dans les deux cas il n'y a
    /// pas de rythme à prolonger, il y en a un à commencer, et proposer une
    /// date au hasard serait une invention.
    static func nextPlannedDate(of thread: OneOnOneThread, now: Date) -> Date? {
        guard thread.cadenceDays > 0,
              let dernier = lastMeetingDate(of: thread, now: now) else { return nil }
        return dernier.addingTimeInterval(Double(thread.cadenceDays) * 86_400)
    }

    /// Prénom de la personne du fil, tel que les titres de colonnes l'affichent
    /// (`<Prénom> · n`, `Envoyer le récap à Laurent`).
    static func firstName(of thread: OneOnOneThread) -> String {
        let nom = thread.collaborator?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return nom.split(separator: " ").first.map(String.init) ?? nom
    }
}
