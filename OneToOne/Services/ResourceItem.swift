import Foundation

/// Une ligne du tiroir Ressources, quelle que soit sa provenance.
///
/// Trois sources alimentent le même tiroir (spec §4.1) et n'ont **aucun**
/// modèle commun en base : `MeetingAttachment` (pièces de la séance et liens
/// collés), `ProjectAttachment` (pièces de la fiche projet, en lecture) et
/// `SlideCapture` (captures d'écran de la séance). Sans cet adaptateur, chaque
/// vignette devrait savoir de quel type elle vient, et les quatre filtres de la
/// capture `3a-tiroir-ressources.png` deviendraient trois listes juxtaposées.
///
/// **Structure de valeur, construite par des fonctions pures** : aucune vue ne
/// lit un `@Model` directement, et les filtres comme les compteurs se testent
/// sans base ni écran.
struct ResourceItem: Identifiable, Hashable, Sendable {

    /// Nature de la ressource (spec §1.3 : `kind file/link/capture`). Elle
    /// décide de l'action principale de la vignette et de son aperçu.
    enum Nature: String, Hashable, Sendable {
        /// Un fichier, copié dans la séance ou dans le projet.
        case fichier
        /// Une URL collée. Aucun fichier, aucune requête réseau.
        case lien
        /// Une capture d'écran de la séance, horodatée sur l'axe temps.
        case capture
    }

    /// D'où vient la ligne. Portée pour que les actions sachent quoi écrire :
    /// seule une pièce de séance est épinglable et citable.
    enum Origin: Hashable, Sendable {
        case pieceDeSeance(UUID)
        case pieceDeProjet(UUID)
        case captureDeSeance(UUID)
    }

    var id: UUID
    var origin: Origin
    /// Nom affiché, en ellipsis dans la vignette.
    var name: String
    /// Catégorie `AttachmentCopyPolicy` (`pdf`, `xlsx`, `image`, `link`…).
    var kind: String
    var nature: Nature
    var scope: AttachmentScope
    /// Qui l'a déposée, en clair. Vide = mention omise.
    var addedByName: String
    var addedAt: Date
    /// Poids en octets. `0` = inconnu, la mention est alors omise.
    var byteCount: Int
    /// Chemin du fichier, ou l'URL pour un lien.
    var path: String
    /// Instant d'épinglage sur l'axe temps de la séance. `nil` = non épinglée.
    ///
    /// Pour une **capture**, c'est son propre `t` : une capture prise pendant
    /// la séance est ancrée dans le temps par construction, elle n'a pas besoin
    /// qu'on l'épingle une seconde fois.
    var pinnedAtT: Double?
    var citationCount: Int
    /// Le fichier a disparu (jamais vrai pour un lien).
    var isOrphan: Bool

    // MARK: - Dérivés d'affichage

    /// Le badge de la vignette (`XLS`, `PDF`, `PNG`, `URL`…).
    var badge: String { AttachmentCopyPolicy.badge(forKind: kind, fileName: name) }

    /// Le ton du fond de l'icône 34 × 40.
    var badgeTone: AttachmentCopyPolicy.BadgeTone { AttachmentCopyPolicy.badgeTone(forKind: kind) }

    /// Seule une pièce de séance porte `pinnedAtT` et `citationCount` : les
    /// pièces du projet sont en lecture (spec §4.1), et une capture est déjà
    /// horodatée.
    var isPinnable: Bool {
        if case .pieceDeSeance = origin { return nature != .lien }
        return false
    }

    /// Un lien s'ouvre, il ne se présente pas : il n'y a rien à afficher aux
    /// participants qu'un navigateur ne ferait mieux.
    var isPresentable: Bool { nature != .lien && !isOrphan }

