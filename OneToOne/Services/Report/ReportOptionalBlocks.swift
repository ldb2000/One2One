import Foundation
import SwiftData

/// Les cinq blocs optionnels des gabarits de rapport (spec §8 : « les templates
/// existants restent ; ils gagnent des blocs optionnels — pièces épinglées,
/// captures jointes, planches d'atelier, engagements réciproques (1:1), mises à
/// jour de fiche projet acceptées »).
///
/// **Une** sélection, **deux** rendus. La variable `{{…}}` injecte du markdown
/// dans le prompt pour que le modèle sache citer ; le bloc HTML est une annexe
/// déterministe du rapport, écrite sans lui. Un seul rendu n'aurait pas suffi :
/// un rapport dont les pièces ne figurent que si le modèle a bien voulu les
/// reprendre ne satisfait pas le critère n° 3 du chantier 3, qui demande
/// qu'une pièce épinglée soit citée **automatiquement**.
///
/// Les collecteurs sont `@MainActor` (ils lisent des `@Model`) ; les rendus
/// sont `nonisolated` et purs, ce qui les rend vérifiables sans base.
@MainActor
enum ReportOptionalBlocks {

    // MARK: - Pièces épinglées

    struct PinnedPiece: Equatable {
        var t: Double
        var name: String
        /// Page citée, quand la puce du lot 6 en mentionne une.
        var page: Int?
        var stableID: UUID?
    }

    nonisolated static let pinnedTitle = "Pièces épinglées"
    nonisolated static let pinnedEmptyInvite = "Aucune pièce épinglée — épinglez depuis Ressources."

    /// Les pièces `pinnedAtT != nil`, dans l'ordre du temps.
    ///
    /// `Meeting.pinnedAttachments` (lot 6) est la source de l'ordre : le
    /// dupliquer ici aurait fait deux tris à tenir en phase, alors que le lot 6
    /// l'a justement exposé « parce que le bloc de rapport du lot 15 lira la
    /// même liste ».
    static func pinnedPieces(of meeting: Meeting) -> [PinnedPiece] {
        meeting.pinnedAttachments.map { piece in
            PinnedPiece(t: piece.pinnedAtT ?? 0,
                        name: piece.fileName,
                        page: citedPage(of: piece, in: meeting),
                        stableID: piece.stableID)
        }
    }

