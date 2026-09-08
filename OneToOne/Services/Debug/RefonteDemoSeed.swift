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

    /// La réunion d'origine des trois actions reportées : « REPORTÉES DU
    /// 1ER SEPT. — 3 » dans le rail de la capture, et « 1 sept. — COSUI
    /// hebdo » dans la nav latérale de `1c-poste-de-pilotage.png`.
    static let carriedMeetingTitle = "COSUI hebdo"

    /// Les douze actions du rail (capture 1a).
    ///
    /// L'arithmétique de la capture est tenue **exactement** : trois actions
    /// portent un responsable et sont **celles qui sont reportées** du 1er
    /// septembre (le rendu compact d'un groupe reporté n'affiche pas de
    /// porteur, donc rien ne le contredit à l'écran) ; les neuf autres n'ont
    /// pas de responsable. Cela donne les trois nombres de la capture d'un
    /// coup : `12 · 9 non assignées` au bandeau, `À ASSIGNER — 9` et
    /// `REPORTÉES DU 1ER SEPT. — 3` au rail.
    ///
    /// - `echeance` : jours à partir de la date de la réunion, `nil` = aucune.
    /// - `charge` : `effortMinutes`, `nil` = non estimée.
    /// - `reportee` : reportée du 1er septembre.
    /// - `sourceSegment` : indice dans `transcript`, pour la chaîne de
    ///   citation et la suggestion de responsable.
    static let actions: [(titre: String, porteur: String?, echeance: Int?,
                          charge: Int?, reportee: Bool, sourceSegment: Int?)] = [
        // La capture montre « Vendredi » puis « 11 sept. » : une échéance de la
        // semaine se nomme par son jour, une plus lointaine par sa date. Le
        // libellé étant relatif à **aujourd'hui**, aucune valeur semée ne peut
        // fixer le mot affiché — ce que le jeu reproduit, c'est la forme : une
        // échéance proche et une lointaine côte à côte.
        ("Vérifier l'état des comptes GitLab", nil, 3, 120, false, 1),
        ("Clarifier la situation de facturation (40k)", nil, nil, nil, false, nil),
        ("Chiffrer la fin de migration Marine", nil, 7, 480, false, nil),
        ("Préparer gitlab.rb et valider les flux", "Pierre-Yves Nallet", nil, nil, true, nil),
        ("Planification de la formation Admin", "Cédric Payet", 14, 240, true, nil),
        ("Relancer Alexis/Jeff pour l'estimation", "Lucas Sylvain", nil, nil, true, nil),
        ("Refaire le tour des prérequis de synchronisation", nil, nil, nil, false, 0),
        ("Isoler la partie data de la migration", nil, nil, nil, false, nil),
        ("Obtenir la photo globale de la migration", nil, nil, nil, false, nil),
        ("Synchroniser les pipelines entre la source et le GitLab", nil, nil, 60, false, 0),
        ("Reprendre l'état des lieux (3 jours-hommes)", nil, nil, 480, false, 2),
        ("Confirmer la reprise par le partenaire", nil, nil, nil, false, 3)
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
                              // 4 septembre 2026, 9:15 à Paris — la date que
                              // porte la barre d'espaces de la capture. Le
                              // lot 1 avait semé 1 756 970 100, qui tombe le
                              // 4 septembre **2025** : le vendredi devenait un
                              // jeudi, et tout raccourci d'échéance avec lui.
                              date: Date(timeIntervalSince1970: 1_788_506_100),
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

        // Gardés dans l'ordre localement : une relation SwiftData tout juste
        // renseignée ne garantit ni son contenu ni son ordre avant `save()`,
        // et ce sont ces segments qui portent la chaîne de citation.
        var segments: [TranscriptSegment] = []
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
            segments.append(s)
        }

        let origine = seedCarriedMeeting(projet: projet, in: context)

        for (index, action) in actions.enumerated() {
            let tache = ActionTask(title: action.titre)
            tache.sortOrder = index
            if let nom = action.porteur {
                tache.collaborator = collaborateurs.first { $0.name == nom }
                tache.destinataire = .collaborateur
            } else {
                // Sans porteur, `destinataire` doit dire « à quelqu'un » et non
                // « pour moi », sinon le rail les rangerait dans MES ACTIONS
                // au lieu d'À ASSIGNER (`ActionsRailGrouping`).
                tache.destinataire = .collaborateur
            }
            if let jours = action.echeance {
                tache.dueDate = Calendar.current.date(byAdding: .day, value: jours, to: reunion.date)
            }
            tache.effortMinutes = action.charge
            if action.reportee {
                tache.carriedFromMeeting = origine
                tache.deferralCount = 1
            }
            if let indice = action.sourceSegment, indice < segments.count {
                let segment = segments[indice]
                tache.sourceRef = SourceRef(kind: .transcript,
                                            stableID: segment.stableID ?? UUID(),
                                            t: segment.startSeconds)
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

    /// La réunion du 1er septembre dont trois actions ont été reportées.
    ///
    /// Elle porte un résumé : sans lui, le mode Préparer afficherait « Pas de
    /// résumé » dans « DERNIERS POINTS », ce qui est le cas le moins
    /// intéressant à mettre sous les yeux d'une recette.
    private static func seedCarriedMeeting(projet: Project,
                                           in context: ModelContext) -> Meeting {
        let titre = carriedMeetingTitle
        if let existante = (try? context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.title == titre })
        ))?.first {
            return existante
        }
        // Trois jours avant la réunion de la capture : le 1er septembre 2026,
        // 9:15 à Paris.
        let reunion = Meeting(title: carriedMeetingTitle,
                              date: Date(timeIntervalSince1970: 1_788_246_900),
                              notes: "")
        reunion.kind = .project
        reunion.project = projet
        reunion.shortSummary = """
        Point hebdomadaire : la migration AP avance, trois actions restent \
        ouvertes et sont reportées au prochain point.
        """
        context.insert(reunion)
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
