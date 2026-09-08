import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les cinq blocs optionnels des gabarits (spec §8). Une sélection, deux
/// rendus : le markdown alimente le prompt, le HTML est l'annexe déterministe
/// du rapport — celle qui ne dépend pas de la bonne volonté du modèle.
@Suite("Blocs optionnels du rapport")
@MainActor
struct ReportOptionalBlocksTests {

    private func contexte() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: cfg))
    }

    private func piece(_ nom: String, t: Double?, in reunion: Meeting,
                       _ ctx: ModelContext) -> MeetingAttachment {
        let p = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/\(nom)"))
        p.pinnedAtT = t
        p.meeting = reunion
        ctx.insert(p)
        return p
    }

    // MARK: - Pièces épinglées

    @Test("Les pièces épinglées sortent triées par timecode, les autres pas du tout")
    func pieceEpingleeTrieeParTimecode() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        _ = piece("Annexe_technique.pdf", t: 728, in: reunion, ctx)
        _ = piece("Chiffrage_Marine_v3.xlsx", t: 252, in: reunion, ctx)
        _ = piece("Brouillon.txt", t: nil, in: reunion, ctx)
        try ctx.save()

        let pieces = ReportOptionalBlocks.pinnedPieces(of: reunion)
        #expect(pieces.map(\.name) == ["Chiffrage_Marine_v3.xlsx", "Annexe_technique.pdf"])
        #expect(pieces.map(\.t) == [252, 728])
    }

    /// Critère d'acceptation n° 3 du chantier 3 : « une pièce épinglée est
    /// retrouvable par son timecode et citée automatiquement dans le rapport ».
    @Test("Le markdown cite la pièce avec son timecode et sa page")
    func markdownCiteTimecodeEtPage() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        let p = piece("Chiffrage_Marine_v3.xlsx", t: 252, in: reunion, ctx)
        // La page vit dans la puce `◫ … · p.n` que le lot 6 écrit dans la note
        // qui cite la pièce : c'est là qu'on va la relire, plutôt que d'ajouter
        // une colonne pour une information qui n'existe que par la citation.
        let note = MeetingNote(t: 252,
                               text: "Le chiffrage annonce 21 000 € ◫ Chiffrage_Marine_v3 · p.2")
        note.meeting = reunion
        note.sourceRef = SourceRef(kind: .capture, stableID: p.ensuredStableID, t: 252)
        ctx.insert(note)
        try ctx.save()

        let md = ReportOptionalBlocks.pinnedMarkdown(ReportOptionalBlocks.pinnedPieces(of: reunion))
        #expect(md.contains("04:12"))
        #expect(md.contains("Chiffrage_Marine_v3.xlsx"))
        #expect(md.contains("p.2"))
    }

    @Test("Un bloc vide ne rend rien du tout")
    func blocVideRendVide() {
        #expect(ReportOptionalBlocks.pinnedMarkdown([]).isEmpty)
        #expect(ReportOptionalBlocks.pinnedHTML([]).isEmpty)
    }

    @Test("Le HTML porte le timecode en <code> pour que la citation le trouve")
    func htmlPorteLeTimecodeEnCode() {
        let html = ReportOptionalBlocks.pinnedHTML([
            .init(t: 252, name: "Chiffrage_Marine_v3.xlsx", page: 2, stableID: nil)
        ])
        #expect(html.contains("<code>04:12</code>"))
        #expect(html.contains(ReportOptionalBlocks.pinnedTitle))
        #expect(html.contains("p.2"))
    }

    // MARK: - Captures jointes

    @Test("Seules les captures cochées « Joindre au rapport » entrent dans le bloc")
    func capturesSeulementCochees() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        ctx.insert(reunion)
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"), kind: "slides")
        lot.meeting = reunion
        ctx.insert(lot)

        let cochee = SlideCapture(index: 1, capturedAt: Date(), imagePath: "/tmp/c1.png")
        cochee.t = 305
        cochee.includeInReport = true
        cochee.ocrText = "Architecture cible\nDeux zones réseau"
        cochee.attachment = lot
        let ignoree = SlideCapture(index: 2, capturedAt: Date(), imagePath: "/tmp/c2.png")
        ignoree.t = 400
        ignoree.includeInReport = false
        ignoree.attachment = lot
        ctx.insert(cochee); ctx.insert(ignoree)
        try ctx.save()

        let entrees = ReportOptionalBlocks.captures(of: reunion)
        #expect(entrees.count == 1)
        #expect(entrees[0].firstOCRLine == "Architecture cible")

        let md = ReportOptionalBlocks.capturesMarkdown(entrees)
        #expect(md.contains("05:05"))
        #expect(md.contains("Architecture cible"))
        #expect(!md.contains("Deux zones réseau"))
    }

    @Test("Une capture hors enregistrement n'invente pas de timecode")
    func captureSansTimecode() {
        let md = ReportOptionalBlocks.capturesMarkdown([
            .init(t: nil, index: 3, firstOCRLine: "Sans horloge", imagePath: "/tmp/c3.png")
        ])
        #expect(!md.contains("00:00"))
        #expect(md.contains("Capture 3"))
        #expect(md.contains("Sans horloge"))
    }

    // MARK: - Planches

    /// Critère d'acceptation n° 5 du chantier 6 : « le rapport d'atelier
    /// contient les planches dans l'ordre du temps ». Trois planches insérées à
    /// contretemps : l'ordre d'une relation SwiftData ne garantit rien.
    @Test("Les trois planches sortent dans l'ordre du temps, pas de l'insertion")
    func planchesDansLOrdreDuTemps() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        ctx.insert(reunion)
        for (index, triplet) in [
            ("Zones réseau", 900.0, BoardMode.diagram),
            ("Premier jet", 120.0, BoardMode.sketch),
            ("Notes manuscrites", 450.0, BoardMode.ink)
        ].enumerated() {
            let planche = Board(index: index, title: triplet.0, mode: triplet.2, t: triplet.1,
                                authorNames: "Laurent DEBERTI")
            planche.meeting = reunion
            ctx.insert(planche)
        }
        try ctx.save()

        let entrees = ReportOptionalBlocks.boards(of: reunion)
        #expect(entrees.map(\.title) == ["Premier jet", "Notes manuscrites", "Zones réseau"])
        #expect(entrees.map(\.t) == [120, 450, 900])

        let md = ReportOptionalBlocks.boardsMarkdown(entrees)
        let positions = ["Premier jet", "Notes manuscrites", "Zones réseau"]
            .compactMap { md.range(of: $0)?.lowerBound }
        #expect(positions.count == 3)
        #expect(positions == positions.sorted())
        #expect(md.contains("02:00"))
        #expect(md.contains("Croquis"))
        #expect(md.contains("Laurent DEBERTI"))
    }

    @Test("Sans planche, la variable existe et rend vide")
    func planchesVides() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        ctx.insert(reunion)
        try ctx.save()
        #expect(ReportOptionalBlocks.boards(of: reunion).isEmpty)
        #expect(ReportOptionalBlocks.boardsMarkdown([]).isEmpty)
    }

    // MARK: - Engagements

    @Test("Les engagements sortent par côté, l'engagement privé jamais")
    func engagementsParCoteSansPrive() throws {
        let ctx = try contexte()
        let personne = Collaborator(name: "Marine LEROY")
        ctx.insert(personne)
        let fil = OneOnOneThread(collaborator: personne, myRole: .manager)
        ctx.insert(fil)
        let reunion = Meeting(title: "1:1 Marine", date: Date())
        reunion.kind = .oneToOne
        reunion.participants = [personne]
        ctx.insert(reunion)

        let mien = Commitment(text: "Ouvrir le poste", ownerSide: .manager, visibility: .shared)
        let sien = Commitment(text: "Livrer la maquette", ownerSide: .collaborator,
                              state: .kept, visibility: .shared)
        let manque = Commitment(text: "Relire l'ADR", ownerSide: .collaborator,
                                state: .missed, visibility: .shared)
        let secret = Commitment(text: "SUJET SENSIBLE", ownerSide: .manager, visibility: .private)
        for e in [mien, sien, manque, secret] {
            e.thread = fil
            e.promisedInMeeting = reunion
            ctx.insert(e)
        }
        try ctx.save()

        let entrees = ReportOptionalBlocks.commitments(of: reunion, in: ctx,
                                                        audience: .collaborator)
        #expect(entrees.count == 3)
        #expect(!entrees.contains { $0.text == "SUJET SENSIBLE" })
        #expect(entrees.filter { $0.sideTitle == "Moi" }.count == 1)
        #expect(entrees.filter { $0.sideTitle == "Marine" }.count == 2)

        let md = ReportOptionalBlocks.commitmentsMarkdown(entrees)
        #expect(md.contains("### Moi"))
        #expect(md.contains("### Marine"))
        #expect(md.contains("[x] Livrer la maquette"))
        #expect(md.contains("manqué"))
        #expect(!md.contains("SUJET SENSIBLE"))
    }

    @Test("Hors 1:1, le bloc des engagements est vide")
    func engagementsHors1a1() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "COPIL", date: Date())
        reunion.kind = .project
        ctx.insert(reunion)
        try ctx.save()
        #expect(ReportOptionalBlocks.commitments(of: reunion, in: ctx,
                                                  audience: .projectTeam).isEmpty)
    }

    // MARK: - Mises à jour de fiche projet acceptées

    @Test("Seules les mises à jour acceptées sont tracées et rendues")
    func majFicheProjetAcceptees() throws {
        let ctx = try contexte()
        let projet = Project(code: "P25_110", name: "Marine", domain: "Assurance",
                             phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue Marine", date: Date())
        reunion.project = projet
        ctx.insert(reunion)
        try ctx.save()

        #expect(reunion.acceptedProjectUpdates.isEmpty)

        var brouillon = ProjectCardDraft.snapshot(of: projet)
        let acceptee = ProjectCardUpdate(field: .status, label: "Statut du projet",
                                         current: "Sous contrôle", proposed: "À surveiller",
                                         evidence: "12:08 le chiffrage dérape")
        #expect(ProjectCardSuggestions.accept(acceptee, in: &brouillon))
        ProjectCardSuggestions.recordAcceptance(acceptee, in: reunion)

        // Une proposition non acceptée ne laisse aucune trace.
        let ignoree = ProjectCardUpdate(field: .budgetSpent, label: "Budget consommé",
                                        current: "0", proposed: "21000",
                                        evidence: "12:10")

        #expect(reunion.acceptedProjectUpdates.count == 1)
        let md = ReportOptionalBlocks.cardUpdatesMarkdown(
            ReportOptionalBlocks.cardUpdates(of: reunion))
        #expect(md.contains("Statut du projet"))
        #expect(md.contains("Sous contrôle"))
        #expect(md.contains("À surveiller"))
        #expect(!md.contains(ignoree.displayLabel))
    }

    @Test("Tracer deux fois la même ligne n'écrit qu'une entrée")
    func majFicheProjetIdempotente() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        try ctx.save()
        let maj = ProjectCardUpdate(field: .risk, label: "Risque",
                                    current: "—", proposed: "Dérive de charge",
                                    evidence: "08:00")
        ProjectCardSuggestions.recordAcceptance(maj, in: reunion)
        ProjectCardSuggestions.recordAcceptance(maj, in: reunion)
        #expect(reunion.acceptedProjectUpdates.count == 1)
    }

    // MARK: - Invites de l'espace Rapport

    @Test("Un bloc vide devient une invite, pas une section vide")
    func invitesPlutotQueSectionsVides() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.summary = "Contenu."
        ctx.insert(reunion)
        try ctx.save()

        let invites = MeetingReportSpaceInvites.forMeeting(reunion)
        #expect(invites.contains(ReportOptionalBlocks.pinnedEmptyInvite))
        #expect(invites.contains(ReportOptionalBlocks.capturesEmptyInvite))

        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()
        #expect(!MeetingReportSpaceInvites.forMeeting(reunion)
            .contains(ReportOptionalBlocks.pinnedEmptyInvite))
    }

    @Test("Case décochée, on n'invite pas à épingler")
    func pasDInviteQuandLaCaseEstDecochee() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        var options = reunion.reportAttachmentOptions
        options.attachPinned = false
        reunion.reportAttachmentOptions = options
        ctx.insert(reunion)
        try ctx.save()
        #expect(!MeetingReportSpaceInvites.forMeeting(reunion)
            .contains(ReportOptionalBlocks.pinnedEmptyInvite))
    }
}