    private static let pageMotif = try! NSRegularExpression(pattern: #"·\s*p\.(\d+)"#)

    /// La page citée dans la puce `◫ <nom> · p.n` que le lot 6 écrit dans la
    /// note. Elle n'est pas persistée sur la pièce, et lui ajouter une colonne
    /// pour ça serait inventer une vérité : une pièce n'a pas « une » page, on
    /// en a cité une à un moment donné. On relit donc la note qui la cite.
    private static func citedPage(of piece: MeetingAttachment, in meeting: Meeting) -> Int? {
        guard let cible = piece.stableID else { return nil }
        let notes = meeting.timedNotes
            .filter { $0.sourceRef?.stableID == cible }
            .sorted { $0.t < $1.t }
        for note in notes {
            let ns = note.text as NSString
            guard let m = pageMotif.firstMatch(in: note.text,
                                               range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 2,
                  let page = Int(ns.substring(with: m.range(at: 1))), page > 0
            else { continue }
            return page
        }
        return nil
    }

    /// `- 04:12 · Chiffrage_Marine_v3.xlsx · p.2`
    nonisolated static func pinnedMarkdown(_ pieces: [PinnedPiece]) -> String {
        guard !pieces.isEmpty else { return "" }
        return pieces.map { piece in
            var ligne = "- \(MeetingPlayhead.mmss(piece.t)) · \(piece.name)"
            if let page = piece.page { ligne += " · p.\(page)" }
            return ligne
        }.joined(separator: "\n")
    }

    nonisolated static func pinnedHTML(_ pieces: [PinnedPiece]) -> String {
        guard !pieces.isEmpty else { return "" }
        var html = "<h2>\(pinnedTitle)</h2>\n<ul>\n"
        for piece in pieces {
            var ligne = "<li><code>\(MeetingPlayhead.mmss(piece.t))</code> \(escape(piece.name))"
            if let page = piece.page { ligne += " · p.\(page)" }
            html += ligne + "</li>\n"
        }
        html += "</ul>\n"
        return html
    }

    // MARK: - Captures jointes

    struct CaptureEntry: Equatable {
        /// `nil` pour une capture prise hors enregistrement. Le lot 7 refuse de
        /// lui coller `00:00`, qui désignerait un instant où rien ne s'est
        /// passé ; le rapport tient la même ligne.
        var t: Double?
        var index: Int
        var firstOCRLine: String
        var imagePath: String
    }

    nonisolated static let capturesTitle = "Captures jointes"
    nonisolated static let capturesEmptyInvite =
        "Aucune capture jointe — cochez « Joindre au rapport » dans la bande de captures."

    /// Les captures cochées `includeInReport`, dans l'ordre du temps puis de
    /// l'index (une capture sans `t` passe après celles qui en ont un).
    static func captures(of meeting: Meeting) -> [CaptureEntry] {
        meeting.attachments
            .flatMap(\.slides)
            .filter(\.includeInReport)
            .sorted { ($0.t ?? .greatestFiniteMagnitude, $0.index)
                    < ($1.t ?? .greatestFiniteMagnitude, $1.index) }
            .map { capture in
                CaptureEntry(t: capture.t,
                             index: capture.index,
                             firstOCRLine: firstLine(capture.ocrText),
                             imagePath: capture.imagePath)
            }
    }

    nonisolated static func capturesMarkdown(_ entries: [CaptureEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.map { entry in
            var ligne = "- "
            if let t = entry.t { ligne += "\(MeetingPlayhead.mmss(t)) · " }
            ligne += "Capture \(entry.index)"
            if !entry.firstOCRLine.isEmpty { ligne += " · \(entry.firstOCRLine)" }
            return ligne
        }.joined(separator: "\n")
    }

    /// `embedImages` : l'image en annexe, en `data:` URI. L'aperçu la veut ;
    /// l'export mail non — plusieurs centaines de kilooctets de base64 dans un
    /// corps de message ne passent aucun filtre, et l'image y arrive de toute
    /// façon en pièce jointe (`ReportSendPreparation`).
    nonisolated static func capturesHTML(_ entries: [CaptureEntry],
                                         embedImages: Bool) -> String {
        guard !entries.isEmpty else { return "" }
        var html = "<h2>\(capturesTitle)</h2>\n<ul>\n"
        for entry in entries {
            var ligne = "<li>"
            if let t = entry.t { ligne += "<code>\(MeetingPlayhead.mmss(t))</code> " }
            ligne += "Capture \(entry.index)"
            if !entry.firstOCRLine.isEmpty { ligne += " · \(escape(entry.firstOCRLine))" }
            ligne += "</li>\n"
            html += ligne
        }
        html += "</ul>\n"
        if embedImages {
            for entry in entries {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: entry.imagePath))
                else { continue }
                html += "<div><img src=\"data:image/png;base64,\(data.base64EncodedString())\""
                     + " style=\"max-width:100%;border-radius:6px;\" /></div>\n"
            }
        }
        return html
    }

    // MARK: - Planches

    struct BoardEntry: Equatable {
        var t: Double
        var title: String
        var mode: String
        var authors: String
        var thumbPath: String
        /// La légende textuelle de la planche (`BoardCaptionBuilder`, lot 18).
        /// Vide quand la planche n'a pas encore été décrite.
        var caption: String = ""
        /// La case `Joindre au rapport` de l'encart de clôture de 6b (lot 18).
        /// Elle ne décide pas de la **citation** — le rapport dit toujours ce
        /// que la séance a produit — mais de l'**annexe** : l'image de la
        /// planche et le fichier joint au message.
        var includeInReport: Bool = false
        /// Chemin **absolu** de la vignette, résolu par `BoardStore`. Vide
        /// quand la planche n'a pas de vignette : `Board.thumbPath` est
        /// relatif au dossier de la réunion, et le rapport ne sait pas le
        /// résoudre lui-même.
        var thumbAbsolutePath: String = ""
    }

    nonisolated static let boardsTitle = "Planches"
    nonisolated static let boardsEmptyInvite = "Aucune planche — le type Atelier en produit."

    /// Les planches de la séance **dans l'ordre du temps** (critère n° 5 du
    /// chantier 6).
    ///
    /// Le tri porte sur `t` et non sur `index` : ce dernier est un rang
    /// d'affichage que le réordonnancement du dock (lot 16) peut faire diverger
    /// de la chronologie, et l'ordre d'une relation SwiftData n'est de toute
    /// façon pas garanti.
    ///
    /// Depuis le lot 18, l'entrée porte aussi la **légende** de la planche
    /// (`Board.caption`, produite par `BoardCaptionBuilder`), sa case `Joindre
    /// au rapport` et le chemin absolu de sa vignette.
    ///
    /// `store` est injectable : résoudre `Board.thumbPath`, qui est relatif au
    /// dossier de la réunion, demande une racine, et un test ne doit pas lire
    /// le `recordings/` de production.
    static func boards(of meeting: Meeting, store: BoardStore? = nil) -> [BoardEntry] {
        let magasin = store ?? .shared
        let reunion = meeting.ensuredStableID
        return meeting.boards
            .sorted { ($0.t, $0.index) < ($1.t, $1.index) }
            .map { planche in
                let vignette = planche.thumbPath.isEmpty
                    ? ""
                    : magasin.url(meetingStableID: reunion,
                                  relativePath: planche.thumbPath).path
                return BoardEntry(t: planche.t,
                                  title: planche.title,
                                  mode: planche.mode.label,
                                  authors: planche.authorNames,
                                  thumbPath: planche.thumbPath,
                                  caption: planche.caption,
                                  includeInReport: planche.includeInReport,
                                  thumbAbsolutePath: vignette)
            }
    }

    nonisolated static func boardsMarkdown(_ entries: [BoardEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.map { entry in
            let titre = entry.title.isEmpty ? "Planche sans titre" : entry.title
            var ligne = "- \(MeetingPlayhead.mmss(entry.t)) · \(titre) · \(entry.mode)"
            if !entry.authors.isEmpty { ligne += " · \(entry.authors)" }
            // La légende sur une ligne de continuation indentée (lot 18) : le
            // modèle la lit comme faisant partie de la puce, et une planche
            // sans légende ne laisse pas de ligne vide derrière elle.
            if !entry.caption.isEmpty { ligne += "\n  \(entry.caption)" }
            return ligne
        }.joined(separator: "\n")
    }

    /// `embedImages` : la vignette des planches **cochées** en annexe, en
    /// `data:` URI — même arbitrage que pour les captures (l'aperçu la veut,
    /// l'export mail non, l'image y arrive en pièce jointe).
    ///
    /// La citation, elle, ne dépend pas de la case : le rapport d'atelier dit
    /// ce que la séance a produit, et une planche non jointe reste une planche
    /// qui a existé.
    nonisolated static func boardsHTML(_ entries: [BoardEntry],
                                       embedImages: Bool = false) -> String {
        guard !entries.isEmpty else { return "" }
        var html = "<h2>\(boardsTitle)</h2>\n<ul>\n"
        for entry in entries {
            let titre = entry.title.isEmpty ? "Planche sans titre" : entry.title
            var ligne = "<li><code>\(MeetingPlayhead.mmss(entry.t))</code> "
                + "\(escape(titre)) · \(escape(entry.mode))"
            if !entry.authors.isEmpty { ligne += " · \(escape(entry.authors))" }
            if !entry.caption.isEmpty { ligne += "<br/><em>\(escape(entry.caption))</em>" }
            ligne += "</li>\n"
            html += ligne
        }
        html += "</ul>\n"
        if embedImages {
            for entry in entries where entry.includeInReport {
                guard !entry.thumbAbsolutePath.isEmpty,
                      let data = try? Data(contentsOf: URL(fileURLWithPath: entry.thumbAbsolutePath))
                else { continue }
                html += "<div><img src=\"data:image/png;base64,\(data.base64EncodedString())\""
                     + " style=\"max-width:100%;border-radius:6px;\" /></div>\n"
            }
        }
        return html
    }

    // MARK: - Engagements réciproques (1:1)

    struct CommitmentEntry: Equatable {
        /// `Moi` ou le prénom de la personne du fil — les deux groupes de la
        /// colonne de droite de la capture 2a.
        var sideTitle: String
        var text: String
        var dueAt: Date?
        var state: CommitmentState
        var deferrals: Int
    }

    nonisolated static let commitmentsTitle = "Engagements"
    nonisolated static let commitmentsEmptyInvite = "Aucun engagement pris dans cette séance."
    /// Reprise du pied `CLÔTURER` de la capture 2a, à mettre dans le gabarit.
    nonisolated static let commitmentsPrivacyNotice = "Les notes privées ne sont jamais incluses."

    /// Les engagements **pris dans cette séance**, par côté, filtrés par
    /// `ConfidentialityFilter` (spec §8 : la règle n'est jamais réécrite).
    ///
    /// Lecture seule du fil — `OneOnOneThreadStore.existingThread` et non
    /// `thread(for:in:)`, qui en crée un : générer un rapport ne doit rien
    /// écrire en base.
    static func commitments(of meeting: Meeting,
                            in context: ModelContext,
                            audience: Audience) -> [CommitmentEntry] {
        guard let role = OneOnOneThreadStore.role(for: meeting.kind),
              let personne = meeting.participants.first,
              let fil = OneOnOneThreadStore.existingThread(for: personne, role: role,
                                                            in: context)
        else { return [] }
        let cible = meeting.persistentModelID
        var entrees: [CommitmentEntry] = []
        for cote in [OneOnOneSide.manager, .collaborator] {
            let titre = OneOnOneRecapBuilder.sideTitle(cote, in: fil)
            let engagements = fil.commitments
                .filter { $0.ownerSide == cote }
                .filter { $0.promisedInMeeting?.persistentModelID == cible }
                .filter { ConfidentialityFilter.isExportable($0, for: audience) }
                .sorted { ($0.dueAt ?? .distantFuture, $0.text)
                        < ($1.dueAt ?? .distantFuture, $1.text) }
            entrees += engagements.map {
                CommitmentEntry(sideTitle: titre, text: $0.text, dueAt: $0.dueAt,
                                state: $0.state, deferrals: $0.deferralCount)
            }
        }
        return entrees
    }

    nonisolated static func commitmentsMarkdown(_ entries: [CommitmentEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var out: [String] = []
        for titre in orderedSideTitles(entries) {
            out.append("### \(titre)")
            for entry in entries where entry.sideTitle == titre {
                out.append("- \(commitmentLine(entry))")
            }
        }
        return out.joined(separator: "\n")
    }

    nonisolated static func commitmentsHTML(_ entries: [CommitmentEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var html = "<h2>\(commitmentsTitle)</h2>\n"
        for titre in orderedSideTitles(entries) {
            html += "<h3>\(escape(titre))</h3>\n<ul>\n"
            for entry in entries where entry.sideTitle == titre {
                html += "<li>\(escape(commitmentLine(entry)))</li>\n"
            }
            html += "</ul>\n"
        }
        return html
    }

    /// Les titres de côté dans l'ordre de première apparition : `commitments`
    /// les produit déjà manager puis collaborateur, et un tri alphabétique
    /// inverserait ce que la capture 2a montre.
    private nonisolated static func orderedSideTitles(_ entries: [CommitmentEntry]) -> [String] {
        var vus: Set<String> = []
        return entries.compactMap { vus.insert($0.sideTitle).inserted ? $0.sideTitle : nil }
    }

    private nonisolated static func commitmentLine(_ entry: CommitmentEntry) -> String {
        var ligne = "[\(entry.state == .kept ? "x" : " ")] \(entry.text)"
        if let due = entry.dueAt { ligne += " — \(OneOnOneDateFormat.dayMonth(due))" }
        if entry.deferrals > 0 { ligne += " (\(entry.deferrals)× reporté)" }
        if entry.state == .missed { ligne += " — manqué" }
        return ligne
    }

    // MARK: - Mises à jour de fiche projet acceptées

    nonisolated static let cardUpdatesTitle = "Mises à jour de la fiche projet"
    nonisolated static let cardUpdatesEmptyInvite =
        "Aucune mise à jour acceptée — l'assistant propose, vous validez."

    static func cardUpdates(of meeting: Meeting) -> [AcceptedProjectUpdate] {
        meeting.acceptedProjectUpdates
    }

    nonisolated static func cardUpdatesMarkdown(_ updates: [AcceptedProjectUpdate]) -> String {
        guard !updates.isEmpty else { return "" }
        return updates.map { "- \(cardUpdateLine($0))" }.joined(separator: "\n")
    }

    nonisolated static func cardUpdatesHTML(_ updates: [AcceptedProjectUpdate]) -> String {
        guard !updates.isEmpty else { return "" }
        var html = "<h2>\(cardUpdatesTitle)</h2>\n<ul>\n"
        for maj in updates {
            html += "<li>\(escape(cardUpdateLine(maj)))</li>\n"
        }
        html += "</ul>\n"
        return html
    }

    /// `Statut du projet : Vert → Jaune`. La valeur d'avant est rendue `—`
    /// quand elle était vide : une flèche partant de rien se lit mal.
    private nonisolated static func cardUpdateLine(_ maj: AcceptedProjectUpdate) -> String {
        let avant = maj.from.trimmingCharacters(in: .whitespaces)
        return "\(maj.label) : \(avant.isEmpty ? "—" : avant) → \(maj.to)"
    }

    // MARK: - Outils

    nonisolated static func firstLine(_ s: String) -> String {
        s.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Les cinq caractères dangereux en HTML. Dupliqué depuis
    /// `ReportHTMLBuilder.escape`, qui est `private` : l'exposer aurait élargi
    /// la surface d'un type dont le rôle est d'assembler un document, pas de
    /// prêter ses outils.
    nonisolated static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}
