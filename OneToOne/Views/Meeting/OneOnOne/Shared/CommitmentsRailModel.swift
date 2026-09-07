import Foundation
import SwiftData

/// Le modèle de vue du rail d'engagements de la capture 2a (spec §3.3, colonne
/// droite) — **pur**, hors de toute vue.
///
/// C'est ici que se tient le critère d'acceptation chantier 2 n° 2 : « un
/// engagement manqué côté manager est visible aussi bien dans 2a que dans 2b,
/// avec son compteur de reports ». Un rail rendu directement depuis
/// `CommitmentLedger` dans une `View` rendrait ce critère invérifiable
/// autrement qu'à l'œil.
///
/// Ne recalcule rien de ce que le lot 10 sait déjà faire : les filtres, le tri
/// par retard, le compteur de reports et la date de solde viennent de
/// `CommitmentLedger`. Ce qui est ici, c'est ce que l'**écran** ajoute — le
/// regroupement par côté, les titres, les pilules et les invites de vide.
@MainActor
enum CommitmentsRailModel {

    // MARK: - Groupes

    /// Un groupe titré du rail : `Moi · 2`, `Laurent · 2`.
    struct Group: Identifiable, Equatable {
        var side: OneOnOneSide
        /// `Moi · 2` — le libellé complet, compteur inclus.
        var title: String
        /// Initiales de l'avatar du groupe (`YP`, `LN`).
        var initials: String
        var commitments: [Commitment]

        var id: String { side.rawValue }
    }

    /// Les deux groupes de la séance, **le porteur du fil d'abord**.
    ///
    /// Les deux groupes sont rendus même vides : la capture les montre côte à
    /// côte, et un groupe qui disparaîtrait quand il est vide ferait sauter la
    /// mise en page d'un entretien à l'autre. L'invite de vide est rendue par
    /// `emptyInvite(for:in:)`.
    ///
    /// - Parameter ownerName: le nom de l'utilisateur de l'application
    ///   (`AppSettings.ownerName`), pour ses initiales. Vide → `?`, ce que la
    ///   pastille sait afficher.
    static func groups(for meeting: Meeting,
                       in thread: OneOnOneThread,
                       ownerName: String) -> [Group] {
        // « ENGAGEMENTS DE CETTE SÉANCE » : ceux qui ont été **pris ici**. Un
        // engagement d'une séance antérieure appartient au registre du fil, pas
        // à la liste de ce qu'on vient de se promettre.
        let deLaSeance = thread.commitments.filter {
            $0.promisedInMeeting?.persistentModelID == meeting.persistentModelID
        }

        return [thread.myRole, other(of: thread.myRole)].map { side in
            let lignes = CommitmentLedger.byLatenessDescending(
                deLaSeance.filter { $0.ownerSide == side }, now: Date.distantPast)
            return Group(side: side,
                         title: "\(sideTitle(side, in: thread)) · \(lignes.count)",
                         initials: initials(for: side, in: thread, ownerName: ownerName),
                         commitments: lignes)
        }
    }

    /// `Moi` pour mon côté du fil, le prénom de l'autre sinon — même règle que
    /// `OneOnOneRecapBuilder.sideTitle`, dont c'est la reprise à l'écran.
    static func sideTitle(_ side: OneOnOneSide, in thread: OneOnOneThread) -> String {
        OneOnOneRecapBuilder.sideTitle(side, in: thread)
    }

    /// L'invite d'un groupe vide (« aucune zone vide sans invite »).
    static func emptyInvite(for side: OneOnOneSide, in thread: OneOnOneThread) -> String {
        side == thread.myRole
            ? "Rien pour vous — tapez /engagement dans les notes"
            : "Rien pour \(OneOnOneThreadStore.firstName(of: thread)) — tapez /engagement dans les notes"
    }

    // MARK: - Pilules d'une carte

    /// L'échéance : le **jour de la semaine** quand elle tombe dans la semaine
    /// calendaire de la séance (`Vendredi`), la date courte au-delà
    /// (`9 sept.`).
    ///
    /// Un « vendredi » ne veut dire quelque chose qu'à l'intérieur de la
    /// semaine où il est prononcé : passé le dimanche, « vendredi » est
    /// ambigu, et la capture écrit bien `11 sept.` pour la semaine suivante.
    ///
    /// `nil` sans échéance : on ne peut pas afficher une date qui n'a pas été
    /// prise.
    static func duePill(_ commitment: Commitment, now: Date) -> String? {
        guard let due = commitment.dueAt else { return nil }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.locale = Locale(identifier: "fr_FR")
        calendrier.firstWeekday = 2 // lundi
        if calendrier.isDate(due, equalTo: now, toGranularity: .weekOfYear) {
            return OneOnOneDateFormat.weekday(due)
        }
        return OneOnOneDateFormat.dayMonth(due)
    }

    /// `Bloquant pour lui` / `Bloquant pour moi` — la criticité, dite du point
    /// de vue de celui qui lit l'écran. Un engagement que **je** porte bloque
    /// l'autre ; un engagement qu'il porte me bloque.
    static func criticalityPill(_ commitment: Commitment) -> String? {
        guard commitment.blocksOther else { return nil }
        switch commitment.ownerSide {
        case .manager:      return "Bloquant pour lui"
        case .collaborator: return "Bloquant pour moi"
        }
    }