    var fileURL: URL? {
        guard nature != .lien, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var linkURL: URL? {
        guard nature == .lien else { return nil }
        return URL(string: path)
    }

    /// La ligne de métadonnées de la vignette : `Ajouté par Sylvain · 09:22 ·
    /// 84 Ko` sur la capture. Chaque partie disparaît quand elle est inconnue,
    /// plutôt que d'afficher un séparateur orphelin.
    ///
    /// - Parameter calendar: injecté pour que le test ne dépende ni du fuseau
    ///   ni du réglage régional du poste.
    func metadata(calendar: Calendar = .current) -> String {
        var parties: [String] = []
        if !addedByName.isEmpty { parties.append("Ajouté par \(addedByName)") }
        if nature == .capture, let t = pinnedAtT {
            parties.append("Capture écran · épinglé à \(MeetingPlayhead.mmss(t))")
        } else {
            let h = calendar.component(.hour, from: addedAt)
            let m = calendar.component(.minute, from: addedAt)
            parties.append(String(format: "%02d:%02d", h, m))
        }
        if let poids = AttachmentCopyPolicy.formattedByteCount(byteCount) { parties.append(poids) }
        if citationCount > 0 {
            parties.append(citationCount == 1 ? "cité 1 fois" : "cité \(citationCount) fois")
        }
        return parties.joined(separator: " · ")
    }
}

// MARK: - Filtres

/// Les quatre filtres de l'en-tête du tiroir (spec §4.1, capture 3a).
enum ResourcesFilter: String, CaseIterable, Identifiable, Sendable {
    case seance
    case projet
    case captures
    case liens

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seance:   return "Cette séance"
        case .projet:   return "Le projet"
        case .captures: return "Captures"
        case .liens:    return "Liens"
        }
    }
}

// MARK: - Construction

@MainActor
extension ResourceItem {

    /// Toutes les ressources visibles depuis une réunion, dans l'ordre du
    /// tiroir : les plus récentes d'abord, une pièce épinglée passant devant.
    ///
    /// L'ordre est décidé ici et pas dans la vue : l'ordre d'une relation
    /// SwiftData n'est pas garanti, et deux vues qui trient chacune de leur
    /// côté finissent par trier différemment.
    static func all(for meeting: Meeting) -> [ResourceItem] {
        var lignes = meeting.attachments.compactMap { piece -> ResourceItem? in
            // Le **lot** de captures est un conteneur à chemin virtuel : ses
            // PNG remontent un par un ci-dessous, la ligne elle-même n'est pas
            // une ressource.
            guard piece.kind != AttachmentCopyPolicy.slidesKind else { return nil }
            return ResourceItem(piece)
        }
        lignes += meeting.attachments.flatMap(\.slides).map { ResourceItem($0) }
        lignes += (meeting.project?.attachments ?? []).map { ResourceItem($0) }
        return sorted(lignes)
    }

