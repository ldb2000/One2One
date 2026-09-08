import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// Le jeu de démonstration du **lot 7** : les trois captures de
/// `4a-capture-selecteur.png` — `GITLAB · COMPTES 04:12 · auto`,
/// `PLANNING MIGRATION 08:55 · auto`, `CHIFFRAGE V3 12:08 · ⌘⇧S`.
///
/// Dans un fichier d'extension, **sans toucher** à `RefonteDemoSeed.swift` :
/// plusieurs lots travaillent en parallèle sur la même base, et le fichier
/// principal a déjà été le lieu d'un conflit à l'intégration des lots 2 et 3.
///
/// Les PNG sont **réellement écrits** par CoreGraphics : une vignette qui
/// pointe un fichier absent afficherait « Image introuvable », et la recette
/// montrerait trois cadres muets au lieu de la bande de la capture.
@MainActor
extension RefonteDemoSeed {

    /// Les trois captures de la capture 4a, dans l'ordre du temps.
    ///
    /// - `t` : position sur l'axe audio, en secondes (`04:12`, `08:55`, `12:08`).
    /// - `trigger` : `auto` pour les deux premières, `⌘⇧S` pour la dernière.
    /// - `ocr` : le texte extrait, celui qui doit être **cherchable** dans la
    ///   réunion (critère n° 4 du chantier 4).
    static var lot7Captures: [(titre: String, t: Double, trigger: CaptureTrigger, ocr: String)] {
        [
            ("GITLAB · COMPTES", 252, .shareChange,
             "État des comptes GitLab — 34 actifs, 6 à désactiver\nReprise des droits : 3 j-h"),
            ("PLANNING MIGRATION", 535, .shareChange,
             "Planning migration — jalon du 11 septembre\nBascule des pipelines : semaine 38"),
            ("CHIFFRAGE V3", 728, .manual,
             "Reprise AP : 3 j-h · Marine : 21 000 €\nTotal reste à faire : 21 000 € à confirmer")
        ]
    }

    /// Sème les captures du lot 7 sur la réunion de la démonstration.
    ///
    /// **Idempotent** : appelé après `RefonteDemoSeed.seed(in:)`, il ne fait
    /// rien si la réunion porte déjà un lot de captures. Une commande de menu
    /// peut être cliquée deux fois.
    ///
    /// - Parameter base: racine de stockage ; paramétrée pour les tests.
    @discardableResult
    static func seedLot7(in context: ModelContext,
                         base: URL = AttachmentImporter.baseDirectory()) -> Meeting {
        let reunion = seed(in: context)
        let dejaSemee = reunion.attachments.contains {
            $0.kind == AttachmentCopyPolicy.slidesKind
        }
        guard !dejaSemee else { return reunion }

        let dossier = base
            .appending(path: reunion.ensuredStableID.uuidString, directoryHint: .isDirectory)
            .appending(path: "slides", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        let lot = MeetingAttachment(
            url: dossier.appending(path: "captures.slides"),
            kind: AttachmentCopyPolicy.slidesKind)
        lot.fileName = "Captures de la séance"
        lot.bookmarkData = nil
        lot.scope = .meeting
        lot.addedByName = ""
        lot.importedAt = reunion.date
        _ = lot.ensuredStableID
        lot.meeting = reunion
        context.insert(lot)

        for (index, modele) in lot7Captures.enumerated() {
            let numero = index + 1
            let date = reunion.date.addingTimeInterval(modele.t)
            let fichier = dossier.appending(
                path: ScreenCaptureService.fileName(index: numero, date: date))
            écrirePNGFactice(titre: modele.titre, à: fichier)

            let capture = SlideCapture(index: numero, capturedAt: date, imagePath: fichier.path)
            capture.t = modele.t
            capture.trigger = modele.trigger
            // La capture 4a annonce `source Teams` dans l'en-tête de la bande.
            capture.source = .teams
            capture.ocrText = modele.ocr
            capture.attachment = lot
            context.insert(capture)
        }

        // Le texte agrégé du lot, celui qu'indexe `reindexAttachment` : sans
        // lui, l'assistant ne trouverait pas « 21 000 € » pendant la recette.
        lot.extractedText = lot.slides
            .sorted { $0.index < $1.index }
            .map { "--- Capture \($0.index) [\(MeetingPlayhead.mmss($0.t ?? 0))] ---\n\($0.ocrText)" }
            .joined(separator: "\n\n")

        try? context.save()
        return reunion
    }

    /// Un PNG 1 320 × 760 (dix fois la vignette) portant son titre en gros, à
    /// la manière des maquettes : sans image, la bande n'aurait rien à montrer.
    ///
    /// Le texte est dessiné en **rectangles**, pas en glyphes : dessiner du
    /// texte demanderait une fonte résolue, et un semis de démonstration ne
    /// doit pas dépendre de ce qui est installé sur le poste. Le résultat est
    /// une mire reconnaissable, ce qui suffit à distinguer trois vignettes.
    private static func écrirePNGFactice(titre: String, à url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let largeur = 1_320
        let hauteur = 760
        guard let contexte = CGContext(data: nil,
                                       width: largeur,
                                       height: hauteur,
                                       bitsPerComponent: 8,
                                       bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return }

        // Fond papier, comme les captures de la refonte.
        contexte.setFillColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)
        contexte.fill(CGRect(x: 0, y: 0, width: largeur, height: hauteur))

        // Une bande d'en-tête `accent/action`, puis une ligne de « mots » par
        // ligne de contenu : la mire varie avec le titre, donc les trois
        // vignettes ne se ressemblent pas.
        contexte.setFillColor(red: 0.15, green: 0.39, blue: 0.85, alpha: 1)
        contexte.fill(CGRect(x: 0, y: hauteur - 90, width: largeur, height: 90))

        let graine = abs(titre.hashValue)
        contexte.setFillColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1)
        for ligne in 0..<6 {
            let y = hauteur - 190 - ligne * 90
            let mots = 3 + (graine / (ligne + 1)) % 4
            var x = 70
            for mot in 0..<mots {
                let largeurMot = 110 + (graine / (mot + 2)) % 220
                contexte.fill(CGRect(x: x, y: y, width: largeurMot, height: 26))
                x += largeurMot + 40
                if x > largeur - 120 { break }
            }
        }

        guard let image = contexte.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
