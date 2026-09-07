import Foundation
import SwiftData

/// Le jeu de données de la capture de référence
/// `docs/superpowers/specs/refonte-2026-09/ecrans/1a-cockpit.png`.
///
/// Sert la **recette** de tous les lots de la refonte : sans lui, comparer
/// l'écran à la maquette demande de saisir à la main six participants, douze
/// actions, trois décisions et cinq risques — c'est-à-dire de ne jamais le
/// faire deux fois pareil.
///
/// Idempotent : semer deux fois ne duplique pas la réunion. Ce n'est pas une
/// commodité, c'est la condition pour qu'une commande de menu soit sans
/// danger.
@MainActor
enum RefonteDemoSeed {

    /// Le titre exact de la capture — il sert aussi de clé d'idempotence.
    static let meetingTitle = "[P25_110] Partage statut final et chiffrage reste à faire"
    static let projectName = "S/D — Modernisation CI/CD"
    /// Durée de l'audio de la capture : `23:24`.
    static let durationSeconds = 1_404

    /// Les six participants, dans l'ordre des pastilles de la capture
    /// (`PY NL CP LS CA LD`).
    static let participants: [(nom: String, role: String)] = [
        ("Pierre-Yves Nallet", "Architecte"),
        ("Nathalie Lefèvre", "Cheffe de projet"),
        ("Cédric Payet", "Ingénieur CI/CD"),
        ("Lucas Sylvain", "Architecte"),
        ("Camille Aubert", "Product owner"),
        ("Laurent Deberti", "Manager")
    ]

    /// Les trois décisions, dont celle de la carte DÉCISIONS et une qui porte
    /// sur le budget (« dont 1 budget »).
    static let decisions = [
        "Le partenaire finalise lui-même la migration (Olivier Freund)",
        "Budget : 40k déjà payés, le reste à faire est à chiffrer avant le 11 septembre",
        "La formation Admin est planifiée sur la première quinzaine d'octobre"
    ]

    /// Les cinq risques, dont deux critiques.
    static let risks: [(titre: String, gravite: String)] = [
        ("Comptes GitLab désactivés — droits à remettre", "Critique"),
        ("Chiffrage du reste à faire non validé", "Critique"),
        ("Prérequis de synchronisation des pipelines non tenus", "Élevé"),
        ("Facturation de 40k sans livrable associé", "Modéré"),
        ("Disponibilité d'Alexis pour l'estimation", "Faible")
    ]

    /// Les douze actions : trois assignées (indices 9, 10, 11), neuf sans
    /// responsable — le « 12 · 9 non assignées » de la capture.
    static let actions: [(titre: String, porteur: String?)] = [
        ("Vérifier l'état des comptes GitLab", nil),
        ("Clarifier la situation de facturation (40k)", nil),
        ("Chiffrer la fin de migration Marine", nil),
        ("Préparer gitlab.rb et valider les flux", nil),
        ("Planification de la formation Admin", nil),
        ("Relancer Alexis/Jeff pour l'estimation", nil),
        ("Refaire le tour des prérequis de synchronisation", nil),
        ("Isoler la partie data de la migration", nil),
        ("Obtenir la photo globale de la migration", nil),
        ("Synchroniser les pipelines entre la source et le GitLab", "Pierre-Yves Nallet"),
        ("Reprendre l'état des lieux (3 jours-hommes)", "Cédric Payet"),
        ("Confirmer la reprise par le partenaire", "Lucas Sylvain")
    ]

    /// Les quatre notes horodatées de la colonne MES NOTES de la capture, avec
    /// leur timecode exact et leur nature.
    ///
    /// Semées en `MeetingNote` (D1) **et** laissées dans `liveNotes` : le
    /// markdown reste lu par l'éditeur des réunions de type `Note` et par les
    /// gabarits de rapport. Le drapeau `notesMigrated` est posé pour que
    /// `MeetingNoteStore.importLiveNotesIfNeeded` n'ajoute pas une cinquième
    /// ligne à `t = 0` — la recette doit montrer exactement quatre lignes.
    static let timedNotes: [(t: Double, texte: String, nature: MeetingNoteKind)] = [
        (252, "Gros morceau = AP. Partie data isolée, on a la photo globale de la migration.", .note),
        (468, "Timing à définir → qui donne le feu vert ?", .note),
        (663, "Le partenaire finalise lui-même la migration (Olivier Freund).", .decision),
        (920, "40k déjà payés, rien de finalisé — reste à chiffrer la fin Marine.", .note)
    ]

    /// Les mêmes notes en markdown (`liveNotes`), telles que l'éditeur
    /// historique les affiche.
    static let liveNotes = """
    **04:12** Gros morceau = **AP**. Partie data isolée, on a la photo globale de la migration.

    **07:48** Timing à définir → qui donne le feu vert ?

    **11:03** **Décision** — le partenaire finalise lui-même la migration (Olivier Freund).

    **15:20** 40k déjà payés, rien de finalisé — reste à chiffrer la fin Marine.
    """

