import Foundation
import SwiftData

/// Ce que la capture `5a-1to1-collaborateur-seance.png` montre **en plus** du
/// jeu du lot 10 : les quatre lignes de `CE QUE J'AI LIVRÉ`, et l'échéance de
/// l'arbitrage qui fait dire `Samedi · pris aujourd'hui` à sa carte.
///
/// Le lot 10 sème déjà le fil côté collaborateur — Yann PENVEN me manage — avec
/// ses trois demandes, ses trois sujets privés, ses trois promesses et les cinq
/// lignes de notes. Ce fichier **complète** : `seedOneOnOneThreads` reste le
/// point d'entrée du domaine, et ni son fichier ni celui du lot 11 ne sont
/// touchés. Tout est **idempotent** — les ajouts sont gardés par leur titre,
/// les ajustements sont des affectations.
@MainActor
extension RefonteDemoSeed {

    private static var jourLot13: TimeInterval { 86_400 }

    /// Point d'entrée du lot 13.
    ///
    /// - Returns: le fil collaborateur et sa dernière séance — celle de la
    ///   capture, le 4 septembre.
    @discardableResult
    static func seedLot13(in context: ModelContext) -> (thread: OneOnOneThread,
                                                        meeting: Meeting)? {
        let fils = seedOneOnOneThreads(in: context)
        let fil = fils.collaborator
        guard let seance = OneOnOneThreadStore.meetings(of: fil, now: oneOnOneSeedDate).last
        else { return nil }

        seedMyClosedActions(in: context)
        seedMyBlockedAction(in: context)
        seedActiveRoleMeeting(in: context)
        seedArbitrationDueDate(fil, seance)
        try? context.save()
        return (fil, seance)
    }

    // MARK: - Ce que j'ai livré : mes actions closes

    /// Les deux lignes `✓ … · Action close le …` de la capture.
    ///
    /// **Sans `collaborator`** : ce sont *mes* actions, et c'est justement ce
    /// que `DeliveredItemsBuilder` vérifie — une action rattachée à une
    /// personne est la sienne, quelle que soit la valeur de `destinataire`. Les
    /// deux livrables de Laurent que sème le lot 10 portent son nom et ne
    /// remontent donc pas ici, ce qui est le comportement voulu.
    private static func seedMyClosedActions(in context: ModelContext) {
        let livrables: [(titre: String, close: Double, charge: Int?)] = [
            // `2 j` sur la carte : 960 minutes, soit deux journées de travail.
            ("Reprise du périmètre Nexus", -6, 960),
            ("Base PostgreSQL dédiée préparée", -2, nil)
        ]
        for livrable in livrables where existingAction(livrable.titre, in: context) == nil {
            let action = ActionTask(title: livrable.titre)
            action.destinataire = .moi
            action.isCompleted = true
            action.completedAt = oneOnOneSeedDate.addingTimeInterval(livrable.close * jourLot13)
            action.createdAt = oneOnOneSeedDate
                .addingTimeInterval((livrable.close - 20) * jourLot13)
            action.effortMinutes = livrable.charge
            context.insert(action)
        }
    }

    /// La quatrième ligne : `◐ Tests de clustering en recette · En cours ·
    /// bloqué par les comptes GitLab`.
    ///
    /// La cause vient d'un **commentaire** et non d'une colonne dédiée : un
    /// blocage se dit dans un commentaire, c'est ce que les utilisateurs font
    /// déjà, et une colonne de plus serait à remplir deux fois.
    private static func seedMyBlockedAction(in context: ModelContext) {
        let titre = "Tests de clustering en recette"
        guard existingAction(titre, in: context) == nil else { return }
        let action = ActionTask(title: titre)
        action.destinataire = .moi
        action.createdAt = oneOnOneSeedDate.addingTimeInterval(-12 * jourLot13)
        context.insert(action)

        let cause = ActionComment(text: "Bloqué par les comptes GitLab",
                                  date: oneOnOneSeedDate.addingTimeInterval(-4 * jourLot13))
        context.insert(cause)
        cause.task = action
    }

    // MARK: - Ce que j'ai livré : une réunion à rôle actif

    /// La troisième ligne : `✓ Présentation COSUI — risques Jenkins · Réunion
    /// du 1er sept. · a débloqué la décision`.
    ///
    /// Une réunion **de projet**, pas un tête-à-tête : mes 1:1 ne sont pas des
    /// livrables. Son rôle actif est porté par une décision, ce que la carte
    /// dit en toutes lettres.
    private static func seedActiveRoleMeeting(in context: ModelContext) {
        let titre = "Présentation COSUI — risques Jenkins"
        let existantes = (try? context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.title == titre })
        )) ?? []
        guard existantes.isEmpty else { return }

        let reunion = Meeting(title: titre,
                              date: oneOnOneSeedDate.addingTimeInterval(-3 * jourLot13),
                              notes: "")
        reunion.kind = .project
        reunion.durationSeconds = 2_700
        reunion.meetingDurationSeconds = reunion.durationSeconds
        reunion.notesMigrated = true
        context.insert(reunion)

        let decision = MeetingNote(
            t: 1_240,
            text: "Jenkins reste en place jusqu'à la fin de la migration ; le risque est porté au COPIL du 25.",
            kind: .decision)
        context.insert(decision)
        decision.meeting = reunion
    }

    // MARK: - Ce qu'il m'a promis

    /// L'arbitrage du Webcast est promis **pendant** la séance et attendu le
    /// lendemain : c'est ce qui fait afficher `Samedi` et `pris aujourd'hui`.
    ///
    /// Le lot 10 le sème déjà avec ces dates ; l'affectation est ici pour que
    /// la carte reste juste si ce jeu-là évolue, et parce qu'un semis
    /// idempotent doit pouvoir se rejouer sur une base déjà peuplée.
    private static func seedArbitrationDueDate(_ fil: OneOnOneThread, _ seance: Meeting) {
        guard let arbitrage = fil.commitments.first(where: {
            $0.text == "Arbitrage renfort / décalage Webcast"
        }) else { return }
        arbitrage.promisedAt = oneOnOneSeedDate
        arbitrage.dueAt = oneOnOneSeedDate.addingTimeInterval(jourLot13)
        arbitrage.promisedInMeeting = seance
    }

    // MARK: - Outils

    /// Une action déjà semée, retrouvée par son titre : semer deux fois ne doit
    /// pas produire deux « Reprise du périmètre Nexus » dans mes preuves.
    private static func existingAction(_ titre: String,
                                       in context: ModelContext) -> ActionTask? {
        let toutes = (try? context.fetch(
            FetchDescriptor<ActionTask>(predicate: #Predicate { $0.title == titre })
        )) ?? []
        return toutes.first
    }
}
