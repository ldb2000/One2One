import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La nav latérale de 190 px et l'en-tête du poste de pilotage (spec §2.7,
/// capture `1c-poste-de-pilotage.png`).
///
/// « Plus d'onglet vide : chaque entrée porte son compteur » est un critère qui
/// ne se vérifie pas à l'œil — il se vérifie par **exhaustivité** : une entrée
/// ajoutée demain fait échouer cette suite tant qu'elle n'a pas dit ce qu'elle
/// contient. C'est la même garde que `MeetingEmptyInvite.Catalogue` au lot 1.
@Suite("Nav latérale et en-tête du poste de pilotage")
@MainActor
struct ReviewSidebarNavTests {

    private var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private var localeFr: Locale { Locale(identifier: "fr_FR") }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func date(_ jour: Int, _ mois: Int, _ annee: Int, heure: Int = 9, minute: Int = 15) -> Date {
        calendrier.date(from: DateComponents(year: annee, month: mois, day: jour,
                                             hour: heure, minute: minute)) ?? .now
    }

    // MARK: - Exhaustivité

    @Test("Chaque section du mode Relire a exactement une entrée")
    func exhaustive() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final")
        context.insert(reunion)

        let entrees = ReviewSidebarNav.entrees(for: reunion)
        #expect(entrees.count == ReviewState.Section.allCases.count)
        #expect(entrees.map(\.section) == ReviewState.Section.allCases)
    }

    @Test("Aucune entrée du rail n'est sans compteur ni état")
    func noEmptyEntry() throws {
        let context = try makeContext()
        // Une réunion **vide** : c'est le cas où un « onglet vide » serait le
        // plus tentant.
        let vide = Meeting(title: "Réunion neuve")
        context.insert(vide)
        for entree in ReviewSidebarNav.entrees(for: vide) {
            #expect(!entree.libelle.isEmpty)
            #expect(!entree.complement.texte.isEmpty)
        }

        // …et une réunion remplie.
        let pleine = Meeting(title: "[P25_110] Partage statut final")
        pleine.shortSummary = "Résumé."
        pleine.summary = "# Rapport"
        pleine.rawTranscript = "texte"
        pleine.durationSeconds = 1_404
        context.insert(pleine)
        for entree in ReviewSidebarNav.entrees(for: pleine) {
            #expect(!entree.complement.texte.isEmpty)
        }
    }

    // MARK: - Compteurs

    @Test("Les compteurs du rail sont ceux des données")
    func counters() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "[P25_110] Partage statut final", date: date(4, 9, 2026))
        reunion.durationSeconds = 1_404          // 23:24
        reunion.meetingDurationSeconds = 1_404
        reunion.rawTranscript = "texte"
        context.insert(reunion)

        for (index, t) in [252.0, 468.0, 663.0].enumerated() {
            let note = MeetingNote(t: t, text: "Note \(index)", orderIndex: index)
            context.insert(note)
            note.meeting = reunion
        }
        let porteur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(porteur)
        let assignee = ActionTask(title: "Chiffrer la fin Marine")
        assignee.collaborator = porteur
        let libre = ActionTask(title: "Clarifier la facturation")
        libre.destinataire = .collaborateur
        for tache in [assignee, libre] {
            context.insert(tache)
            tache.meeting = reunion
        }

        let parSection = Dictionary(uniqueKeysWithValues:
            ReviewSidebarNav.entrees(for: reunion).map { ($0.section, $0) })

        #expect(parSection[.notes]?.complement == .compte(3))
        #expect(parSection[.transcription]?.complement == .minutes(23))
        #expect(parSection[.actions]?.complement == .compte(2))
        // Une action sans porteur met le compteur en rouge — c'est le
        // `Actions 12` de la capture.
        #expect(parSection[.actions]?.alerte == true)
        #expect(parSection[.rapport]?.complement == .etat("—"))
        // Aucune pièce jointe : une invite, pas un `0`.
        #expect(parSection[.documents]?.complement == .invite)
        #expect(parSection[.synthese]?.complement == .etat("—"))
        #expect(parSection[.assistant]?.complement == .etat("⌘K"))
    }

    @Test("Toutes les actions assignées éteignent l'alerte")
    func noAlertWhenAllAssigned() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion")
        context.insert(reunion)
        let porteur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(porteur)
        let tache = ActionTask(title: "Chiffrer la fin Marine")
        tache.collaborator = porteur
        context.insert(tache)
        tache.meeting = reunion

        let actions = ReviewSidebarNav.entrees(for: reunion).first { $0.section == .actions }
        #expect(actions?.alerte == false)
        #expect(actions?.complement == .compte(1))
    }

    @Test("Un rapport généré met un ✓, une synthèse générée le dit")
    func reportAndSummaryStates() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion")
        reunion.summary = "# Compte-rendu"
        reunion.shortSummary = "Une phrase."
        context.insert(reunion)
        let parSection = Dictionary(uniqueKeysWithValues:
            ReviewSidebarNav.entrees(for: reunion).map { ($0.section, $0) })
        #expect(parSection[.rapport]?.complement == .etat("✓"))
        #expect(parSection[.synthese]?.complement == .etat("généré"))
    }

    // MARK: - Minutes

    @Test("La durée de séance l'emporte sur celle de l'enregistrement")
    func minutesPreferMeetingDuration() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion")
        reunion.durationSeconds = 1_200          // 20 min d'audio
        reunion.meetingDurationSeconds = 1_404   // 23 min de séance
        context.insert(reunion)
        #expect(ReviewSidebarNav.minutes(of: reunion) == 23)

        reunion.meetingDurationSeconds = 0
        #expect(ReviewSidebarNav.minutes(of: reunion) == 20)
    }

    // MARK: - Bloc projet

    @Test("Le bloc projet montre les trois dernières réunions antérieures du projet")
    func lastThreeMeetings() throws {
        let context = try makeContext()
        let projet = Project(code: "P25_110", name: "S/D — Modernisation CI/CD", domain: "S/D", phase: "Réalisation")
        let autre = Project(code: "P25_200", name: "Autre projet", domain: "S/D", phase: "Réalisation")
        context.insert(projet); context.insert(autre)

        let courante = Meeting(title: "[P25_110] Partage statut final", date: date(4, 9, 2026))
        courante.project = projet
        context.insert(courante)

        func reunion(_ titre: String, _ jour: Int, _ mois: Int, projet p: Project) -> Meeting {
            let m = Meeting(title: titre, date: date(jour, mois, 2026))
            m.project = p
            context.insert(m)
            return m
        }
        let cosui = reunion("COSUI hebdo", 1, 9, projet: projet)
        let gouvernance = reunion("Gouvernance", 31, 8, projet: projet)
        let situation = reunion("Situation AP", 26, 8, projet: projet)
        let vieille = reunion("Cadrage", 12, 8, projet: projet)
        let future = reunion("COPIL à venir", 11, 9, projet: projet)
        let horsProjet = reunion("Réunion d'un autre projet", 2, 9, projet: autre)

        let historique = [courante, cosui, gouvernance, situation, vieille, future, horsProjet]
        let dernieres = ReviewSidebarNav.dernieresDuProjet(courante, dans: historique)

        #expect(dernieres.map { $0.title } == ["COSUI hebdo", "Gouvernance", "Situation AP"])
        #expect(!dernieres.contains { $0.title == "COPIL à venir" })
        #expect(!dernieres.contains { $0.title == "Réunion d'un autre projet" })
        #expect(!dernieres.contains { $0.persistentModelID == courante.persistentModelID })
    }

    @Test("Une réunion hors projet n'a pas de fil")
    func noProjectNoThread() throws {
        let context = try makeContext()
        let seule = Meeting(title: "Point rapide", date: date(4, 9, 2026))
        context.insert(seule)
        #expect(ReviewSidebarNav.dernieresDuProjet(seule, dans: [seule]).isEmpty)
    }

    @Test("Une réunion du fil se nomme par sa date puis son sujet")
    func meetingLabel() throws {
        let context = try makeContext()
        let premier = Meeting(title: "COSUI hebdo", date: date(1, 9, 2026))
        let trenteEtUn = Meeting(title: "[P25_110] Gouvernance", date: date(31, 8, 2026))
        context.insert(premier); context.insert(trenteEtUn)

        #expect(ReviewSidebarNav.libelleReunion(premier, calendar: calendrier) == "1er sept. — COSUI hebdo")
        // La référence projet quitte le libellé : dans 190 px, elle mange le
        // sujet, et elle est déjà dans l'en-tête.
        #expect(ReviewSidebarNav.libelleReunion(trenteEtUn, calendar: calendrier) == "31 août — Gouvernance")
    }

    @Test("Le titre court retire le préfixe de référence, et lui seul")
    func shortTitle() {
        #expect(ReviewSidebarNav.titreCourt("[P25_110] Partage statut final")
                == "Partage statut final")
        #expect(ReviewSidebarNav.titreCourt("Gouvernance") == "Gouvernance")
        #expect(ReviewSidebarNav.titreCourt("[sans fermeture") == "[sans fermeture")
    }

    // MARK: - En-tête

    @Test("La ligne de métadonnées est celle de la capture 1c")
    func headerMetadata() throws {
        let context = try makeContext()
        let projet = Project(code: "P25_110", name: "S/D — Modernisation CI/CD", domain: "S/D", phase: "Réalisation")
        context.insert(projet)
        let reunion = Meeting(title: "[P25_110] Partage statut final et chiffrage reste à faire",
                              date: date(4, 9, 2026))
        reunion.kind = .project
        reunion.project = projet
        reunion.durationSeconds = 1_404
        reunion.meetingDurationSeconds = 1_404
        context.insert(reunion)
        for nom in ["Pierre-Yves Nallet", "Nathalie Lefèvre", "Cédric Payet",
                    "Lucas Sylvain", "Camille Aubert", "Laurent Deberti"] {
            let collaborateur = Collaborator(name: nom, role: "")
            context.insert(collaborateur)
            reunion.participants.append(collaborateur)
        }

        #expect(ReviewHeader.metadonnees(for: reunion, locale: localeFr, calendar: calendrier)
                == "P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants")
    }

    @Test("Sans projet ni participant, aucun point médian n'est orphelin")
    func headerMetadataWithoutProject() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Point rapide", date: date(4, 9, 2026))
        reunion.kind = .global
        context.insert(reunion)

        let ligne = ReviewHeader.metadonnees(for: reunion, locale: localeFr, calendar: calendrier)
        #expect(ligne == "Globale · 4 sept. 2026 · 9:15")
        #expect(!ligne.hasPrefix("·"))
        #expect(!ligne.hasSuffix("·"))
        #expect(!ligne.contains("· ·"))
    }

    @Test("Un participant unique reste au singulier")
    func singleParticipant() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Point", date: date(4, 9, 2026))
        context.insert(reunion)
        let collaborateur = Collaborator(name: "Lucas Sylvain", role: "")
        context.insert(collaborateur)
        reunion.participants.append(collaborateur)
        #expect(ReviewHeader.metadonnees(for: reunion, locale: localeFr, calendar: calendrier).hasSuffix("1 participant"))
    }

    @Test("Le bouton Rapport dit l'état de la génération")
    func reportButtonLabel() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion")
        context.insert(reunion)
        #expect(ReviewHeader.libelleRapport(for: reunion) == "Transcrire + Rapport")

        reunion.rawTranscript = "texte"
        #expect(ReviewHeader.libelleRapport(for: reunion) == "Rapport")

        reunion.summary = "# Compte-rendu"
        #expect(ReviewHeader.libelleRapport(for: reunion) == "Rapport ✓")

        // `6:20` de la capture.
        reunion.reportGenerationDurationSeconds = 380
        #expect(ReviewHeader.libelleRapport(for: reunion) == "Rapport ✓ 6:20")
    }

    @Test("Le bouton Capture annonce le nombre de captures")
    func captureButtonLabel() {
        #expect(ReviewHeader.libelleCapture(count: 0) == "Capture")
        #expect(ReviewHeader.libelleCapture(count: 4) == "Capture 4")
    }
}