    /// Les segments de transcription de la capture, avec leurs locuteurs.
    static let transcript: [(t: Double, tFin: Double, locuteur: Int, texte: String)] = [
        (231, 252, 0, "Synchroniser les pipelines entre la source et le GitLab. Il y a des prérequis sur lesquels il va falloir refaire le tour."),
        (252, 275, 5, "Tous les comptes ont été désactivés, il faut remettre ça en route et vérifier les droits."),
        (390, 415, 2, "L'état des lieux est repris, l'équivalent de trois jours-hommes. Je trouve que ça fait beaucoup."),
        (663, 690, 3, "C'est un des points décidés par Olivier Freund : ils finalisent eux-mêmes la migration.")
    ]

    static let shortSummary = """
    Le partenaire reprend la fin de la migration ; les comptes GitLab doivent être \
    réactivés et le reste à faire chiffré avant le 11 septembre, 40k ayant déjà été payés \
    sans livrable.
    """

    /// Sème le jeu de démonstration et rend la réunion.
    ///
    /// - Returns: la réunion de la capture, existante ou nouvellement créée.
    @discardableResult
    static func seed(in context: ModelContext) -> Meeting {
        // Idempotence par le titre : une commande de menu peut être cliquée
        // deux fois, et un doublon de recette serait pire qu'inutile.
        let titre = meetingTitle
        let existante = (try? context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.title == titre })
        ))?.first
        if let existante { return existante }

        let projet = seedProject(in: context)
        let collaborateurs = seedCollaborators(in: context)

        let reunion = Meeting(title: meetingTitle,
                              date: Date(timeIntervalSince1970: 1_756_970_100),  // 4 sept. 2026, 9:15 UTC
                              notes: "")
        reunion.kind = .project
        reunion.project = projet
        reunion.durationSeconds = durationSeconds
        reunion.meetingDurationSeconds = durationSeconds
        reunion.liveNotes = liveNotes
        // Les lignes horodatées sont semées explicitement : la reprise du
        // markdown en produirait **une** à `t = 0`, et la capture en montre
        // quatre, à quatre instants distincts.
        reunion.notesMigrated = true
        reunion.shortSummary = shortSummary
        reunion.decisions = decisions
        reunion.rawTranscript = transcript.map(\.texte).joined(separator: "\n\n")
        context.insert(reunion)

        for collaborateur in collaborateurs {
            reunion.participants.append(collaborateur)
            reunion.setParticipantStatus(.present, for: collaborateur)
        }

        for (index, ligne) in timedNotes.enumerated() {
            let note = MeetingNote(t: ligne.t,
                                   text: ligne.texte,
                                   kind: ligne.nature,
                                   visibility: MeetingNoteStore.defaultVisibility(for: reunion.kind),
                                   orderIndex: index)
            context.insert(note)
            note.meeting = reunion
        }

        for (index, segment) in transcript.enumerated() {
            let s = TranscriptSegment(orderIndex: index,
                                      startSeconds: segment.t,
                                      endSeconds: segment.tFin,
                                      text: segment.texte,
                                      speakerID: segment.locuteur)
            context.insert(s)
            s.meeting = reunion
            if segment.locuteur < collaborateurs.count {
                s.speaker = collaborateurs[segment.locuteur]
            }
        }

        for (index, action) in actions.enumerated() {
            let tache = ActionTask(title: action.titre)
            tache.sortOrder = index
            if let nom = action.porteur {
                tache.collaborator = collaborateurs.first { $0.name == nom }
            }
            context.insert(tache)
            tache.meeting = reunion
        }

        for risque in risks {
            let alerte = ProjectAlert(title: risque.titre, severity: risque.gravite)
            context.insert(alerte)
            alerte.meeting = reunion
            alerte.project = projet
        }

        try? context.save()
        return reunion
    }

    private static func seedProject(in context: ModelContext) -> Project {
        let nom = projectName
        if let existant = (try? context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.name == nom })
        ))?.first {
            return existant
        }
        let projet = Project(code: "P25_110",
                             name: projectName,
                             domain: "S/D",
                             sponsor: "Olivier Freund",
                             phase: "Réalisation",
                             status: "Yellow")
        context.insert(projet)
        return projet
    }

    /// Les six collaborateurs, réutilisés s'ils existent déjà : semer ne doit
    /// pas créer un second « Laurent Deberti » dans une base réelle.
    private static func seedCollaborators(in context: ModelContext) -> [Collaborator] {
        let existants = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
        return participants.map { participant in
            if let trouve = existants.first(where: {
                $0.name.localizedCaseInsensitiveCompare(participant.nom) == .orderedSame
            }) {
                return trouve
            }
            let collaborateur = Collaborator(name: participant.nom, role: participant.role)
            context.insert(collaborateur)
            return collaborateur
        }
    }
}