    /// Tri stable du tiroir : les épinglées d'abord (par timecode croissant,
    /// comme la bande `ÉPINGLÉ DANS LA SÉANCE`), puis les autres du plus récent
    /// au plus ancien, le nom tranchant les ex æquo.
    static func sorted(_ lignes: [ResourceItem]) -> [ResourceItem] {
        lignes.sorted { a, b in
            switch (a.pinnedAtT, b.pinnedAtT) {
            case let (ta?, tb?): if ta != tb { return ta < tb }
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): break
            }
            if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Ce que montre un filtre. Fonction pure : c'est la règle des quatre
    /// onglets, elle se lit d'un coup d'œil.
    static func filtered(_ lignes: [ResourceItem], by filtre: ResourcesFilter) -> [ResourceItem] {
        lignes.filter { ligne in
            switch filtre {
            case .seance:
                // Les liens collés en séance comptent parmi les ressources de
                // la séance : ils y ont été déposés, exactement comme un PDF.
                return ligne.scope == .meeting && ligne.nature != .capture
            case .projet:
                return ligne.scope == .project
            case .captures:
                return ligne.nature == .capture
            case .liens:
                return ligne.nature == .lien
            }
        }
    }

    /// Les deux compteurs de l'en-tête : `4 séance` / `17 projet`.
    ///
    /// Les captures **ne sont pas** comptées dans « séance » : elles ont leur
    /// propre filtre, et la capture 3a annonce `4 séance` pour quatre vignettes
    /// dont aucune n'est un doublon d'une autre ligne.
    static func counts(_ lignes: [ResourceItem]) -> (seance: Int, projet: Int) {
        (filtered(lignes, by: .seance).count, filtered(lignes, by: .projet).count)
    }

    // MARK: - Adaptateurs

    init(_ piece: MeetingAttachment) {
        let nature: Nature = switch piece.kind {
        case AttachmentCopyPolicy.linkKind: .lien
        case AttachmentCopyPolicy.captureKind: .capture
        default: .fichier
        }
        self.init(id: piece.ensuredStableID,
                  origin: .pieceDeSeance(piece.ensuredStableID),
                  name: piece.fileName,
                  kind: piece.kind,
                  nature: nature,
                  scope: piece.scope,
                  addedByName: piece.addedByName,
                  addedAt: piece.importedAt,
                  byteCount: piece.byteCount,
                  path: piece.filePath,
                  pinnedAtT: piece.pinnedAtT,
                  citationCount: piece.citationCount,
                  isOrphan: piece.isOrphan)
    }

    /// Une pièce de la fiche projet. **Lecture seule** dans le tiroir (spec
    /// §4.1) : `scope = .project`, pas d'épinglage, pas de citation.
    /// `ProjectAttachment` n'a pas d'identifiant stable ; l'identité de la
    /// ligne vient de son chemin, qui est unique par construction (le copieur
    /// horodate et déduplique).
    init(_ piece: ProjectAttachment) {
        let taille = (try? FileManager.default.attributesOfItem(atPath: piece.filePath))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
        let identifiant = ResourceItem.derivedID(from: "project:" + piece.filePath)
        self.init(id: identifiant,
                  origin: .pieceDeProjet(identifiant),
                  name: piece.fileName,
                  kind: AttachmentCopyPolicy.kind(
                      forExtension: URL(fileURLWithPath: piece.fileName).pathExtension),
                  nature: .fichier,
                  scope: .project,
                  addedByName: "",
                  addedAt: piece.importedAt,
                  byteCount: taille,
                  path: piece.filePath,
                  pinnedAtT: nil,
                  citationCount: 0,
                  isOrphan: !FileManager.default.fileExists(atPath: piece.filePath))
    }

    /// Une capture d'écran de la séance. Son `t` **est** son épinglage : une
    /// capture prise pendant la séance est ancrée dans le temps par
    /// construction (spec §4.2 : la bande liste ce qui est daté de la séance).
    init(_ capture: SlideCapture) {
        let nom = URL(fileURLWithPath: capture.imagePath).lastPathComponent
        let taille = (try? FileManager.default.attributesOfItem(atPath: capture.imagePath))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
        self.init(id: capture.id,
                  origin: .captureDeSeance(capture.id),
                  name: nom,
                  kind: AttachmentCopyPolicy.captureKind,
                  nature: .capture,
                  scope: .meeting,
                  addedByName: "",
                  addedAt: capture.capturedAt,
                  byteCount: taille,
                  path: capture.imagePath,
                  pinnedAtT: capture.t,
                  citationCount: 0,
                  isOrphan: !FileManager.default.fileExists(atPath: capture.imagePath))
    }

    /// Identifiant déterministe pour les sources qui n'en ont pas
    /// (`ProjectAttachment`). Déterministe et non aléatoire : l'identité d'une
    /// ligne doit survivre à un rafraîchissement de la vue, sinon SwiftUI
    /// remonte la vignette à chaque rendu et l'animation de sélection saute.
    static func derivedID(from clef: String) -> UUID {
        var octets = [UInt8](repeating: 0, count: 16)
        // Somme de contrôle FNV-1a sur 64 bits, dupliquée sur les 16 octets :
        // il ne s'agit pas de sécurité, seulement de stabilité.
        var hash: UInt64 = 0xcbf29ce484222325
        for octet in Array(clef.utf8) {
            hash ^= UInt64(octet)
            hash = hash &* 0x100000001b3
        }
        for i in 0..<8 {
            octets[i] = UInt8((hash >> (8 * UInt64(i))) & 0xff)
            octets[i + 8] = octets[i] ^ 0x5a
        }
        return UUID(uuid: (octets[0], octets[1], octets[2], octets[3],
                           octets[4], octets[5], octets[6], octets[7],
                           octets[8], octets[9], octets[10], octets[11],
                           octets[12], octets[13], octets[14], octets[15]))
    }
}
