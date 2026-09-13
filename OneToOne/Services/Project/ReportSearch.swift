import Foundation
import SwiftData

/// Un compte rendu qui contient le terme cherché.
///
/// La réunion est désignée par son `PersistentIdentifier` — l'écran la
/// retrouve dans sa propre `@Query` pour l'ouvrir — et par son `stableID`
/// quand elle en a un. `stableID` est optionnel parce qu'un constructeur pur
/// ne peut pas appeler `ensuredStableID`, qui **écrit** dans le store ; c'est
/// `repairStoreIfNeeded()` qui les backfille au lancement (même raison que
/// `PortfolioRow.stableID`).
struct ReportSearchHit: Identifiable, Equatable, Sendable {
    var id: PersistentIdentifier { meetingID }
    let meetingID: PersistentIdentifier
    let stableID: UUID?
    let titre: String
    let date: Date
    /// Le champ où le terme a été trouvé, dans les mots de
    /// `Meeting.textualContent` : « titre », « rapport », « décision »…
    let etiquette: String
    /// Les ±`ReportSearch.rayon` caractères autour de la première occurrence.
    let extrait: String
    /// Le nom du projet portant la réunion, ou `nil`.
    let projet: String?
}

/// Les résultats d'un projet, dans l'ordre de la liste.
struct ReportSearchGroup: Identifiable, Equatable, Sendable {
    var id: String { projet }
    let projet: String
    let resultats: [ReportSearchHit]
}

/// La recherche lexicale dans les comptes rendus (décision **D8**) — le second
/// bras de la palette `⌘K` : « Chercher « x » dans les CR ».
///
/// **Lexicale et synchrone, exprès.** `localizedStandardContains` sur
/// `Meeting.textualContent`, rien d'autre : ni RAG, ni embeddings à la frappe.
/// L'écran est ouvert depuis une palette, sur un terme de trois lettres, et
/// doit répondre dans l'image qui suit. Le pipeline sémantique existe
/// (`EmbeddingService`) et reste à sa place, dans l'assistant.
///
/// **Les mails ne sont pas là.** La maquette écrit « dans les CR et mails » ;
/// Laurent a tranché le 2026-09-09 pour les CR seulement. Les mails viendront
/// dans un chantier ultérieur, sur le même écran
/// (`ProjectMail.subject`/`body`).
///
/// Fonctions pures, testées avant la vue (**D11**) : `ReportSearchView` ne
/// filtre ni ne groupe ni ne découpe d'extrait.
enum ReportSearch {

    // MARK: - Libellés et mesures

    /// L'en-tête de l'écran.
    static let titre = "Recherche dans les CR"

    /// Nombre de caractères conservés de chaque côté de l'occurrence.
    static let rayon = 60

    /// Le groupe des réunions sans projet, toujours rangé en dernier.
    static let sansProjet = "Sans projet"

    /// L'état vide de l'écran.
    static let libelleAucunResultat = "Aucun compte rendu ne contient ce terme."

    /// « 3 réunions · « ged » » — le sous-titre de l'en-tête.
    static func sousTitre(reunions: Int, terme: String) -> String {
        let net = terme.trimmingCharacters(in: .whitespacesAndNewlines)
        // Le français met zéro au singulier : « 0 réunion », « 1 réunion »,
        // « 2 réunions ».
        let mot = reunions <= 1 ? "réunion" : "réunions"
        return "\(reunions) \(mot) · « \(net) »"
    }

    /// Le nombre de réunions que ces groupes totalisent.
    static func nombreDeReunions(_ groupes: [ReportSearchGroup]) -> Int {
        groupes.reduce(0) { $0 + $1.resultats.count }
    }

    // MARK: - Recherche

