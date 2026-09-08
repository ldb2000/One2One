import Foundation
import SwiftData

/// Les deux boutons de la préparation du 1:1 subi (capture 5b, spec §6.3) :
/// `En faire mon ordre du jour` et `Partager les sujets à <Prénom>`.
///
/// Le **plan** est pur : à partir des lignes cochées, il dit dans quel ordre
/// les sujets doivent se suivre. Seules `apply` et `share` écrivent, comme
/// `ReminderRules.toAgendaItems` au lot 10 — un service du domaine qui insère
/// depuis trois endroits différents est un service qu'on ne sait plus tester.
///
/// ## L'ordre est le propos
///
/// D'abord ce qui est resté sans réponse, ensuite ce que je veux obtenir. Un
/// entretien de trente minutes se joue dans ses cinq premières : commencer par
/// ce qu'on m'a promis et qui n'est pas venu, c'est obtenir une réponse avant
/// que le temps ne manque. Trier autrement — par thème, par ancienneté mêlée —
/// remettrait mes envies avant les paroles non tenues.
///
/// ## Tout est privé
///
/// Les sujets créés sont `private` (spec §6.1 : côté collaborateur, le défaut
/// n'est pas négociable). `Partager les sujets` est le **geste explicite** du
/// critère chantier 5 n° 2, et il ne porte que sur les lignes du plan : rien
/// d'autre du fil ne change de visibilité, et une ligne `escalated` ne
/// redescend jamais vers le manager par ce geste (D9).
@MainActor
enum PrepToAgenda {

    // MARK: - Intitulés

    static let agendaButtonLabel = "En faire mon ordre du jour"

    /// `Partager les sujets à Yann`, ou sans prénom faute d'interlocuteur
    /// nommé : « Partager les sujets à  » avec un blanc se voit.
    static func shareButtonLabel(for thread: OneOnOneThread) -> String {
        let prenom = OneOnOneThreadStore.firstName(of: thread)
        return prenom.isEmpty ? "Partager les sujets" : "Partager les sujets à \(prenom)"
    }

    /// L'état du bouton après usage : il ne promet plus une action qu'il a déjà
    /// faite. `Ordre du jour prêt · 2 sujets`.
    static func doneLabel(_ count: Int) -> String {
        count == 1 ? "Ordre du jour prêt · 1 sujet" : "Ordre du jour prêt · \(count) sujets"
    }

    /// La confirmation légère du second bouton : le **compte** des sujets, qui
    /// est la seule chose qu'on veut relire avant de rendre visible ce qu'on a
    /// écrit pour soi.
    static func shareConfirmation(_ count: Int) -> String {
        count == 1
            ? "Partager 1 sujet avec votre manager ?"
            : "Partager \(count) sujets avec votre manager ?"
    }

    static let shareConfirmButton = "Partager"
    static let shareCancelButton = "Annuler"
    /// L'état du second bouton une fois le partage fait.
    static func sharedLabel(_ count: Int) -> String {
        count == 1 ? "1 sujet partagé" : "\(count) sujets partagés"
    }

    // MARK: - Le plan

    /// Une ligne du plan : le texte exact du sujet d'ordre du jour à obtenir.
    ///
    /// Le texte, et non un identifiant : une ligne de `RESTÉ SANS RÉPONSE`
    /// n'existe pas encore en base — c'est un calcul —, et l'idempotence se
    /// juge donc sur ce que l'utilisateur lit. Même règle
    /// qu'`AgendaCarryover.hasCopy` et que `ReminderRules.toAgendaItems`.
    struct Line: Equatable, Sendable {
        var text: String
        /// Faux quand la ligne est déjà un sujet du fil (les sujets voulus le
        /// sont toujours : ils viennent de là).
        var isExisting: Bool
    }

    /// Le préfixe que prend une ligne sans réponse en devenant un sujet.
    ///
    /// Sans lui, l'ordre du jour de la séance suivante afficherait
    /// « Mobilité archi — 4 fois évoquée » sans dire d'où la phrase sort, et on
    /// ne saurait plus si on porte une demande, une parole non tenue ou un
    /// constat. Le vocabulaire est celui d'`AgendaItemKind.label` (`Sujet`,
    /// `Demande`), plus la promesse que ce modèle ne connaît pas.
    static func prefix(for source: UnansweredItemsBuilder.Source) -> String {
        switch source {
        case .promise: return "Promesse : "
        case .topic:   return "Sujet : "
        case .request: return "Demande : "
        }
    }

    /// L'ordre exact des sujets à porter — **pur**.
    static func plan(unanswered: [UnansweredItemsBuilder.Item],
                     wanted: [OneOnOneAgendaItem]) -> [Line] {
        unanswered.map { Line(text: prefix(for: $0.source) + $0.text, isExisting: false) }
            + wanted.map { Line(text: $0.text, isExisting: true) }
    }

