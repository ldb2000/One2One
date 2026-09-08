import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le fil est créé **paresseusement** au premier tête-à-tête d'une personne
/// (D3) et son rôle se déduit du type de réunion (D4). Cette suite garde les
/// deux règles, plus le calcul de la prochaine date, qui décide de ce que
/// « Planifier le prochain — 18 sept. » affiche à la clôture.
@Suite("Fil 1:1 — création paresseuse, rôle par type et dates (D3, D4)")
@MainActor
struct OneOnOneThreadStoreTests {

    private static let jour: TimeInterval = 86_400
    /// 4 septembre 2026, 9:15 à Paris — la date des captures 2a / 5a.
    private static let quatreSeptembre = Date(timeIntervalSince1970: 1_788_506_100)
    private static let vingtEtUnAout = quatreSeptembre.addingTimeInterval(-14 * jour)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @discardableResult
    private func reunion(_ context: ModelContext,
                         kind: MeetingKind,
                         date: Date,
                         avec collaborateur: Collaborator,
                         titre: String = "1:1") -> Meeting {
        let reunion = Meeting(title: titre, date: date, notes: "")
        reunion.kind = kind
        context.insert(reunion)
        reunion.participants.append(collaborateur)
        return reunion
    }

    // MARK: - Rôle

    @Test("Le rôle se déduit du type de réunion")
    func roleParType() {
        #expect(OneOnOneThreadStore.role(for: .oneToOne) == .manager)
        #expect(OneOnOneThreadStore.role(for: .manager) == .collaborator)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(OneOnOneThreadStore.role(for: kind) == nil)
        }
    }

    @Test("Le type de réunion se déduit du rôle, sans ambiguïté")
    func typeParRole() {
        #expect(OneOnOneThreadStore.meetingKind(for: .manager) == .oneToOne)
        #expect(OneOnOneThreadStore.meetingKind(for: .collaborator) == .manager)
    }

    // MARK: - Création paresseuse

    @Test("Créer le fil deux fois rend le même fil")
    func creationIdempotente() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        context.insert(laurent)

        let premier = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        let second = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))

        #expect(premier.persistentModelID == second.persistentModelID)
        #expect(try context.fetch(FetchDescriptor<OneOnOneThread>()).count == 1)
        #expect(premier.myRole == .manager)
        #expect(premier.collaborator?.name == "Laurent NOMINÉ")
    }

    @Test("Les deux rôles d'une même personne sont deux fils distincts")
    func deuxRolesDeuxFils() throws {
        let context = try makeContext()
        let personne = Collaborator(name: "Yann PENVEN", role: "Manager")
        context.insert(personne)

        let mene = try #require(OneOnOneThreadStore.thread(for: personne, kind: .oneToOne, in: context))
        let subi = try #require(OneOnOneThreadStore.thread(for: personne, kind: .manager, in: context))

        #expect(mene.persistentModelID != subi.persistentModelID)
        #expect(mene.myRole == .manager)
        #expect(subi.myRole == .collaborator)
        #expect(try context.fetch(FetchDescriptor<OneOnOneThread>()).count == 2)
    }

    @Test("Aucun fil pour une réunion qui n'est pas un tête-à-tête")
    func pasDeFilHorsFaceAFace() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Camille Aubert")
        context.insert(collab)

        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(OneOnOneThreadStore.thread(for: collab, kind: kind, in: context) == nil)
        }
        #expect(try context.fetch(FetchDescriptor<OneOnOneThread>()).isEmpty)
    }

    @Test("Le fil d'une réunion se trouve par son premier participant")
    func filDepuisLaReunion() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        context.insert(laurent)
        let seance = reunion(context, kind: .oneToOne, date: Self.quatreSeptembre, avec: laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))
        #expect(fil.collaborator?.name == "Laurent NOMINÉ")
        #expect(fil.myRole == .manager)
    }

    @Test("Une réunion 1:1 sans participant n'ouvre pas de fil")
    func reunionSansParticipant() throws {
        let context = try makeContext()
        let seance = Meeting(title: "1:1 sans personne", date: Self.quatreSeptembre, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)

        #expect(OneOnOneThreadStore.thread(for: seance, in: context) == nil)
    }

    // MARK: - Cadence

    @Test("La cadence du fil suit l'annuaire")
    func cadenceMiroir() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        laurent.oneToOneCadence = .bimensuelle
        context.insert(laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(fil.cadenceDays == 14)

        // L'annuaire reste la source de vérité : un changement de rythme se
        // reflète au prochain accès, sans qu'il faille toucher le fil.
        laurent.oneToOneCadence = .mensuelle
        let remis = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(remis.cadenceDays == 30)
    }

    @Test("Sans rythme convenu, la cadence du fil est nulle")
    func sansCadence() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Lucas Sylvain")
        context.insert(collab)

        let fil = try #require(OneOnOneThreadStore.thread(for: collab, kind: .oneToOne, in: context))
        #expect(fil.cadenceDays == 0)
        #expect(OneOnOneThreadStore.nextPlannedDate(of: fil, now: Self.quatreSeptembre) == nil)
    }

    // MARK: - Réunions du fil

    @Test("Le fil ne compte que les réunions de son propre côté")
    func reunionsDuBonCote() throws {
        let context = try makeContext()
        let personne = Collaborator(name: "Yann PENVEN")
        context.insert(personne)
        reunion(context, kind: .oneToOne, date: Self.vingtEtUnAout, avec: personne)
        reunion(context, kind: .manager, date: Self.quatreSeptembre, avec: personne)
        reunion(context, kind: .project, date: Self.quatreSeptembre, avec: personne)

        let mene = try #require(OneOnOneThreadStore.thread(for: personne, kind: .oneToOne, in: context))
        let subi = try #require(OneOnOneThreadStore.thread(for: personne, kind: .manager, in: context))

        let menees = OneOnOneThreadStore.meetings(of: mene, now: Self.quatreSeptembre)
        let subies = OneOnOneThreadStore.meetings(of: subi, now: Self.quatreSeptembre)
        #expect(menees.count == 1)
        #expect(menees.first?.date == Self.vingtEtUnAout)
        #expect(subies.count == 1)
        #expect(subies.first?.date == Self.quatreSeptembre)
    }

    @Test("Les réunions à venir ne comptent pas encore")
    func reunionsFutures() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        context.insert(laurent)
        reunion(context, kind: .oneToOne, date: Self.vingtEtUnAout, avec: laurent)
        reunion(context, kind: .oneToOne,
                date: Self.quatreSeptembre.addingTimeInterval(14 * Self.jour), avec: laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(OneOnOneThreadStore.meetings(of: fil, now: Self.quatreSeptembre).count == 1)
    }

    @Test("La séance précédente est la dernière antérieure du fil")
    func seancePrecedente() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        context.insert(laurent)
        let juillet = reunion(context, kind: .oneToOne,
                              date: Self.vingtEtUnAout.addingTimeInterval(-28 * Self.jour),
                              avec: laurent)
        let aout = reunion(context, kind: .oneToOne, date: Self.vingtEtUnAout, avec: laurent)
        let septembre = reunion(context, kind: .oneToOne, date: Self.quatreSeptembre, avec: laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(OneOnOneThreadStore.previousMeeting(before: septembre, in: fil)?.date == aout.date)
        #expect(OneOnOneThreadStore.previousMeeting(before: aout, in: fil)?.date == juillet.date)
        #expect(OneOnOneThreadStore.previousMeeting(before: juillet, in: fil) == nil)
    }

    @Test("Le rang de la séance se compte depuis la première du fil")
    func rangDeLaSeance() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        context.insert(laurent)
        var seances: [Meeting] = []
        for index in 0..<3 {
            seances.append(reunion(context, kind: .oneToOne,
                                   date: Self.quatreSeptembre.addingTimeInterval(Double(index - 2) * 14 * Self.jour),
                                   avec: laurent))
        }

        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(OneOnOneThreadStore.sessionNumber(of: seances[0], in: fil) == 1)
        #expect(OneOnOneThreadStore.sessionNumber(of: seances[2], in: fil) == 3)
    }

    // MARK: - Prochaine date

    @Test("La prochaine date est le dernier tête-à-tête plus la cadence")
    func prochaineDate() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        laurent.oneToOneCadence = .bimensuelle
        context.insert(laurent)
        reunion(context, kind: .oneToOne, date: Self.vingtEtUnAout, avec: laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(OneOnOneThreadStore.lastMeetingDate(of: fil, now: Self.quatreSeptembre) == Self.vingtEtUnAout)
        // 21 août + 14 jours = 4 septembre.
        #expect(OneOnOneThreadStore.nextPlannedDate(of: fil, now: Self.quatreSeptembre) == Self.quatreSeptembre)
    }

    @Test("Sans tête-à-tête tenu, il n'y a pas de prochaine date")
    func sansSeanceTenue() throws {
        let context = try makeContext()
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        laurent.oneToOneCadence = .hebdomadaire
        context.insert(laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        #expect(OneOnOneThreadStore.nextPlannedDate(of: fil, now: Self.quatreSeptembre) == nil)
    }
}
