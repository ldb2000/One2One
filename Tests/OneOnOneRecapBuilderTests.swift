import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le récap de clôture (spec §3.3 `CLÔTURER`, §6.2 `EN SORTANT`, D9).
///
/// Tout passe par `ConfidentialityFilter` : c'est la sixième sortie de texte de
/// l'application, et la seule règle est celle de la spec §8 (« une seule
/// fonction `isExportable(item, audience)` traverse rapport, export, récap 1:1
/// et assistant. Aucune vue ne réimplémente la règle »).
@Suite("Récap 1:1 — markdown filtré et sorties (spec §3.3, §6.2, D9)")
@MainActor
struct OneOnOneRecapBuilderTests {

    private static let jour: TimeInterval = 86_400
    private static let quatreSeptembre = Date(timeIntervalSince1970: 1_788_506_100)

    // Trois textes sans caractère échappable, pour que l'absence d'une chaîne
    // dise quelque chose sur la confidentialité et pas sur l'échappement.
    private static let textePrive = "Risque de depart si la mobilite n avance pas"
    private static let texteEscalade = "Situation a signaler aux RH"
    private static let textePartage = "Charge AP : 3 j-h de reprise non prevus"

    private struct Jeu {
        var fil: OneOnOneThread
        var seance: Meeting
        var context: ModelContext
        var collaborateur: Collaborator
    }

