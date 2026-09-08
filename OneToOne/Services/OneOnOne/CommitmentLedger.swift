import Foundation

/// Le registre des engagements réciproques d'un fil — **pur**, hors de toute
/// vue : la capture 2a (colonne de droite, `TENUS DEPUIS LE DERNIER 1:1`) et la
/// capture 2b (tableau `Engagements réciproques`, pied `8 tenus sur 11 · taux
/// 73 %`) doivent afficher les mêmes nombres, ce qui n'arrive que s'ils sortent
/// du même calcul.
///
/// **Ne lit pas `EngagementLedger`.** L'ancienne dérivation
/// (`DecisionEntry.settledAt` + `ActionTask.engagementSettledAt`) reste
/// affichée en « Historique », en lecture seule : convertir ferait apparaître
/// deux fois le même engagement dans les compteurs, et le taux de tenue serait
/// faux le jour de la migration.
enum CommitmentLedger {

    // MARK: - Lecture

    /// Les engagements du fil, du plus récemment promis au plus ancien.
    /// `side == nil` = les deux côtés (le filtre « Les deux » de la capture 2b).
    static func all(_ thread: OneOnOneThread, side: OneOnOneSide?) -> [Commitment] {
        thread.commitments
            .filter { side == nil || $0.ownerSide == side }
            .sorted { gauche, droite in
                if gauche.promisedAt != droite.promisedAt { return gauche.promisedAt > droite.promisedAt }
                return gauche.text < droite.text
            }
    }

    static func open(_ thread: OneOnOneThread, side: OneOnOneSide? = nil) -> [Commitment] {
        all(thread, side: side).filter { $0.state == .open }
    }

    static func kept(_ thread: OneOnOneThread, side: OneOnOneSide? = nil) -> [Commitment] {
        all(thread, side: side).filter { $0.state == .kept }
    }

    static func missed(_ thread: OneOnOneThread, side: OneOnOneSide? = nil) -> [Commitment] {
        all(thread, side: side).filter { $0.state == .missed }
    }

    /// Vrai quand l'engagement est ouvert **et** que son échéance est passée.
    /// Un engagement sans échéance n'est jamais en retard : on ne peut pas
    /// être en retard sur une date qui n'a pas été prise.
    static func isOverdue(_ commitment: Commitment, now: Date) -> Bool {
        guard commitment.state == .open, let due = commitment.dueAt else { return false }
        return due < now
    }

    /// Les engagements en retard du fil, du plus en retard au moins.
    static func overdue(_ thread: OneOnOneThread, side: OneOnOneSide? = nil, now: Date) -> [Commitment] {
        byLatenessDescending(all(thread, side: side).filter { isOverdue($0, now: now) }, now: now)
    }

    /// Ce qui a été **soldé** (tenu ou manqué) depuis `date`.
    ///
    /// `date == nil` (aucune séance précédente dans le fil) rend tout ce qui
    /// est soldé : à la première séance, « depuis le dernier 1:1 » veut dire
    /// « depuis toujours ».
    static func settledSince(_ date: Date?, in thread: OneOnOneThread,
                             side: OneOnOneSide? = nil) -> [Commitment] {
        all(thread, side: side).filter { engagement in
            guard engagement.state != .open else { return false }
            guard let date else { return true }
            return settlementDate(of: engagement) >= date
        }
    }

    /// Date de solde d'un engagement, avec repli sur `promisedAt` pour les
    /// lignes créées avant la colonne `settledAt` (ou semées sans elle).
    static func settlementDate(of commitment: Commitment) -> Date {
        commitment.settledAt ?? commitment.promisedAt
    }

    // MARK: - Tri

    /// Du plus en retard au moins en retard, puis les échéances à venir, puis
    /// les engagements sans échéance (spec §6.2 : « cartes triées par retard
    /// décroissant »).
    ///
    /// Tri **stable** à retard égal (par date de prise puis par texte) :
    /// `sorted` ne l'est pas, et une liste qui se réordonne à chaque rendu est
    /// illisible.
    static func byLatenessDescending(_ commitments: [Commitment], now: Date) -> [Commitment] {
        commitments.sorted { gauche, droite in
            let rangGauche = latenessRank(gauche, now: now)
            let rangDroite = latenessRank(droite, now: now)
            if rangGauche != rangDroite { return rangGauche > rangDroite }
            if gauche.promisedAt != droite.promisedAt { return gauche.promisedAt < droite.promisedAt }
            return gauche.text < droite.text
        }
    }

