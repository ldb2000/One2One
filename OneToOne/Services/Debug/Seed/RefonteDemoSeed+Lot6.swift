import Foundation
import SwiftData

/// Le jeu de démonstration du **lot 6** : les ressources de
/// `3a-tiroir-ressources.png`.
///
/// Dans un fichier d'extension, et **sans toucher** à `RefonteDemoSeed.swift` :
/// trois lots travaillent en parallèle sur la même base, et le fichier
/// principal a déjà été le lieu d'un conflit à l'intégration des lots 2 et 3
/// (cf. `STATUS.md`).
///
/// Les chiffres de la capture sont tenus exactement : **4 séance** — trois
/// fichiers **plus le lien**, ce sont bien les quatre vignettes du filtre
/// `Cette séance` sur la capture —, **17 projet**, **2 épinglées** (`04:12 ·
/// Comptes_GitLab.png` et `12:08 · Chiffrage_Marine_v3`), une pièce citée
/// trois fois.
///
/// Les fichiers sont **réellement créés** sur le disque, sous la racine de
/// stockage de l'application : une vignette qui pointe un fichier absent
/// s'afficherait orpheline, et la recette montrerait quatre invites de
/// reliaison au lieu du tiroir de la capture.
@MainActor
extension RefonteDemoSeed {

    /// Les trois **fichiers** de la séance, dans l'ordre de la capture. La
    /// quatrième vignette du filtre `Cette séance` est le lien ci-dessous.
    ///
    /// - `pinT` : timecode d'épinglage, `nil` = non épinglée.
    /// - `citations` : `citationCount`, pour la mention « cité 3 fois ».
    static var lot6SessionFiles: [(nom: String, kind: String, depose: String,
                                   octets: Int, pinT: Double?, citations: Int)] {
        [
            // La pièce à l'écran de la capture : 84 Ko, ajoutée par Sylvain à
            // 09:22, épinglée à 12:08.
            ("Chiffrage_Marine_v3.xlsx", "xlsx", "Sylvain", 86_016, 728, 0),
            // « Capture écran · épinglé à 04:12 » — une image déposée, pas une
            // `SlideCapture` : la capture 3a lui donne le bouton `Présenter`,
            // donc elle est présentable, donc c'est une pièce.
            ("Comptes_GitLab.png", "image", "Sylvain", 41_353, 252, 0),
            // « Repris du projet · cité 3 fois ».
            ("Devis_partenaire_40k.pdf", "pdf", "", 218_432, nil, 3)
        ]
    }

    /// Le lien collé par Yann à 11:55.
    static let lot6Link = (titre: "Board GitLab — épiques migration",
                           url: "https://gitlab.example.com/groups/sd-cicd/-/boards/12",
                           depose: "Yann")

    /// Les 17 documents du projet, ceux du compteur `17 projet`.
    static var lot6ProjectFiles: [String] {
        [
            "Cadrage_migration_CI-CD.pdf",
            "Architecture_cible_v4.pdf",
            "Contrat_partenaire_signe.pdf",
            "Facture_40k_juillet.pdf",
            "Planning_T3_2026.xlsx",
            "Matrice_droits_GitLab.xlsx",
            "Inventaire_pipelines.xlsx",
            "Comite_pilotage_juin.pptx",
            "Comite_pilotage_juillet.pptx",
            "Formation_admin_programme.docx",
            "Prerequis_synchronisation.docx",
            "Compte_rendu_kickoff.docx",
            "Risques_registre.xlsx",
            "Recette_criteres.md",
            "Runbook_bascule.md",
            "Schema_reseau.png",
            "Devis_initial_partenaire.pdf"
        ]
    }

