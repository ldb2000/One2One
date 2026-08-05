import XCTest
@testable import OneToOne

/// Caractérise `MentionCatalog` : construction des entrées du panneau `@`
/// (candidats + entrée « Créer … » conditionnelle) et le schéma d'URL de
/// mention (`onetoone://collaborator/<uuid>`, aligné sur `MickeyIntegration.
/// callbackScheme`). Logique pure, sans SwiftData ni `NSTextView`.
final class MentionCatalogTests: XCTestCase {

    // MARK: - `rows` : candidats

    func test_rows_returnsCandidatesInOrder() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let marc = MentionCandidate(id: UUID(), name: "Marc Martin", role: "Chef de projet")

        let rows = MentionCatalog.rows(candidates: [marie, marc], query: "mar")

        // Aucune correspondance exacte pour "mar" : l'entrée de création doit
        // suivre les deux candidats, dans l'ordre reçu (le tri est délégué à
        // la closure de recherche, pas à `MentionCatalog`).
        XCTAssertEqual(rows, [.candidate(marie), .candidate(marc), .create("mar")])
    }

    // MARK: - `rows` : entrée « Créer … »

    func test_rows_emptyQuery_neverOffersCreate() {
        // Juste après avoir tapé "@" : la requête est vide, impossible de
        // créer un collaborateur sans nom, même si `candidates` est vide.
        let rows = MentionCatalog.rows(candidates: [], query: "")
        XCTAssertEqual(rows, [])
    }

    func test_rows_blankQuery_neverOffersCreate() {
        // Uniquement des espaces : trimé à vide, même garde que la requête
        // réellement vide.
        let rows = MentionCatalog.rows(candidates: [], query: "   ")
        XCTAssertEqual(rows, [])
    }

    func test_rows_noCandidates_nonEmptyQuery_offersCreate() {
        let rows = MentionCatalog.rows(candidates: [], query: "Nouveau")
        XCTAssertEqual(rows, [.create("Nouveau")])
    }

    /// Le cœur de la garde anti-doublon (point laissé ouvert par la spec,
    /// tranché ici) : taper le nom **exact** d'un collaborateur existant ne
    /// doit jamais proposer d'en créer un doublon.
    func test_rows_exactNameMatch_doesNotOfferCreate() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let rows = MentionCatalog.rows(candidates: [marie], query: "Marie Dupont")
        XCTAssertEqual(rows, [.candidate(marie)])
    }

    /// La comparaison d'exactitude est insensible à la casse et aux accents
    /// (`slashSearchNormalized`, réutilisé du menu `/`) — sans quoi taper
    /// « marie dupont » (minuscules) proposerait à tort un doublon.
    func test_rows_exactNameMatch_isCaseAndAccentInsensitive() {
        let helene = MentionCandidate(id: UUID(), name: "Hélène Noël", role: "Architecte")
        let rows = MentionCatalog.rows(candidates: [helene], query: "helene noel")
        XCTAssertEqual(rows, [.candidate(helene)],
                       "« helene noel » doit être reconnu comme le nom exact de « Hélène Noël »")
    }

    /// Un candidat qui contient la requête sans l'égaler exactement (sous-mot)
    /// ne doit **pas** supprimer l'entrée de création — sans quoi il
    /// deviendrait impossible de créer quelqu'un dont le nom est un sous-mot
    /// d'un collaborateur existant.
    func test_rows_partialMatch_stillOffersCreate() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let rows = MentionCatalog.rows(candidates: [marie], query: "Mari")
        XCTAssertEqual(rows, [.candidate(marie), .create("Mari")])
    }

    /// L'entrée de création porte le texte **tel que tapé**, non trimé —
    /// c'est ce texte qui doit apparaître dans le libellé « Créer "…" » et
    /// être transmis à la closure de création.
    func test_rows_createEntry_carriesTheQueryVerbatim_notTrimmed() {
        let rows = MentionCatalog.rows(candidates: [], query: "  Nouveau  ")
        XCTAssertEqual(rows, [.create("  Nouveau  ")])
    }

    // MARK: - Schéma d'URL de mention

    func test_mentionURL_hasTheExpectedSchemeHostAndPath() {
        let id = UUID()
        let url = MentionCatalog.mentionURL(for: id)
        XCTAssertEqual(url.scheme, "onetoone")
        XCTAssertEqual(url.host, "collaborator")
        XCTAssertEqual(url.path, "/\(id.uuidString)")
    }

    func test_collaboratorID_roundTripsWithMentionURL() {
        let id = UUID()
        let url = MentionCatalog.mentionURL(for: id)
        XCTAssertEqual(MentionCatalog.collaboratorID(from: url), id)
    }

    func test_collaboratorID_wrongScheme_returnsNil() {
        let url = URL(string: "https://collaborator/\(UUID().uuidString)")!
        XCTAssertNil(MentionCatalog.collaboratorID(from: url))
    }

    func test_collaboratorID_wrongHost_returnsNil() {
        // Même schéma que le callback `MickeyIntegration` existant, mais un
        // hôte qui n'est pas celui des mentions.
        let url = URL(string: "onetoone://session-done")!
        XCTAssertNil(MentionCatalog.collaboratorID(from: url))
    }

    func test_collaboratorID_malformedUUID_returnsNil() {
        let url = URL(string: "onetoone://collaborator/pas-un-uuid")!
        XCTAssertNil(MentionCatalog.collaboratorID(from: url))
    }
}
