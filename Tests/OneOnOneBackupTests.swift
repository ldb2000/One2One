import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Point 6 des points durs du programme (§2.4) : « `StorageStatsService`,
/// `OrphanCleanupService`, `BackupService` ne connaissent que les emplacements
/// existants : **chaque nouveau dossier de fichiers s'y enregistre** ». Et
/// chaque nouvelle table.
///
/// `SchemaV3` (lot 0B) en a ajouté neuf. Une seule, `Board`, était exportée —
/// le lot 16 l'avait faite en même temps que son dossier `boards/`. Les huit
/// autres sortaient d'une sauvegarde silencieusement vides : un fil 1:1
/// entier, ses engagements, son ordre du jour, ses humeurs, ses objectifs, les
/// notes horodatées de chaque réunion, les jalons et les interlocuteurs de
/// chaque projet.
@Suite("Sauvegarde : notes horodatées, fiche projet, domaine 1:1")
@MainActor
struct OneOnOneBackupTests {

    private func contexte() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func reunion(_ titre: String) -> Meeting {
        Meeting(title: titre,
                date: Date(timeIntervalSince1970: 1_788_523_200),
                notes: "")
    }

    @Test("une note horodatée fait l'aller-retour, confidentialité et citation comprises")
    func noteSurvit() throws {
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let seance = reunion("Comité de suivi")
        source.insert(seance)

        let note = MeetingNote(t: 252,
                               text: "Le partenaire décide seul du chiffrage",
                               kind: .decision,
                               visibility: .private,
                               orderIndex: 3)
        source.insert(note)
        note.meeting = seance
        note.sourceKindRaw = "transcript"
        note.sourceT = 250
        try source.save()

        let data = try BackupService().backup(settings: reglages, entities: [], projects: [],
                                              collaborators: [], meetings: [seance])

        // La note est dans le JSON, sous la réunion qui la porte.
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let reunions = try #require(json["meetings"] as? [[String: Any]])
        let notes = try #require(reunions.first?["timedNotes"] as? [[String: Any]])
        #expect(notes.count == 1)
        #expect((notes[0]["text"] as? String) == "Le partenaire décide seul du chiffrage")

        let cible = try contexte()
        try BackupService().restore(from: data, into: cible)

        let restaurees = try cible.fetch(FetchDescriptor<MeetingNote>())
        #expect(restaurees.count == 1)
        let restauree = try #require(restaurees.first)
        #expect(restauree.t == 252)
        #expect(restauree.kind == .decision)
        // La confidentialité par ligne est la raison d'être de la table (D1) :
        // la perdre à la restauration publierait une note privée.
        #expect(restauree.visibility == .private)
        #expect(restauree.orderIndex == 3)
        #expect(restauree.sourceKindRaw == "transcript")
        #expect(restauree.sourceT == 250)
        #expect(restauree.stableID == note.stableID)
        #expect(restauree.meeting?.title == "Comité de suivi")
    }

    @Test("jalons et interlocuteurs suivent leur projet")
    func ficheProjetSurvit() throws {
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let projet = Project(code: "P25_110", name: "Modernisation CI/CD",
                             domain: "Socle", phase: "Réalisation")
        source.insert(projet)

        let jalon = ProjectMilestone(label: "Fin de conception", order: 1)
        source.insert(jalon)
        jalon.project = projet
        jalon.dueAt = Date(timeIntervalSince1970: 1_790_000_000)
        jalon.state = .done

        let contact = ProjectContact(name: "Claire-Amélie F.", role: "Sponsor", order: 0)
        source.insert(contact)
        contact.project = projet
        try source.save()

        let data = try BackupService().backup(settings: reglages, entities: [],
                                              projects: [projet], collaborators: [],
                                              meetings: [])
        let cible = try contexte()
        try BackupService().restore(from: data, into: cible)

        let jalons = try cible.fetch(FetchDescriptor<ProjectMilestone>())
        #expect(jalons.count == 1)
        #expect(jalons.first?.label == "Fin de conception")
        #expect(jalons.first?.state == .done)
        #expect(jalons.first?.project?.code == "P25_110")

        let contacts = try cible.fetch(FetchDescriptor<ProjectContact>())
        #expect(contacts.first?.name == "Claire-Amélie F.")
        #expect(contacts.first?.role == "Sponsor")
        #expect(contacts.first?.project?.code == "P25_110")
    }