    /// Les comptes rendus contenant le terme, de la réunion la plus récente à
    /// la plus ancienne.
    ///
    /// **Une réunion, un résultat.** Le premier champ de
    /// `Meeting.textualContent` qui porte le terme donne l'étiquette et
    /// l'extrait ; les suivants ne font pas une seconde ligne. Un compte rendu
    /// qui répète un mot dix fois n'est pas dix résultats.
    ///
    /// **Les notes sont écartées** (`MeetingKind.note`) : une note est une
    /// réunion avec soi-même, pas un compte rendu — la même règle que
    /// `MeetingStatsScope.held` et que le `@Query` de la barre latérale.
    static func resultats(in meetings: [Meeting], query: String) -> [ReportSearchHit] {
        let terme = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terme.isEmpty else { return [] }
        return meetings
            .filter { $0.kind != .note }
            .compactMap { hit($0, terme: terme) }
            .sorted { a, b in
                if a.date != b.date { return a.date > b.date }
                return a.titre.localizedStandardCompare(b.titre) == .orderedAscending
            }
    }

    /// Les mêmes résultats, groupés par projet.
    ///
    /// Les groupes sont rangés par nom de projet, « Sans projet » **en
    /// dernier** : c'est le fourre-tout, il ne doit pas ouvrir la liste.
    static func groupes(in meetings: [Meeting], query: String) -> [ReportSearchGroup] {
        let trouves = resultats(in: meetings, query: query)
        guard !trouves.isEmpty else { return [] }
        let parProjet = Dictionary(grouping: trouves) { $0.projet ?? sansProjet }
        return parProjet
            .map { ReportSearchGroup(projet: $0.key, resultats: $0.value) }
            .sorted { a, b in
                if a.projet == sansProjet { return false }
                if b.projet == sansProjet { return true }
                return a.projet.localizedStandardCompare(b.projet) == .orderedAscending
            }
    }

    // MARK: - Extrait

    /// Les ±`rayon` caractères autour de la première occurrence du terme, sur
    /// une seule ligne, bornés par des ellipses quand le texte est tronqué.
    ///
    /// Le texte est **aplati** d'abord : un `rawTranscript` ou des notes
    /// portent des retours à la ligne et des tabulations, et un extrait à
    /// trois lignes casserait la hauteur de ligne de la liste.
    ///
    /// Le terme introuvable rend le début du texte plutôt que rien : par le
    /// chemin normal le cas ne se produit pas (le résultat n'existe que si le
    /// terme est là), et une ligne muette serait pire qu'un extrait décalé.
    static func extrait(_ texte: String, terme: String, rayon: Int = rayon) -> String {
        let plat = aplati(texte)
        guard !plat.isEmpty else { return "" }
        let net = terme.trimmingCharacters(in: .whitespacesAndNewlines)
        let trouve = net.isEmpty
            ? nil
            : plat.range(of: net, options: [.caseInsensitive, .diacriticInsensitive])
        let plage = trouve ?? plat.startIndex..<plat.startIndex

        let debut = plat.index(plage.lowerBound,
                               offsetBy: -rayon,
                               limitedBy: plat.startIndex) ?? plat.startIndex
        let fin = plat.index(plage.upperBound,
                             offsetBy: rayon,
                             limitedBy: plat.endIndex) ?? plat.endIndex
        var morceau = String(plat[debut..<fin])
        if debut > plat.startIndex { morceau = "…" + morceau }
        if fin < plat.endIndex { morceau += "…" }
        return morceau
    }

    // MARK: - Mécanique

    /// Le premier champ de la réunion qui porte le terme, en résultat.
    private static func hit(_ meeting: Meeting, terme: String) -> ReportSearchHit? {
        for champ in meeting.textualContent {
            guard !champ.text.isEmpty,
                  champ.text.localizedStandardContains(terme) else { continue }
            return ReportSearchHit(meetingID: meeting.persistentModelID,
                                   stableID: meeting.stableID,
                                   titre: meeting.title,
                                   date: meeting.date,
                                   etiquette: champ.label,
                                   extrait: extrait(champ.text, terme: terme),
                                   projet: nomDeProjet(meeting))
        }
        return nil
    }

    /// Le nom du projet, ou `nil` si la réunion n'en porte pas — ou si son nom
    /// est blanc, ce qui ferait un groupe sans titre.
    private static func nomDeProjet(_ meeting: Meeting) -> String? {
        guard let nom = meeting.project?.name.trimmingCharacters(in: .whitespaces),
              !nom.isEmpty
        else { return nil }
        return nom
    }

    /// Espaces, tabulations et retours à la ligne réduits à une espace simple.
    private static func aplati(_ texte: String) -> String {
        texte
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