    /// `● privé` / `● escaladé` — rien sur une ligne partagée : c'est le
    /// défaut côté manager, et le marquer ferait de la pilule du décor.
    static func privacyPill(_ commitment: Commitment) -> String? {
        switch commitment.visibility {
        case .shared:    return nil
        case .private:   return "● privé"
        case .escalated: return "● escaladé"
        }
    }

    /// `4h` — la charge, **uniquement** quand une action liée la porte
    /// (`ActionTask.effortMinutes`). Aucune estimation n'est inventée depuis le
    /// texte : une charge fausse sur une carte d'engagement se retrouverait
    /// dans un arbitrage.
    static func effortPill(_ commitment: Commitment) -> String? {
        guard let minutes = commitment.linkedAction?.effortMinutes, minutes > 0 else { return nil }
        guard minutes >= 60 else { return "\(minutes)min" }
        let heures = minutes / 60
        let reste = minutes % 60
        return reste == 0 ? "\(heures)h" : "\(heures)h\(String(format: "%02d", reste))"
    }

    // MARK: - Tenus depuis le dernier 1:1

    /// Une ligne de `TENUS DEPUIS LE DERNIER 1:1`.
    struct LedgerLine: Identifiable, Equatable {
        /// `✓` ou `✗`.
        var symbol: String
        var text: String
        /// Initiales du porteur (`LN`, `YP`).
        var initials: String
        var isMissed: Bool
        /// `2× reporté`, ou `nil` quand rien n'a été reporté.
        var deferralLabel: String?
        var id: String { text }
    }

    /// Le registre depuis la séance précédente du fil : les engagements soldés
    /// **et** ceux qui sont en retard sans avoir été soldés.
    ///
    /// Les retards non soldés y figurent en `✗` : la capture les montre ainsi
    /// (« ✗ Retour sur la grille d'astreinte — YP · 2× reporté », dont
    /// l'échéance est passée de six semaines et que personne n'a fermée). Ne
    /// garder que les soldés ferait **disparaître de l'écran** l'engagement
    /// qu'on n'a jamais tenu — exactement l'inverse de ce que le critère n° 2
    /// demande.
    static func ledgerLines(for meeting: Meeting,
                            in thread: OneOnOneThread,
                            ownerName: String,
                            now: Date) -> [LedgerLine] {
        let depuis = OneOnOneThreadStore.previousMeeting(before: meeting, in: thread)?.date
        let soldes = CommitmentLedger.settledSince(depuis, in: thread)
        let retards = CommitmentLedger.overdue(thread, now: now)

        // Un engagement en retard peut aussi avoir été soldé (`missed`) : il ne
        // doit apparaître qu'une fois.
        var vus: Set<PersistentIdentifier> = []
        let lignes = (soldes + retards).filter { vus.insert($0.persistentModelID).inserted }

        return lignes
            .map { ligne in
                let manque = ligne.state == .missed || CommitmentLedger.isOverdue(ligne, now: now)
                return LedgerLine(
                    symbol: manque ? "✗" : "✓",
                    text: ligne.text,
                    initials: initials(for: ligne.ownerSide, in: thread, ownerName: ownerName),
                    isMissed: manque,
                    deferralLabel: CommitmentLedger.deferralLabel(ligne)
                )
            }
            // Les manqués d'abord : c'est la dette du fil, et c'est ce que la
            // capture met en évidence en `accent/report`.
            .sorted { gauche, droite in
                if gauche.isMissed != droite.isMissed { return gauche.isMissed }
                return gauche.text < droite.text
            }
    }

    /// L'invite du registre vide — une première séance n'a rien à solder.
    static let ledgerEmptyInvite = "Rien de soldé depuis la dernière fois"

    // MARK: - Clôture

    /// `Envoyer le récap à Laurent` (bouton primaire `accent/oneonone`).
    static func recapButtonLabel(for thread: OneOnOneThread) -> String {
        let prenom = OneOnOneThreadStore.firstName(of: thread)
        guard !prenom.isEmpty else { return "Envoyer le récap" }
        return "Envoyer le récap à \(prenom)"
    }

    /// `Planifier le prochain — 18 sept.`, ou sans date quand aucune cadence
    /// n'est convenue : proposer une date au hasard serait une invention
    /// (même règle que `OneOnOneThreadStore.nextPlannedDate`).
    static func planNextButtonLabel(for thread: OneOnOneThread, now: Date) -> String {
        guard let date = OneOnOneThreadStore.nextPlannedDate(of: thread, now: now) else {
            return "Planifier le prochain"
        }
        return "Planifier le prochain — \(OneOnOneDateFormat.dayMonth(date))"
    }

    /// La mention du pied de `CLÔTURER`, affichée **sans condition** : c'est
    /// une promesse faite à la personne interrogée, pas un état de la séance.
    static let privacyFootnote = "Les notes privées ne sont jamais incluses"

    // MARK: - Outils

    private static func other(of side: OneOnOneSide) -> OneOnOneSide {
        side == .manager ? .collaborator : .manager
    }

    /// Les initiales de la pastille d'un côté : celles de l'utilisateur de
    /// l'application pour mon côté, celles de la personne du fil pour l'autre.
    static func initials(for side: OneOnOneSide,
                         in thread: OneOnOneThread,
                         ownerName: String) -> String {
        if side == thread.myRole {
            return AvatarPalette.initials(for: ownerName)
        }
        return AvatarPalette.initials(for: thread.collaborator?.name ?? "")
    }
}
