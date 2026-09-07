import Foundation
import SwiftData

/// Les **seules** écritures de l'écran de préparation 1:1 (capture 2b) :
/// un nouvel engagement, la bascule tenu/rouvert d'un engagement, l'ajout et
/// l'édition d'un objectif.
///
/// Un fichier d'extension du domaine, dans `Services/OneOnOne/Prep/` : le lot
/// 10 a posé la règle « `OneOnOneThreadStore` est le seul service du domaine
/// qui écrit en base », et `CommitmentLedger` comme `OneOnOneObjectiveTone`
/// sont purs par construction. Y glisser un `context.insert` les rendrait
/// intestables et ferait mentir leur documentation. Les trois gestes de cet
/// écran vivent donc ici, ensemble, et nulle part ailleurs.
///
/// Aucune de ces fonctions n'invente de donnée : elles bornent, refusent le
/// vide, et sauvegardent une fois.
@MainActor
enum OneOnOnePrepStore {

    // MARK: - Engagements

    /// Le composeur `Nouvel engagement…` du pied du tableau.
    ///
    /// - Returns: l'engagement créé, ou `nil` si le texte est vide — un
    ///   engagement sans énoncé n'est pas un engagement, et une ligne vide dans
    ///   ce tableau fausserait le taux de tenue.
    @discardableResult
    static func addCommitment(text: String,
                              ownerSide: OneOnOneSide = .manager,
                              dueAt: Date? = nil,
                              promisedAt: Date = Date(),
                              in thread: OneOnOneThread,
                              in context: ModelContext) -> Commitment? {
        let propre = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return nil }

        let engagement = Commitment(
            text: propre,
            ownerSide: ownerSide,
            dueAt: dueAt,
            state: .open,
            promisedAt: promisedAt,
            // Le manager écrit en `shared` par défaut (spec §3.2) : un
            // engagement réciproque que l'autre ne verrait pas n'engage
            // personne.
            visibility: OneOnOneConfidentiality.defaultVisibility(for: .manager)
        )
        context.insert(engagement)
        engagement.thread = thread
        try? context.save()
        return engagement
    }

    /// Le clic sur la pastille d'état de la première colonne : solde
    /// l'engagement ouvert, rouvre celui qui était tenu.
    ///
    /// Un engagement **manqué** ne se rouvre pas d'un clic : le manquement est
    /// un fait de l'entretien, et l'effacer par inadvertance depuis un écran de
    /// préparation reviendrait à réécrire l'historique. Il faut passer par la
    /// séance pour cela.
    static func toggleKept(_ commitment: Commitment,
                           on date: Date = Date(),
                           in context: ModelContext) {
        switch commitment.state {
        case .open:
            CommitmentLedger.markKept(commitment, on: date)
        case .kept:
            commitment.state = .open
            commitment.settledAt = nil
        case .missed:
            return
        }
        try? context.save()
    }

    // MARK: - Objectifs

    /// L'ajout inline de la carte `OBJECTIFS S2`.
    ///
    /// La date de revue reprend celle des objectifs déjà posés : la carte
    /// n'affiche qu'**une** échéance en pied (`OneOnOneObjectiveList.reviewLabel`),
    /// et un nouvel objectif sans date ferait disparaître la ligne si c'était
    /// lui qui portait la plus proche.
    @discardableResult
    static func addObjective(label: String,
                             progress: Int = 0,
                             reviewAt: Date? = nil,
                             in thread: OneOnOneThread,
                             in context: ModelContext) -> OneOnOneObjective? {
        let propre = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return nil }

        let rang = (thread.objectives.map(\.order).max() ?? -1) + 1
        let revue = reviewAt ?? thread.objectives.compactMap(\.reviewAt).min()
        let objectif = OneOnOneObjective(label: propre,
                                         progress: progress,
                                         reviewAt: revue,
                                         order: rang)
        context.insert(objectif)
        objectif.thread = thread
        try? context.save()
        return objectif
    }

    /// L'édition inline : le libellé, le pourcentage, ou les deux. Un
    /// paramètre `nil` laisse le champ tel quel — c'est ce qui permet de
    /// valider un pourcentage sans toucher au libellé qu'on n'a pas ouvert.
    static func update(_ objective: OneOnOneObjective,
                       label: String? = nil,
                       progress: Int? = nil,
                       reviewAt: Date?? = nil,
                       in context: ModelContext) {
        if let label {
            let propre = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !propre.isEmpty { objective.label = propre }
        }
        if let progress { objective.progress = min(100, max(0, progress)) }
        if let reviewAt { objective.reviewAt = reviewAt }
        try? context.save()
    }
}
