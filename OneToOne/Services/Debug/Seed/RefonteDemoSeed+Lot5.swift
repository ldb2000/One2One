import Foundation
import SwiftData

/// Ce que la capture `1c-poste-de-pilotage.png` ajoute à `1a-cockpit.png` :
/// trois décisions horodatées avec leur porteur, quatre thèmes, et deux
/// réunions de plus dans le fil du projet.
///
/// Une **extension** et non une modification de `RefonteDemoSeed` : les lots 4,
/// 6 et 10 se développent en parallèle sur la même base, et le semis du lot 3
/// est le fichier qu'ils touchent tous. Ici, rien n'y est réécrit — `seedLot5`
/// appelle `seed(in:)` puis complète.
///
/// Idempotent comme lui : semer deux fois n'ajoute ni décision ni thème.
@MainActor
extension RefonteDemoSeed {

    /// Les trois décisions de la carte `DÉCISIONS PRISES · 3`, aux timecodes de
    /// la capture (`11:03`, `13:40`, `20:15`).
    ///
    /// La première nomme son porteur en fin de phrase : c'est cette forme que
    /// `DecisionsCard.separerPorteur` détache pour l'afficher en `— Olivier
    /// Freund`. Les deux autres n'en ont pas, et la carte doit le supporter.
    static let decisionsHorodatees: [(t: Double, texte: String)] = [
        (663, "Le partenaire finalise la migration — Olivier Freund"),
        (820, "Pas de rallonge budgétaire sur cette phase"),
        (1_215, "Webcast développeurs lancé cette semaine")
    ]

    /// Les quatre thèmes de la carte `EN UNE PHRASE`.
    /// Suffixé comme `shortSummaryLot5` : le semis de base porte déjà un
    /// `tags`, les thèmes du **projet** de la fiche du lot 9.
    static let tagsLot5 = ["Migration AP", "Facturation", "GitLab / CI-CD", "Ressources"]

    /// Le résumé en une phrase de la capture, avec son gras.
    static let shortSummaryLot5 = """
    Point de situation sur les migrations **AP** et **Marine** : l'AP avance mais reste \
    bloquée sur les comptes GitLab et la conteneurisation côté partenaire. \
    **Décision** : le partenaire finalise lui-même la migration. \
    **Reste à faire** : chiffrer la fin Marine — 40k déjà engagés sans livrable finalisé.
    """

    /// Les deux réunions antérieures que le bloc `PROJET` de la nav latérale
    /// montre à côté de « 1 sept. — COSUI hebdo » (semée par le lot 3).
    ///
    /// - `jours` : nombre de jours **avant** la réunion de la capture.
    static let reunionsPrecedentes: [(titre: String, jours: Int, resume: String)] = [
        ("Gouvernance", 4, """
        Revue de gouvernance : le comité valide le principe de la reprise par le \
        partenaire, sous réserve du chiffrage.
        """),
        ("Situation AP", 9, """
        État des lieux de la migration AP : comptes GitLab désactivés, \
        conteneurisation non commencée côté partenaire.
        """)
    ]

    /// Sème le jeu du lot 3 puis le complète pour la capture 1c.
    ///
    /// - Returns: la réunion de la capture.
    @discardableResult
    static func seedLot5(in context: ModelContext) -> Meeting {
        let reunion = seed(in: context)

        semerDecisions(dans: reunion, in: context)
        semerTags(dans: reunion, in: context)
        semerReunionsPrecedentes(dans: reunion, in: context)

        // Le résumé de 1c est plus riche que celui de 1a : il porte le gras et
        // la structure « Décision / Reste à faire » que montre la carte
        // `EN UNE PHRASE`. Réécrit à chaque semis — c'est une donnée de
        // recette, pas une saisie de l'utilisateur.
        reunion.shortSummary = shortSummaryLot5

        try? context.save()
        return reunion
    }

    // MARK: - Décisions

    /// Ajoute les décisions manquantes, sans toucher à celles qui existent.
    ///
    /// L'idempotence se joue sur le **timecode** : le lot 3 sème déjà une
    /// décision à `11:03`, et une comparaison sur le texte en aurait créé une
    /// seconde au même instant, puisque la formulation de 1c n'est pas celle de
    /// 1a (« Le partenaire finalise la migration — Olivier Freund » contre
    /// « … lui-même la migration (Olivier Freund). »).
    private static func semerDecisions(dans reunion: Meeting, in context: ModelContext) {
        let existants = Set(reunion.timedNotes.filter { $0.kind == .decision }.map(\.t))
        var ordre = (reunion.timedNotes.map(\.orderIndex).max() ?? -1) + 1
        for decision in decisionsHorodatees where !existants.contains(decision.t) {
            let note = MeetingNote(t: decision.t,
                                   text: decision.texte,
                                   kind: .decision,
                                   visibility: MeetingNoteStore.defaultVisibility(for: reunion.kind),
                                   orderIndex: ordre)
            context.insert(note)
            note.meeting = reunion
            ordre += 1
        }
        // La décision de `11:03` du lot 3 prend la formulation de 1c : c'est
        // elle que la carte affiche, avec son porteur détaché.
        if let onzeHeuresTrois = reunion.timedNotes.first(where: { $0.kind == .decision && $0.t == 663 }) {
            onzeHeuresTrois.text = decisionsHorodatees[0].texte
        }
    }

    // MARK: - Thèmes

    private static func semerTags(dans reunion: Meeting, in context: ModelContext) {
        for nom in tagsLot5 {
            guard let theme = MeetingTag.findOrCreate(name: nom, in: context) else { continue }
            let deja = reunion.tags.contains { $0.persistentModelID == theme.persistentModelID }
            if !deja { reunion.tags.append(theme) }
        }
    }

    // MARK: - Fil du projet

    /// Les deux réunions antérieures du projet, créées si elles n'existent pas.
    ///
    /// Elles portent un résumé : le bloc `PROJET` ne l'affiche pas, mais le mode
    /// Préparer et l'assistant le lisent, et une réunion vide dans le fil est
    /// le cas le moins intéressant à mettre sous les yeux d'une recette.
    private static func semerReunionsPrecedentes(dans reunion: Meeting, in context: ModelContext) {
        guard let projet = reunion.project else { return }
        for precedente in reunionsPrecedentes {
            let titre = precedente.titre
            let existante = (try? context.fetch(
                FetchDescriptor<Meeting>(predicate: #Predicate { $0.title == titre })
            ))?.first
            if existante != nil { continue }
            guard let date = Calendar.current.date(byAdding: .day,
                                                   value: -precedente.jours,
                                                   to: reunion.date) else { continue }
            let nouvelle = Meeting(title: precedente.titre, date: date, notes: "")
            nouvelle.kind = .project
            nouvelle.project = projet
            nouvelle.shortSummary = precedente.resume
            context.insert(nouvelle)
        }
    }
}
