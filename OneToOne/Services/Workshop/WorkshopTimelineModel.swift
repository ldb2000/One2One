import Foundation

/// Une ligne de la frise de l'écran 6b : un **élément produit** pendant
/// l'atelier (spec §7.3, capture `6b-atelier-planche-de-seance.png`).
///
/// Une structure de valeurs et non les objets SwiftData eux-mêmes : la vue
/// n'a pas à savoir qu'une capture vit sous un lot de pièces jointes ni qu'une
/// planche porte ses chemins en relatif, et le tri, les libellés et le compte
/// se testent alors sans base ni écran.
struct WorkshopTimelineItem: Identifiable, Equatable, Sendable {

    /// D'où vient la ligne. L'ordre des cas est aussi celui du tri à timecode
    /// égal : la planche est ce que la séance a produit, la capture ce qu'elle
    /// a montré, la pièce ce qu'on y a apporté.
    enum Nature: String, Comparable, Sendable {
        case board
        case capture
        case attachment

        private var rang: Int {
            switch self {
            case .board:      return 0
            case .capture:    return 1
            case .attachment: return 2
            }
        }

        static func < (gauche: Nature, droite: Nature) -> Bool {
            gauche.rang < droite.rang
        }
    }

    /// Identité stable de la ligne, préfixée par sa nature : deux sources
    /// distinctes ne partagent jamais un identifiant.
    var id: String
    var nature: Nature
    /// Instant sur l'axe temps de la réunion, en secondes.
    var t: Double
    /// `Croquis`, `Schéma`, `Manuscrit`, `Capture` ou `Pièce`.
    var typeLabel: String
    var title: String
    /// Ce que le pied affiche à droite : l'auteur, `texte extrait`, `stylet`.
    var trailing: String
    /// Légende textuelle, vide quand la planche n'en a pas encore.
    var caption: String
    /// Chemin de l'aperçu : **relatif** au dossier de la réunion pour une
    /// planche (`BoardStore` le résout), absolu pour une capture ou une pièce.
    var previewPath: String
    /// Le mode, pour la pastille de repli d'une planche sans vignette. `nil`
    /// pour une capture ou une pièce.
    var boardMode: BoardMode?

    /// Le pied de la carte : `Croquis — périmètre actuel`.
    var footer: String { "\(typeLabel) — \(title)" }

    /// Le chemin de l'aperçu est-il relatif à la réunion ?
    var previewIsRelative: Bool { nature == .board }
}

/// La frise de l'écran 6b : la fusion des trois sources d'éléments produits,
/// **dans l'ordre du temps**.
///
/// C'est le critère n° 5 du chantier 6 (« le rapport d'atelier contient les
/// planches dans l'ordre du temps ») réduit à une fonction pure : la vue 6b
/// affiche cette liste, `{{planches}}` la rend, et le test la vérifie sans
/// ouvrir d'écran.
///
/// `@MainActor` parce qu'elle lit des objets SwiftData, pas parce qu'elle
/// touche à l'écran : aucune de ces fonctions ne lit le disque ni n'écrit en
/// base.
@MainActor
enum WorkshopTimelineModel {

    /// Invite d'un atelier qui n'a rien produit — jamais une zone vide
    /// (règle du programme §2.1).
    static let emptyInvite = """
    Aucun élément produit dans cette séance. Les planches, les captures et les \
    pièces de l'atelier apparaissent ici, dans l'ordre du temps.
    """

    /// Longueur maximale du titre déduit d'un texte extrait. Au-delà, ce n'est
    /// plus un titre mais un paragraphe, et le pied de carte le tronquerait.
    static let maxCaptureTitleLength = 60

    // MARK: - Frise

    /// Les éléments produits de la réunion, triés par timecode.
    static func rows(for meeting: Meeting) -> [WorkshopTimelineItem] {
        let lignes = boardRows(for: meeting) + captureRows(for: meeting) + attachmentRows(for: meeting)
        return lignes.sorted { gauche, droite in
            if gauche.t != droite.t { return gauche.t < droite.t }
            if gauche.nature != droite.nature { return gauche.nature < droite.nature }
            return gauche.title.localizedCaseInsensitiveCompare(droite.title) == .orderedAscending
        }
    }

    /// Le compte affiché en en-tête : `9 éléments produits`.
    static func producedCount(for meeting: Meeting) -> Int {
        rows(for: meeting).count
    }

    // MARK: - Les trois sources

    private static func boardRows(for meeting: Meeting) -> [WorkshopTimelineItem] {
        BoardOrdering.sorted(meeting.boards).map { planche in
            let titre = planche.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let auteur = planche.authorNames.trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkshopTimelineItem(
                id: "board-\(planche.ensuredStableID.uuidString)",
                nature: .board,
                t: planche.t,
                typeLabel: planche.mode.label,
                title: titre.isEmpty ? BoardOrdering.defaultTitle(forIndex: planche.index) : titre,
                trailing: auteur.isEmpty ? "—" : auteur,
                caption: planche.caption,
                previewPath: planche.thumbPath,
                boardMode: planche.mode)
        }
    }

