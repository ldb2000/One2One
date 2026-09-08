import Foundation
import SwiftData
import os

private let pinLog = Logger(subsystem: "com.onetoone.app", category: "attachment-pin")

/// Épinglage et citation d'une pièce dans la séance (spec §4.2).
///
/// Épingler, c'est trois écritures d'un seul geste : `pinnedAtT` sur la pièce
/// (elle devient retrouvable par son timecode), une puce `◫ <nom> · p.n` dans
/// la note courante (elle devient lisible dans le fil de la séance), et un
/// repère sur la frise (elle devient cliquable sur l'axe temps). `Citer` fait
/// la même chose **sans** poser `pinnedAtT` : on cite un document en passant,
/// on épingle celui dont on parle.
///
/// La puce vit dans le **texte** de la note, et pas seulement dans son
/// `sourceRef` : la colonne de notes affiche du texte, et une référence
/// invisible n'aide personne à relire la séance. Le `sourceRef` est posé en
/// plus, pour que le clic mène quelque part et que le rapport (lot 15) sache
/// quoi citer.
@MainActor
enum AttachmentPinning {

    /// Le symbole de la puce, tel que la spec l'écrit : `◫`.
    static let chipSymbol = "◫"

    // MARK: - Libellés

    /// Le nom affiché dans la puce : sans son extension. La capture montre
    /// `◫ Chiffrage_Marine_v3 · p.2` pour un fichier nommé
    /// `Chiffrage_Marine_v3.xlsx` — l'extension est du bruit dans une phrase.
    static func displayName(_ fileName: String) -> String {
        let sansExt = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return sansExt.isEmpty ? fileName : sansExt
    }

    /// La puce complète. La page n'est mentionnée que si on en connaît une :
    /// `p.1` sur un document d'une seule page est une précision inutile, et
    /// `p.?` serait un aveu.
    static func chipText(name: String, page: Int? = nil) -> String {
        guard let page, page > 0 else { return "\(chipSymbol) \(displayName(name))" }
        return "\(chipSymbol) \(displayName(name)) · p.\(page)"
    }

    // MARK: - Épingler

    /// Épingle la pièce à l'instant `t` : `pinnedAtT`, puce dans la note
    /// courante, `citationCount` incrémenté.
    ///
    /// Rend la note qui porte la puce, ou `nil` si la pièce n'est pas
    /// épinglable (une pièce de projet, un lien, une capture — déjà horodatée).
    @discardableResult
    static func pin(_ item: ResourceItem,
                    in meeting: Meeting,
                    at t: Double,
                    page: Int? = nil,
                    context: ModelContext) -> MeetingNote? {
        guard item.isPinnable, let piece = attachment(for: item, in: meeting) else { return nil }
        piece.pinnedAtT = t
        let note = insertChip(name: piece.fileName,
                              stableID: piece.ensuredStableID,
                              page: page,
                              in: meeting,
                              at: t,
                              context: context)
        piece.citationCount += 1
        try? context.save()
        pinLog.info("pin: \(piece.fileName, privacy: .public) t=\(t)")
        return note
    }

    /// Retire l'épinglage. La puce déjà écrite dans une note **reste** : elle
    /// décrit ce qui s'est passé en séance, et réécrire l'historique parce
    /// qu'on a changé d'avis sur une épingle serait pire que le désépinglage
    /// lui-même.
    static func unpin(_ item: ResourceItem, in meeting: Meeting, context: ModelContext) {
        guard let piece = attachment(for: item, in: meeting) else { return }
        piece.pinnedAtT = nil
        try? context.save()
    }

    // MARK: - Citer

    /// `Citer` : la même puce, **sans** épingler. Incrémente `citationCount`.
    @discardableResult
    static func cite(_ item: ResourceItem,
                     in meeting: Meeting,
                     at t: Double,
                     page: Int? = nil,
                     context: ModelContext) -> MeetingNote? {
        let stableID: UUID
        let nom = item.name
        switch item.origin {
        case .pieceDeSeance:
            guard let piece = attachment(for: item, in: meeting) else { return nil }
            stableID = piece.ensuredStableID
            piece.citationCount += 1
        case .captureDeSeance(let id):
            stableID = id
        case .pieceDeProjet(let id):
            stableID = id
        }
        let note = insertChip(name: nom, stableID: stableID, page: page,
                              in: meeting, at: t, context: context)
        try? context.save()
        pinLog.info("cite: \(nom, privacy: .public) t=\(t)")
        return note
    }

    // MARK: - La puce dans les notes

    /// Insère la puce dans la **note courante** — la dernière ligne posée à ou
    /// avant `t` — ou crée une ligne si la séance n'en a aucune à cet instant.
    ///
    /// Coller la puce à la note en cours plutôt que d'en créer une nouvelle
    /// reproduit la capture (`Le chiffrage v3 annonce 21 000 € … ◫
    /// Chiffrage_Marine_v3 · p.2`, une seule ligne à `12:08`) et dit la vérité :
    /// la pièce illustre ce qu'on vient d'écrire, elle n'est pas un événement
    /// séparé.
    ///
    /// Idempotent sur la même puce : citer deux fois la même page de la même
    /// pièce dans la même note n'écrit qu'une puce.
    @discardableResult
    private static func insertChip(name: String,
                                   stableID: UUID,
                                   page: Int?,
                                   in meeting: Meeting,
                                   at t: Double,
                                   context: ModelContext) -> MeetingNote? {
        let puce = chipText(name: name, page: page)

        if let courante = currentNote(in: meeting, at: t) {
            guard !courante.text.contains(puce) else { return courante }
            courante.text = courante.text.trimmingCharacters(in: .whitespacesAndNewlines) + "  " + puce
            if courante.sourceRef == nil {
                courante.sourceRef = SourceRef(kind: .capture, stableID: stableID, t: t)
            }
            return courante
        }

        let note = MeetingNote(t: t,
                               text: puce,
                               kind: .note,
                               visibility: MeetingNoteStore.defaultVisibility(for: meeting.kind),
                               orderIndex: MeetingNoteStore.nextOrderIndex(at: t, in: meeting))
        note.sourceRef = SourceRef(kind: .capture, stableID: stableID, t: t)
        context.insert(note)
        note.meeting = meeting
        return note
    }

    /// La note « courante » : la dernière posée à ou avant `t`. `nil` si la
    /// séance n'a encore rien retenu à cet instant.
    static func currentNote(in meeting: Meeting, at t: Double) -> MeetingNote? {
        meeting.timedNotes
            .filter { $0.t <= t }
            .max { ($0.t, $0.orderIndex) < ($1.t, $1.orderIndex) }
    }

    // MARK: - Recherche

    static func attachment(for item: ResourceItem, in meeting: Meeting) -> MeetingAttachment? {
        guard case .pieceDeSeance(let id) = item.origin else { return nil }
        return meeting.attachments.first { $0.stableID == id }
    }
}

extension Meeting {

    /// Les pièces épinglées dans la séance, **triées par timecode**.
    ///
    /// Critère d'acceptation n° 3 du chantier 3 : « une pièce épinglée est
    /// retrouvable par son timecode ». Exposé ici et non calculé dans la vue,
    /// parce que le bloc de rapport du lot 15 lira la même liste — et que
    /// l'ordre d'une relation SwiftData n'est pas garanti.
    var pinnedAttachments: [MeetingAttachment] {
        attachments
            .filter { $0.pinnedAtT != nil }
            .sorted { ($0.pinnedAtT ?? 0, $0.fileName) < ($1.pinnedAtT ?? 0, $1.fileName) }
    }
}