    @Test("un fil 1:1 emporte engagements, ordre du jour, humeurs et objectifs")
    func filSurvit() throws {
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let collaborateur = Collaborator(name: "Yann PENVEN")
        source.insert(collaborateur)
        let seance = reunion("1:1 — Yann · 14")
        source.insert(seance)

        let fil = OneOnOneThread(collaborator: collaborateur, myRole: .manager, cadenceDays: 14)
        source.insert(fil)

        let engagement = Commitment(text: "Chiffrer le reste à faire")
        source.insert(engagement)
        engagement.thread = fil
        engagement.visibility = .escalated
        engagement.deferralCount = 2
        engagement.blocksOther = true
        engagement.promisedInMeeting = seance

        let sujet = OneOnOneAgendaItem(text: "Charge de l'équipe")
        source.insert(sujet)
        sujet.thread = fil
        sujet.meeting = seance
        sujet.remindedCount = 1

        let humeur = MoodEntry(value: 4)
        source.insert(humeur)
        humeur.thread = fil
        humeur.meeting = seance

        let objectif = OneOnOneObjective(label: "Passer la certification", progress: 40)
        source.insert(objectif)
        objectif.thread = fil
        try source.save()

        let data = try BackupService().backup(settings: reglages, entities: [], projects: [],
                                              collaborators: [collaborateur],
                                              meetings: [seance])
        let cible = try contexte()
        try BackupService().restore(from: data, into: cible)

        let fils = try cible.fetch(FetchDescriptor<OneOnOneThread>())
        #expect(fils.count == 1)
        let restaure = try #require(fils.first)
        #expect(restaure.cadenceDays == 14)
        #expect(restaure.myRole == .manager)
        #expect(restaure.stableID == fil.stableID)
        #expect(restaure.collaborator?.name == "Yann PENVEN")

        #expect(restaure.commitments.count == 1)
        let engagementRestaure = try #require(restaure.commitments.first)
        #expect(engagementRestaure.text == "Chiffrer le reste à faire")
        #expect(engagementRestaure.visibility == .escalated)
        #expect(engagementRestaure.deferralCount == 2)
        #expect(engagementRestaure.blocksOther)
        // La réunion où l'engagement a été pris est recousue par `stableID` :
        // sans elle, « promis le … » perd sa source.
        #expect(engagementRestaure.promisedInMeeting?.title == "1:1 — Yann · 14")

        #expect(restaure.agendaItems.count == 1)
        #expect(restaure.agendaItems.first?.text == "Charge de l'équipe")
        #expect(restaure.agendaItems.first?.remindedCount == 1)
        #expect(restaure.agendaItems.first?.meeting?.title == "1:1 — Yann · 14")

        #expect(restaure.moodEntries.count == 1)
        #expect(restaure.moodEntries.first?.value == 4)
        #expect(restaure.moodEntries.first?.meeting?.title == "1:1 — Yann · 14")

        #expect(restaure.objectives.count == 1)
        #expect(restaure.objectives.first?.label == "Passer la certification")
        #expect(restaure.objectives.first?.progress == 40)
    }

    @Test("une sauvegarde antérieure au lot 19c, sans les nouvelles clés, se restaure")
    func backupAncienSeRestaure() throws {
        // Tous les champs ajoutés sont optionnels, comme `boards` au lot 16 :
        // une sauvegarde de la veille doit continuer de se relire. Le payload
        // « d'avant » est fabriqué en retirant les quatre clés d'un vrai
        // export — l'écrire à la main le rendrait faux au premier champ ajouté
        // ailleurs dans `SettingsDTO`.
        let source = try contexte()
        let reglages = AppSettings()
        source.insert(reglages)
        let projet = Project(code: "P25_110", name: "Modernisation CI/CD",
                             domain: "Socle", phase: "Réalisation")
        source.insert(projet)
        let collaborateur = Collaborator(name: "Yann PENVEN")
        source.insert(collaborateur)
        let seance = reunion("Comité de suivi")
        source.insert(seance)
        let note = MeetingNote(t: 10, text: "Une note qui ne doit pas survivre")
        source.insert(note)
        note.meeting = seance
        let fil = OneOnOneThread(collaborator: collaborateur)
        source.insert(fil)
        try source.save()

        let recent = try BackupService().backup(settings: reglages, entities: [],
                                                projects: [projet],
                                                collaborators: [collaborateur],
                                                meetings: [seance])
        var json = try #require(try JSONSerialization.jsonObject(with: recent)
                                as? [String: Any])
        json["meetings"] = (json["meetings"] as? [[String: Any]] ?? []).map {
            var reunion = $0; reunion.removeValue(forKey: "timedNotes"); return reunion
        }
        json["projects"] = (json["projects"] as? [[String: Any]] ?? []).map {
            var p = $0
            p.removeValue(forKey: "milestones")
            p.removeValue(forKey: "contacts")
            return p
        }
        json["collaborators"] = (json["collaborators"] as? [[String: Any]] ?? []).map {
            var c = $0; c.removeValue(forKey: "threads"); return c
        }
        let ancien = try JSONSerialization.data(withJSONObject: json)

        let cible = try contexte()
        try BackupService().restore(from: ancien, into: cible)

        // Le reste est bien là ; les tables du lot 19c, absentes du fichier,
        // restent vides — sans que le décodage échoue.
        #expect(try cible.fetch(FetchDescriptor<Meeting>()).count == 1)
        #expect(try cible.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try cible.fetch(FetchDescriptor<MeetingNote>()).isEmpty)
        #expect(try cible.fetch(FetchDescriptor<OneOnOneThread>()).isEmpty)
        #expect(try cible.fetch(FetchDescriptor<ProjectMilestone>()).isEmpty)
    }

    @Test("les neuf tables du lot 0B sont toutes exportées")
    func aucuneTableOubliee() {
        // Le garde-fou de la prochaine table : un DTO par modèle de SchemaV3.
        let source = RefonteSource.lire("OneToOne/Services/BackupService.swift")
        for dto in ["MeetingNoteDTO", "BoardDTO", "ProjectMilestoneDTO", "ProjectContactDTO",
                    "OneOnOneThreadDTO", "CommitmentDTO", "OneOnOneAgendaItemDTO",
                    "MoodEntryDTO", "OneOnOneObjectiveDTO"] {
            #expect(source.contains("struct \(dto)"), "DTO manquant : \(dto)")
        }
    }
}