    /// Sème les ressources du lot 6 sur la réunion de la capture.
    ///
    /// **Idempotent** : appelé après `RefonteDemoSeed.seed(in:)`, il ne fait
    /// rien si la réunion porte déjà ses pièces. Une commande de menu peut
    /// être cliquée deux fois.
    ///
    /// - Parameter base: racine de stockage ; paramétrée pour les tests.
    @discardableResult
    static func seedLot6(in context: ModelContext,
                         base: URL = AttachmentImporter.baseDirectory()) -> Meeting {
        let reunion = seed(in: context)
        guard reunion.attachments.isEmpty else { return reunion }

        let dossier = base.appending(
            path: AttachmentCopyPolicy.documentsSubpath(meetingStableID: reunion.ensuredStableID),
            directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)

        // 09:22 pour la première pièce, comme la capture ; les suivantes
        // s'échelonnent dans la matinée.
        let matin = reunion.date.addingTimeInterval(7 * 60)  // 09:22 pour une séance à 09:15

        for (index, fichier) in lot6SessionFiles.enumerated() {
            let destination = dossier.appending(
                path: AttachmentCopyPolicy.destinationFileName(for: fichier.nom, at: matin))
            écrireFactice(octets: fichier.octets, à: destination)

            let piece = MeetingAttachment(url: destination,
                                          kind: fichier.kind)
            piece.fileName = fichier.nom
            piece.bookmarkData = nil
            piece.scope = .meeting
            piece.mimeType = AttachmentCopyPolicy.mimeType(
                forExtension: URL(fileURLWithPath: fichier.nom).pathExtension)
            piece.byteCount = fichier.octets
            piece.addedByName = fichier.depose
            piece.importedAt = matin.addingTimeInterval(Double(index) * 600)
            piece.pinnedAtT = fichier.pinT
            piece.citationCount = fichier.citations
            piece.extractedText = texteFactice(pour: fichier.nom)
            _ = piece.ensuredStableID
            piece.meeting = reunion
            context.insert(piece)
        }

        if let lien = AttachmentLinkImporter.parse(lot6Link.url) {
            let piece = AttachmentLinkImporter.attach(lien, to: reunion, in: context)
            // Le titre de la capture est humain : aucune requête réseau ne
            // peut le deviner, on le pose donc à la main pour la recette.
            piece.fileName = lot6Link.titre
            piece.addedByName = lot6Link.depose
            piece.importedAt = matin.addingTimeInterval(2 * 3_600 + 33 * 60)  // 11:55
        }

        if let projet = reunion.project, projet.attachments.isEmpty {
            let dossierProjet = base.appending(path: "projects/\(projet.code)",
                                               directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dossierProjet,
                                                     withIntermediateDirectories: true)
            for (index, nom) in lot6ProjectFiles.enumerated() {
                let destination = dossierProjet.appending(
                    path: AttachmentCopyPolicy.destinationFileName(
                        for: nom, at: reunion.date.addingTimeInterval(Double(-index) * 86_400)))
                écrireFactice(octets: 12_000 + index * 3_100, à: destination)
                let piece = ProjectAttachment(
                    url: destination,
                    category: "Document",
                    importedAt: reunion.date.addingTimeInterval(Double(-index) * 86_400))
                piece.fileName = nom
                piece.bookmarkData = nil
                piece.project = projet
                context.insert(piece)
            }
        }

        // Les deux cases par défaut du pied, explicitement : la recette doit
        // montrer `✓ Joindre les 2 pièces épinglées` et `✓ Donner l'accès aux
        // 6 participants`, `○ Verser dans les documents du projet`.
        reunion.reportAttachmentOptions = .defaults

        try? context.save()
        return reunion
    }

    /// Un fichier factice de la taille annoncée. Le contenu n'a pas
    /// d'importance — ce qui compte, c'est que la vignette ne soit pas
    /// orpheline et que le poids affiché soit celui de la capture.
    private static func écrireFactice(octets: Int, à url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? Data(repeating: 0x20, count: max(1, octets)).write(to: url)
    }

    /// Un peu de texte extrait, pour que l'assistant ait de quoi répondre à
    /// « Résumer le chiffrage v3 » pendant la recette.
    private static func texteFactice(pour nom: String) -> String {
        switch nom {
        case "Chiffrage_Marine_v3.xlsx":
            return """
            Chiffrage du reste à faire — version 3. Lot 1 migration des pipelines : 8 j-h. \
            Lot 2 reprise des droits GitLab : 3 j-h. Lot 3 formation Admin : 5 j-h. \
            Total 21 000 € à confirmer avant le 11 septembre. 40 000 € déjà facturés.
            """
        case "Devis_partenaire_40k.pdf":
            return """
            Devis partenaire — 40 000 € pour la migration complète, signé en juin. \
            Aucun livrable associé à ce jour.
            """
        default:
            return ""
        }
    }
}