    private static func captureRows(for meeting: Meeting) -> [WorkshopTimelineItem] {
        meeting.attachments.flatMap(\.slides).map { capture in
            let texte = capture.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            let instant = capture.t ?? 0
            return WorkshopTimelineItem(
                id: "capture-\(capture.id.uuidString)",
                nature: .capture,
                t: instant,
                typeLabel: "Capture",
                title: captureTitle(ocrText: texte, t: instant),
                trailing: texte.isEmpty ? "sans texte extrait" : "texte extrait",
                caption: texte,
                previewPath: capture.imagePath,
                boardMode: nil)
        }
    }

    /// Les pièces **déposées pendant la séance**. Trois exclusions, chacune
    /// pour une raison :
    /// - le lot `slides` est un **conteneur** de captures, pas une pièce (même
    ///   règle qu'au dock du lot 17) ;
    /// - un lien n'a rien à montrer et n'a pas été produit ;
    /// - une pièce du **projet** existait avant la séance.
    private static func attachmentRows(for meeting: Meeting) -> [WorkshopTimelineItem] {
        meeting.attachments.compactMap { piece -> WorkshopTimelineItem? in
            guard piece.scope == .meeting,
                  piece.kind != AttachmentCopyPolicy.slidesKind,
                  piece.kind != AttachmentCopyPolicy.linkKind
            else { return nil }
            let auteur = piece.addedByName.trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkshopTimelineItem(
                id: "attachment-\(piece.ensuredStableID.uuidString)",
                nature: .attachment,
                t: attachmentT(pinnedAtT: piece.pinnedAtT,
                               importedAt: piece.importedAt,
                               meetingDate: meeting.date,
                               durationSeconds: sessionDuration(of: meeting)),
                typeLabel: "Pièce",
                title: piece.fileName,
                trailing: auteur.isEmpty ? "déposé dans la séance" : auteur,
                caption: "",
                previewPath: piece.filePath,
                boardMode: nil)
        }
    }

    // MARK: - Règles pures

    /// Le timecode d'une pièce. `pinnedAtT` fait loi ; sinon l'écart entre
    /// l'import et le début de la séance, **borné** à la durée de celle-ci.
    ///
    /// Sans cette borne, une pièce importée deux jours après la réunion
    /// s'afficherait à `2880:00` et repousserait la frise entière : une pièce
    /// non épinglée n'a pas de position connue, elle a une position plausible.
    nonisolated static func attachmentT(pinnedAtT: Double?,
                                        importedAt: Date,
                                        meetingDate: Date,
                                        durationSeconds: Int) -> Double {
        if let pinnedAtT { return max(0, pinnedAtT) }
        guard durationSeconds > 0 else { return 0 }
        let ecart = importedAt.timeIntervalSince(meetingDate)
        return min(max(0, ecart), Double(durationSeconds))
    }

    /// Le titre d'une capture : la **tête** de son texte extrait — première
    /// ligne, coupée au premier tiret cadratin. `partage de Cléva — schéma
    /// réseau partagé` donne `partage de Cléva`, comme sur la capture 6b.
    /// Sans texte, son instant : `capture-003.png` ne dit rien.
    nonisolated static func captureTitle(ocrText: String, t: Double) -> String {
        let premiereLigne = ocrText
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let tete = premiereLigne
            .components(separatedBy: " — ")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !tete.isEmpty else { return "Capture \(MeetingPlayhead.mmss(t))" }
        guard tete.count > maxCaptureTitleLength else { return tete }
        return String(tete.prefix(maxCaptureTitleLength)) + "…"
    }

    /// `4 sept. · 1 h 02 · 4 participants · 9 éléments produits`.
    ///
    /// Une durée inconnue est **omise** plutôt qu'affichée « 0 min » : un
    /// atelier qu'on n'a pas enregistré a tout de même une date et des
    /// participants.
    nonisolated static func headerSummary(date: Date,
                                          durationSeconds: Int,
                                          participantCount: Int,
                                          producedCount: Int) -> String {
        var morceaux: [String] = [dateLabel(date)]
        if let duree = durationLabel(durationSeconds) { morceaux.append(duree) }
        morceaux.append(participantCount == 1 ? "1 participant" : "\(participantCount) participants")
        morceaux.append(producedLabel(producedCount))
        return morceaux.joined(separator: " · ")
    }

    /// `4 sept.` — la date courte de la capture, sans l'année (la réunion est
    /// ouverte, on sait quelle année on lit).
    nonisolated static func dateLabel(_ date: Date) -> String {
        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "fr_FR")
        formateur.dateFormat = "d MMM"
        return formateur.string(from: date)
    }

    /// `1 h 02` au-delà de l'heure, `47 min` en dessous, `nil` si inconnue.
    nonisolated static func durationLabel(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(max(1, minutes)) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// `9 éléments produits`, `1 élément produit`, `aucun élément produit`.
    nonisolated static func producedLabel(_ count: Int) -> String {
        switch count {
        case 0:  return "aucun élément produit"
        case 1:  return "1 élément produit"
        default: return "\(count) éléments produits"
        }
    }

    /// La durée de la séance : celle mesurée, à défaut celle de l'audio.
    private static func sessionDuration(of meeting: Meeting) -> Int {
        meeting.meetingDurationSeconds > 0 ? meeting.meetingDurationSeconds : meeting.durationSeconds
    }
}