    /// Clé de tri : le retard en secondes. `-.infinity` sans échéance, pour que
    /// les engagements sans date finissent la liste sans jamais devancer une
    /// échéance connue, même très lointaine.
    private static func latenessRank(_ commitment: Commitment, now: Date) -> Double {
        guard let due = commitment.dueAt else { return -.infinity }
        return now.timeIntervalSince(due)
    }

    // MARK: - Comptages

    static func counts(_ thread: OneOnOneThread,
                       side: OneOnOneSide? = nil) -> (kept: Int, missed: Int, open: Int) {
        let tous = all(thread, side: side)
        return (tous.filter { $0.state == .kept }.count,
                tous.filter { $0.state == .missed }.count,
                tous.filter { $0.state == .open }.count)
    }

    /// Taux de tenue = `kept / (kept + missed)`, entre 0 et 1.
    ///
    /// `nil` quand rien n'est soldé : afficher « taux 0 % » sur un fil qui n'a
    /// encore rien soldé accuserait à tort.
    static func keptRate(_ thread: OneOnOneThread, side: OneOnOneSide? = nil) -> Double? {
        let comptes = counts(thread, side: side)
        let soldes = comptes.kept + comptes.missed
        guard soldes > 0 else { return nil }
        return Double(comptes.kept) / Double(soldes)
    }

    /// Le pied du tableau de la capture 2b : « 8 tenus sur 11 · taux 73 % ».
    static func rateLabel(_ thread: OneOnOneThread, side: OneOnOneSide? = nil) -> String? {
        guard let taux = keptRate(thread, side: side) else { return nil }
        let comptes = counts(thread, side: side)
        let soldes = comptes.kept + comptes.missed
        let pourcentage = Int((taux * 100).rounded())
        return "\(comptes.kept) tenus sur \(soldes) · taux \(pourcentage) %"
    }

    /// « n× reporté » de la capture 2a. `nil` quand rien n'a été reporté : un
    /// « 0× reporté » est du bruit.
    static func deferralLabel(_ commitment: Commitment) -> String? {
        guard commitment.deferralCount > 0 else { return nil }
        return "\(commitment.deferralCount)× reporté"
    }

    /// La pilule rouge de l'en-tête de la capture 2b : « 1 en retard côté
    /// manager ». Compte les manqués **et** les ouverts dont l'échéance est
    /// passée : les deux sont une parole non tenue, et la spec ne fait pas de
    /// différence dans cet indicateur.
    static func lateOnManagerSideLabel(_ thread: OneOnOneThread, now: Date) -> String? {
        let compte = all(thread, side: .manager).filter {
            $0.state == .missed || isOverdue($0, now: now)
        }.count
        guard compte > 0 else { return nil }
        return "\(compte) en retard côté manager"
    }

    // MARK: - Transitions

    /// Marque tenu. **Sans effet** sur un engagement déjà soldé : le premier
    /// solde fait foi, comme dans `EngagementLedger.settle`.
    static func markKept(_ commitment: Commitment, on date: Date = Date()) {
        guard commitment.state == .open else { return }
        commitment.state = .kept
        commitment.settledAt = date
    }

    static func markMissed(_ commitment: Commitment, on date: Date = Date()) {
        guard commitment.state == .open else { return }
        commitment.state = .missed
        commitment.settledAt = date
    }

    /// Reporte l'échéance. **Ne solde pas** : l'engagement reste `open`, seul le
    /// compteur monte — c'est le compteur que la spec veut voir affiché « y
    /// compris pour le manager, sans exception ».
    ///
    /// Nommé `postpone` et non `defer` : `defer` est un mot réservé de Swift.
    ///
    /// `to == nil` garde l'échéance en place : l'effacer sortirait l'engagement
    /// de la liste des retards, ce qui est exactement l'inverse de reporter.
    static func postpone(_ commitment: Commitment, to newDue: Date? = nil) {
        guard commitment.state == .open else { return }
        commitment.deferralCount += 1
        if let newDue { commitment.dueAt = newDue }
    }
}
