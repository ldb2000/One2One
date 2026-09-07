import Foundation

/// `Tout exporter` de l'encart de clôture de 6b : **un dossier**, une image et
/// une scène par planche, et un `index.md` qui les remet dans l'ordre du temps
/// (spec §7.3).
///
/// L'image exportée est la **vignette déjà sur disque** (`Board.thumbPath`),
/// pas un rendu du moteur : exporter les 40 planches d'une séance en passant
/// par le pont demanderait de les charger une par une dans le `WKWebView`, donc
/// de reconstruire 40 fois une scène pour un fichier de secours. La vignette est
/// régénérée à chaque changement de planche (spec §7.4) : elle est à jour, et
/// l'écran force celle de la planche affichée juste avant d'exporter.
///
/// `.drawio` **n'est pas produit** : hors v1 (décision D6 du programme).
extension WorkshopExport {

    /// Ce qu'un export a réellement écrit. Les comptes sont ceux des fichiers
    /// **présents**, pas des planches : une planche jamais dessinée n'a pas de
    /// vignette, et le dire vaut mieux que promettre une image absente.
    struct BundleSummary: Equatable, Sendable {
        var imageCount: Int
        var sceneCount: Int
        var folder: URL
        var indexPath: URL
    }

    /// Nom du dossier : `<titre assaini> — 2026-09-04`. La date en ISO parce
    /// qu'un dossier se trie par son nom.
    static func folderName(meetingTitle: String, date: Date) -> String {
        let base = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titre = base.isEmpty ? "Atelier" : sanitized(base)
        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "en_US_POSIX")
        formateur.dateFormat = "yyyy-MM-dd"
        return "\(titre) — \(formateur.string(from: date))"
    }

    /// Le `index.md` : la frise, en markdown.
    ///
    /// - Parameter imageNames: nom de fichier de l'image, par identifiant de
    ///   ligne (`WorkshopTimelineItem.id`). Une ligne absente de la table n'a
    ///   pas d'image et n'en affiche donc pas — un `![]()` cassé dans un
    ///   markdown d'export est pire que rien.
    @MainActor
    static func indexMarkdown(meetingTitle: String,
                              rows: [WorkshopTimelineItem],
                              imageNames: [String: String]) -> String {
        var lignes: [String] = ["# \(meetingTitle)", ""]
        if rows.isEmpty {
            lignes.append(WorkshopTimelineModel.emptyInvite)
            return lignes.joined(separator: "\n") + "\n"
        }
        lignes.append("\(rows.count) élément(s) produit(s), dans l'ordre du temps.")
        lignes.append("")
        for ligne in rows {
            lignes.append("## \(MeetingPlayhead.mmss(ligne.t)) · \(ligne.footer) · \(ligne.trailing)")
            lignes.append("")
            if !ligne.caption.isEmpty {
                lignes.append(ligne.caption)
                lignes.append("")
            }
            if let image = imageNames[ligne.id] {
                lignes.append("![\(ligne.title)](\(image))")
                lignes.append("")
            }
        }
        return lignes.joined(separator: "\n")
    }

    /// Écrit le dossier d'export sous `parent`.
    ///
    /// N'écrit **rien** en base et ne lève que sur une erreur de système de
    /// fichiers : une planche sans vignette ou sans scène est sautée, pas
    /// fatale.
    @MainActor
    @discardableResult
    static func exportAll(meeting: Meeting,
                          store: BoardStore,
                          into parent: URL) throws -> BundleSummary {
        let dossier = parent.appendingPathComponent(
            folderName(meetingTitle: meeting.title, date: meeting.date), isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let lignes = WorkshopTimelineModel.rows(for: meeting)
        let planchesParID = Dictionary(
            BoardOrdering.sorted(meeting.boards).map { ("board-\($0.ensuredStableID.uuidString)", $0) },
            uniquingKeysWith: { premiere, _ in premiere })

        var imageNames: [String: String] = [:]
        var images = 0
        var scenes = 0
        var rang = 0

        for ligne in lignes {
            guard ligne.nature == .board, let planche = planchesParID[ligne.id] else { continue }
            rang += 1
            let base = String(format: "%02d-%@", rang, sanitized(ligne.title))

            // La scène : le format de réouverture. Une planche jamais dessinée
            // exporte une scène vide plutôt que rien — le dossier doit
            // refléter la séance, trous compris.
            let scene = store.loadScene(board: planche, meeting: meeting) ?? BoardScene.empty
            let cible = dossier.appendingPathComponent("\(base).\(BoardStore.sceneExtension)")
            try Data(scene.utf8).write(to: cible, options: .atomic)
            scenes += 1

            // L'image : la vignette déjà sur disque, quand il y en a une.
            if let vignette = store.thumbnailData(board: planche, meeting: meeting) {
                let nom = "\(base).png"
                try vignette.write(to: dossier.appendingPathComponent(nom), options: .atomic)
                imageNames[ligne.id] = nom
                images += 1
            }
        }

        let index = dossier.appendingPathComponent("index.md")
        let markdown = indexMarkdown(meetingTitle: meeting.title,
                                     rows: lignes,
                                     imageNames: imageNames)
        try Data(markdown.utf8).write(to: index, options: .atomic)

        return BundleSummary(imageCount: images, sceneCount: scenes,
                             folder: dossier, indexPath: index)
    }
}
