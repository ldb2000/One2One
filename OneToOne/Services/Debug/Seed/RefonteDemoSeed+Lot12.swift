import Foundation
import SwiftData

/// Ce que la capture `2b-1to1-manager-preparation.png` montre et que le lot 10
/// ne sème pas : les **dates** de l'histogramme et de l'historique, et les
/// **résumés d'une ligne** de la carte `HISTORIQUE`.
///
/// Le lot 10 a semé les quatorze séances, les six humeurs, les trois objectifs,
/// les onze engagements et les sujets récurrents — toute l'arithmétique des
/// maquettes. Deux choses lui manquent, et elles ne se voient que sur un écran :
///
/// 1. **Les dates.** Le lot 10 pose une cadence parfaitement régulière de
///    quinze jours, ce qui donne `26/06 10/07 24/07 07/08 21/08 04/09`. La
///    capture, elle, écrit `12/06 26/06 10/07 24/07 21/08 04/09` : il n'y a pas
///    eu d'entretien la première semaine d'août, et l'`HISTORIQUE` saute la
///    même séance. Un fil réel a ce trou-là — celui des congés — et c'est
///    précisément ce que la maquette montre.
/// 2. **Les résumés.** Aucun rapport n'est semé, donc `Meeting.shortSummary`
///    est vide et l'historique retombe sur sa reconstruction
///    (`moral « Bien » · <sujet>`). La capture écrit quatre phrases précises.
///
/// Extension et non modification de `RefonteDemoSeed.swift`, comme les lots 5,
/// 6 et 10 : ce fichier appartient au lot 1 et sert la recette de tous.
@MainActor
extension RefonteDemoSeed {

    private static var lot12Day: TimeInterval { 86_400 }

    /// Cadence du fil, en jours (`Collaborator.oneToOneCadence == .bimensuelle`).
    private static let lot12CadenceDays = 14

    /// Les quatre lignes d'`HISTORIQUE` de la capture 2b, de la plus récente à
    /// la plus ancienne. La clé est le décalage en séances depuis la dernière :
    /// 1 = le 21 août, 2 = le 24 juillet, 3 = le 10 juillet, 4 = le 26 juin.
    static let lot12HistorySummaries: [(sessionsBack: Int, summary: String)] = [
        (1, "Nexus repris · moral « Bien » · astreinte évoquée"),
        (2, "Charge signalée une 1re fois · grille d'astreinte promise"),
        (3, "Souhait de mobilité archi formulé"),
        (4, "Objectifs S2 posés")
    ]

    /// Sème les deux fils 1:1 du lot 10, puis complète le fil manager de ce que
    /// la capture 2b affiche en plus.
    ///
    /// Idempotent : les résumés sont réécrits à l'identique, pas ajoutés.
    @discardableResult
    static func seedLot12(in context: ModelContext)
        -> (manager: OneOnOneThread, collaborator: OneOnOneThread) {
        let fils = seedOneOnOneThreads(in: context)
        alignLot12SessionDates(fils.manager)
        seedLot12HistorySummaries(fils.manager, in: context)
        try? context.save()
        return fils
    }

    /// Recale les dates du fil manager sur celles de la capture : cadence de
    /// quinze jours, **sauf** un mois entre le 24 juillet et le 21 août.
    ///
    /// Idempotent **par construction** : les dates sont *assignées* depuis le
    /// 4 septembre, jamais décalées. Un décalage relatif appliqué deux fois
    /// reculerait tout le fil d'un mois, et le semis se clique deux fois.
    private static func alignLot12SessionDates(_ fil: OneOnOneThread) {
        let seances = OneOnOneThreadStore.allMeetings(of: fil)
        guard seances.count >= 3 else { return }
        let dernier = seances.count - 1

        for (index, seance) in seances.enumerated() {
            let reculs = dernier - index
            // Les deux dernières séances gardent la cadence nominale ; tout ce
            // qui précède recule d'une période de plus — c'est le trou d'août.
            let periodes = reculs <= 1 ? reculs : reculs + 1
            seance.date = oneOnOneSeedDate
                .addingTimeInterval(-Double(periodes * lot12CadenceDays) * lot12Day)
        }

        // Un relevé d'humeur est daté de **sa** séance (`MoodTrend.record`) :
        // déplacer la séance sans le relevé désordonnerait l'histogramme, qui
        // se trie sur `recordedAt`.
        for relevee in fil.moodEntries {
            guard let seance = relevee.meeting else { continue }
            relevee.recordedAt = seance.date
        }
    }

    private static func seedLot12HistorySummaries(_ fil: OneOnOneThread,
                                                  in context: ModelContext) {
        let seances = OneOnOneThreadStore.allMeetings(of: fil)
        guard !seances.isEmpty else { return }
        for ligne in lot12HistorySummaries {
            let index = seances.count - 1 - ligne.sessionsBack
            guard seances.indices.contains(index) else { continue }
            // `shortSummary` et non `summary` : c'est le champ que la carte
            // `HISTORIQUE` lit (une ligne), et écrire un rapport complet ferait
            // apparaître un espace `Rapport` rempli là où la maquette n'en
            // montre pas.
            seances[index].shortSummary = ligne.summary
        }
    }
}