    // MARK: - Matérialisation

    /// Crée ce qui manque, retrouve ce qui existe, et **numérote dans l'ordre
    /// du plan**.
    ///
    /// Les autres sujets de la séance sont renumérotés à la suite, dans leur
    /// ordre relatif : sans cela un sujet voulu, qui existait déjà avec un rang
    /// bas, remonterait devant les lignes sans réponse et l'ordre du bouton
    /// serait faux dès le premier clic.
    ///
    /// Les **demandes** gardent leurs rangs : les deux cartes de la séance
    /// filtrent des listes séparées (ce que documente déjà
    /// `CollaboratorSessionModel.moveTopics`), donc une collision de rang entre
    /// un sujet et une demande est sans effet à l'écran.
    ///
    /// - Returns: les sujets du plan, dans l'ordre du plan.
    @discardableResult
    static func apply(_ plan: [Line],
                      for meeting: Meeting,
                      in thread: OneOnOneThread,
                      in context: ModelContext) -> [OneOnOneAgendaItem] {
        guard !plan.isEmpty else { return [] }

        var portes: [OneOnOneAgendaItem] = []
        for ligne in plan {
            if let existant = topic(named: ligne.text, in: thread) {
                // Un sujet retrouvé rejoint la séance préparée : c'est le
                // rattachement qui le fait apparaître à son ordre du jour.
                existant.meeting = meeting
                portes.append(existant)
                continue
            }
            let item = OneOnOneAgendaItem(
                text: ligne.text,
                addedBySide: .collaborator,
                order: 0,
                state: .todo,
                visibility: OneOnOneConfidentiality.defaultVisibility(for: thread.myRole),
                kind: .topic)
            context.insert(item)
            item.thread = thread
            item.meeting = meeting
            portes.append(item)
        }

        // Les rangs : le plan d'abord, le reste des sujets de la séance après.
        let identifiantsPortes = Set(portes.map(\.persistentModelID))
        for (rang, item) in portes.enumerated() {
            item.order = rang
        }
        let autres = AgendaCarryover.items(of: thread, for: meeting)
            .filter { $0.kind == .topic && !identifiantsPortes.contains($0.persistentModelID) }
        for (decalage, item) in autres.enumerated() {
            item.order = portes.count + decalage
        }

        try? context.save()
        return portes
    }

    /// Vrai quand **chaque** ligne du plan est déjà un sujet du fil.
    ///
    /// Vrai aussi sur un plan vide : il n'y a alors rien à verser, et le bouton
    /// resterait actif sans effet — ce qui pousse à cliquer deux fois pour
    /// vérifier (même règle que `ReminderRules.areAllOnAgenda`).
    static func isApplied(_ plan: [Line], in thread: OneOnOneThread) -> Bool {
        let existants = Set(thread.agendaItems.filter { $0.kind == .topic }.map(\.text))
        return plan.allSatisfy { existants.contains($0.text) }
    }

    // MARK: - Partage

    /// Le second bouton : les sujets du plan passent en `shared`.
    ///
    /// `apply` d'abord, et c'est voulu : partager ce qu'on n'a pas encore versé
    /// n'aurait rien à partager, et la capture montre les deux boutons côte à
    /// côte sans dire lequel cliquer d'abord. `apply` étant idempotent, le
    /// chemin est le même dans les deux ordres.
    ///
    /// Seules les lignes **privées** basculent : une ligne `escalated` reste
    /// escaladée (D9), et une ligne déjà partagée n'a pas à être recomptée.
    ///
    /// - Returns: le nombre de sujets rendus visibles.
    @discardableResult
    static func share(_ plan: [Line],
                      for meeting: Meeting,
                      in thread: OneOnOneThread,
                      in context: ModelContext) -> Int {
        let portes = apply(plan, for: meeting, in: thread, in: context)
        var compte = 0
        for item in portes where item.visibility == .private {
            item.visibility = .shared
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Vrai quand tous les sujets du plan sont déjà visibles du manager.
    static func isShared(_ plan: [Line], in thread: OneOnOneThread) -> Bool {
        guard !plan.isEmpty else { return false }
        return plan.allSatisfy { ligne in
            guard let item = topic(named: ligne.text, in: thread) else { return false }
            return item.visibility == .shared
        }
    }

    // MARK: - Outils

    /// Le sujet du fil qui porte ce texte. Les demandes sont exclues : une
    /// demande et un sujet du même libellé sont deux lignes distinctes, sur
    /// deux cartes distinctes.
    private static func topic(named text: String,
                              in thread: OneOnOneThread) -> OneOnOneAgendaItem? {
        thread.agendaItems.first { $0.kind == .topic && $0.text == text }
    }
}