    private func makeJeu(role: OneOnOneSide = .manager) throws -> Jeu {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let laurent = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        laurent.oneToOneCadence = .bimensuelle
        laurent.email = "laurent.nomine@example.com"
        context.insert(laurent)

        let kind = OneOnOneThreadStore.meetingKind(for: role)
        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: kind, in: context))

        let seance = Meeting(title: "1:1 Laurent", date: Self.quatreSeptembre, notes: "")
        seance.kind = kind
        context.insert(seance)
        seance.participants.append(laurent)

        for (texte, visibilite, nature) in [
            (Self.textePartage, Visibility.shared, MeetingNoteKind.note),
            (Self.textePrive, Visibility.private, MeetingNoteKind.note),
            (Self.texteEscalade, Visibility.escalated, MeetingNoteKind.note)
        ] {
            let note = MeetingNote(t: 375, text: texte, kind: nature, visibility: visibilite)
            context.insert(note)
            note.meeting = seance
        }

        try context.save()
        return Jeu(fil: fil, seance: seance, context: context, collaborateur: laurent)
    }

    // MARK: - Critère chantier 2 n° 1

    @Test("Le récap collaborateur ne contient aucune note privée")
    func recapCollaborateurSansPrive() throws {
        let jeu = try makeJeu()
        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .collaborator,
                                                   now: Self.quatreSeptembre)
        #expect(recap.contains(Self.textePartage))
        #expect(!recap.contains(Self.textePrive))
    }

    @Test("Le récap collaborateur exclut aussi les lignes escaladées")
    func recapCollaborateurSansEscalade() throws {
        // D9 : « exclu du récap collaborateur, inclus dans un export
        // "Escalade" explicite ».
        let jeu = try makeJeu()
        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .collaborator,
                                                   now: Self.quatreSeptembre)
        #expect(!recap.contains(Self.texteEscalade))
    }

    @Test("L'export RH contient les lignes escaladées et pas les lignes partagées seules")
    func exportRH() throws {
        let jeu = try makeJeu()
        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .hr, now: Self.quatreSeptembre)
        #expect(recap.contains(Self.texteEscalade))
        #expect(!recap.contains(Self.textePartage))
        #expect(!recap.contains(Self.textePrive))
    }

    @Test("Mon propre récap contient tout, y compris le privé")
    func recapPourMoi() throws {
        let jeu = try makeJeu()
        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .me, now: Self.quatreSeptembre)
        #expect(recap.contains(Self.textePrive))
        #expect(recap.contains(Self.textePartage))
        #expect(recap.contains(Self.texteEscalade))
    }

    // MARK: - Pied et exclusions

    @Test("Le pied annonce le nombre de lignes exclues")
    func piedDesExclusions() throws {
        let jeu = try makeJeu()
        #expect(OneOnOneRecapBuilder.excludedLinesCount(for: jeu.seance, thread: jeu.fil,
                                                         audience: .collaborator) == 2)
        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .collaborator,
                                                   now: Self.quatreSeptembre)
        #expect(recap.contains("2 lignes ont été exclues de ce récap."))

        // Rien d'exclu pour moi : pas de mention.
        let mien = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                  audience: .me, now: Self.quatreSeptembre)
        #expect(!mien.contains("exclue"))
    }

    // MARK: - Engagements

    @Test("Les engagements sont groupés par côté, cochés selon leur état")
    func engagementsParCote() throws {
        let jeu = try makeJeu()
        let mien = Commitment(text: "Arbitrer renfort ou decalage du Webcast",
                              ownerSide: .manager,
                              dueAt: Self.quatreSeptembre.addingTimeInterval(2 * Self.jour),
                              promisedAt: Self.quatreSeptembre)
        let sien = Commitment(text: "Reprise du perimetre Nexus",
                              ownerSide: .collaborator, state: .kept,
                              promisedAt: Self.quatreSeptembre)
        let prive = Commitment(text: "Ouvrir le sujet mobilite avec Claire-Amelie",
                               ownerSide: .manager, promisedAt: Self.quatreSeptembre,
                               visibility: .private)
        for engagement in [mien, sien, prive] {
            jeu.context.insert(engagement)
            engagement.thread = jeu.fil
        }

        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .collaborator,
                                                   now: Self.quatreSeptembre)
        #expect(recap.contains("### Moi"))
        #expect(recap.contains("### Laurent"))
        #expect(recap.contains("- [ ] Arbitrer renfort ou decalage du Webcast"))
        #expect(recap.contains("- [x] Reprise du perimetre Nexus"))
        // Un engagement privé n'est pas un engagement partagé.
        #expect(!recap.contains("Ouvrir le sujet mobilite"))
    }

    // MARK: - Sujets

    @Test("Les sujets partagés de l'ordre du jour entrent dans le récap")
    func sujetsDuRecap() throws {
        let jeu = try makeJeu()
        let partage = OneOnOneAgendaItem(text: "Formation Admin a porter", visibility: .shared)
        let prive = OneOnOneAgendaItem(text: "Point salaire a preparer", visibility: .private)
        for item in [partage, prive] {
            jeu.context.insert(item)
            item.thread = jeu.fil
            item.meeting = jeu.seance
        }

        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .collaborator,
                                                   now: Self.quatreSeptembre)
        #expect(recap.contains("Formation Admin a porter"))
        #expect(!recap.contains("Point salaire"))
    }

    // MARK: - Humeur

    @Test("L'humeur n'apparaît pas dans un export RH")
    func humeurHorsRH() throws {
        let jeu = try makeJeu()
        MoodTrend.record(2, for: jeu.seance, in: jeu.fil, in: jeu.context)

        let versCollab = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                        audience: .collaborator,
                                                        now: Self.quatreSeptembre)
        #expect(versCollab.contains("Sous tension"))

        // Le cran de moral appartient à la personne : il ne monte pas aux RH
        // au détour d'une escalade.
        let versRH = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                    audience: .hr, now: Self.quatreSeptembre)
        #expect(!versRH.contains("Sous tension"))
    }

    // MARK: - Feedback

    @Test("Le feedback partagé est rendu dans les deux sens")
    func feedbackDansLesDeuxSens() throws {
        let jeu = try makeJeu()
        let donne = MeetingNote(t: 400, text: "Presentation COSUI tres claire",
                                kind: .feedback, visibility: .shared, authorSide: .me)
        let recu = MeetingNote(t: 420, text: "Les arbitrages budget arrivent trop tard",
                               kind: .feedback, visibility: .shared, authorSide: .collaborator)
        for note in [donne, recu] {
            jeu.context.insert(note)
            note.meeting = jeu.seance
        }

        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .collaborator,
                                                   now: Self.quatreSeptembre)
        #expect(recap.contains("## Feedback"))
        #expect(recap.contains("Presentation COSUI tres claire"))
        #expect(recap.contains("Les arbitrages budget arrivent trop tard"))
    }

    // MARK: - Titres et chemins

    @Test("Le sujet du récap nomme la personne et la date")
    func sujetDuRecap() throws {
        let jeu = try makeJeu()
        #expect(OneOnOneRecapBuilder.subject(for: jeu.seance, thread: jeu.fil)
                == "Récap 1:1 — Laurent NOMINÉ — 4 sept. 2026")
    }

    @Test("Le titre du prochain entretien est « 1:1 — <Prénom> »")
    func titreDuProchain() throws {
        let jeu = try makeJeu()
        #expect(OneOnOneRecapBuilder.nextMeetingTitle(for: jeu.fil) == "1:1 — Laurent")
    }

    @Test("Le chemin du dossier annuel porte l'année et le nom du collaborateur")
    func cheminDuDossierAnnuel() throws {
        let jeu = try makeJeu()
        let url = OneOnOneRecapBuilder.annualFolderURL(for: jeu.fil, date: Self.quatreSeptembre)
        #expect(url.pathComponents.suffix(4) == ["recordings", "annual", "2026", "Laurent NOMINÉ"])
    }

    @Test("Un nom de collaborateur à barre oblique ne casse pas le chemin")
    func nomAssaini() throws {
        let jeu = try makeJeu()
        jeu.collaborateur.name = "Jean/Marc : Durand"
        let url = OneOnOneRecapBuilder.annualFolderURL(for: jeu.fil, date: Self.quatreSeptembre)
        #expect(url.lastPathComponent == "Jean-Marc - Durand")
    }

    @Test("Le nom de fichier est la date ISO du jour de l'entretien")
    func nomDeFichier() {
        #expect(OneOnOneRecapBuilder.annualFileName(for: Self.quatreSeptembre) == "2026-09-04.md")
    }

    @Test("Le récap au manager (côté collaborateur) part avec l'audience .manager")
    func recapCoteCollaborateur() throws {
        let jeu = try makeJeu(role: .collaborator)
        #expect(OneOnOneConfidentiality.recapAudience(for: jeu.fil.myRole) == .manager)
        let recap = OneOnOneRecapBuilder.markdown(for: jeu.seance, thread: jeu.fil,
                                                   audience: .manager,
                                                   now: Self.quatreSeptembre)
        #expect(recap.contains(Self.textePartage))
        #expect(!recap.contains(Self.textePrive))
        // Mon manager est aussi le destinataire de l'escalade.
        #expect(recap.contains(Self.texteEscalade))
    }

    // MARK: - Destinataires et prochaine date

    @Test("Le destinataire du récap est l'adresse de la personne du fil")
    func destinataire() throws {
        let jeu = try makeJeu()
        #expect(OneOnOneRecapBuilder.recipients(for: jeu.fil) == ["laurent.nomine@example.com"])

        jeu.collaborateur.email = "pas une adresse"
        #expect(OneOnOneRecapBuilder.recipients(for: jeu.fil).isEmpty)
    }

    @Test("Le dossier annuel écrit un fichier par entretien, écrasable")
    func versementIdempotent() throws {
        let jeu = try makeJeu()
        let racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-annual-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: racine) }

        let premier = try OneOnOneRecapActions.archiveToAnnualFolder(
            for: jeu.seance, thread: jeu.fil, now: Self.quatreSeptembre, root: racine)
        let second = try OneOnOneRecapActions.archiveToAnnualFolder(
            for: jeu.seance, thread: jeu.fil, now: Self.quatreSeptembre, root: racine)

        #expect(premier == second)
        #expect(FileManager.default.fileExists(atPath: premier.path))
        let contenu = try String(contentsOf: premier, encoding: .utf8)
        // Mon dossier annuel : audience `.me`, donc tout y est.
        #expect(contenu.contains(Self.textePrive))
    }
}
