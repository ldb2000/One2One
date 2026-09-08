import Foundation
import SwiftData

/// Ce que le lot 17 ajoute au jeu de démonstration de
/// `6a-atelier-planche.png` : les **objets annotés** de la section
/// `SUR CETTE PLANCHE`, un vrai **connecteur lié** sur la planche `Flux réseau`
/// en mode Schéma, des tracés en mode Manuscrit, et les deux lignes de
/// `PIÈCES & CAPTURES` (`PDF Archi_cible_Cléva.pdf · déposé par Yann`,
/// `TEAMS Capture 21:10 · schéma réseau partagé`).
///
/// Une extension séparée, comme `+Lot16` : plusieurs lots sèment la même
/// réunion en parallèle, et modifier le semis d'origine ferait un conflit à
/// chaque rebase.
extension RefonteDemoSeed {

    // MARK: - Scènes du lot 17

    /// La planche active, **annotée** : `Jenkins à décommissionner` en risque,
    /// `Qui porte la bascule ?` en question — les deux lignes de la capture.
    static func workshopAnnotatedTargetScene() -> String {
        BoardScene.scene(
            boxes: [
                .init(x: 60, y: 40, width: 320, height: 100,
                      text: "Runners GitLab\n3 nœuds · autoscale"),
                .init(x: 940, y: 40, width: 290, height: 70,
                      text: "Nexus"),
                .init(x: 490, y: 170, width: 340, height: 100,
                      text: "GitLab auto-hébergé\ngitlab.rb + flux à valider"),
                .init(x: 60, y: 300, width: 320, height: 100,
                      text: "PostgreSQL dédiée\nisolée de la data",
                      stroke: WorkshopPalette.entries[1].hex,
                      background: "#f7faff"),
                .init(x: 940, y: 300, width: 290, height: 100,
                      text: "Jenkins à décommissionner — dépend de la bascule runners",
                      stroke: WorkshopPalette.entries[2].hex,
                      background: "#fbeceb",
                      dashed: true,
                      annotation: .risk),
                .init(x: 490, y: 440, width: 420, height: 90,
                      text: "Qui porte la bascule ? question ouverte",
                      stroke: WorkshopPalette.entries[4].hex,
                      background: "#f9efe0",
                      annotation: .question),
                .init(x: 960, y: 460, width: 200, height: 60,
                      text: "à valider\navec Cléva",
                      stroke: WorkshopPalette.entries[1].hex,
                      freeText: true),
            ],
            connectors: [.init(from: 0, to: 2), .init(from: 3, to: 4)],
            seed: 3)
    }

    /// `Flux réseau`, en mode **Schéma** : deux boîtes bleues et leurs
    /// connecteurs liés — de quoi vérifier que `startBinding`/`endBinding`
    /// survivent à un aller-retour sur disque.
    static func workshopDiagramScene() -> String {
        let bleu = WorkshopPalette.entries[1].hex
        return BoardScene.scene(
            boxes: [
                .init(x: 60, y: 60, width: 280, height: 80, text: "DMZ",
                      stroke: bleu, background: "#f7faff"),
                .init(x: 480, y: 60, width: 280, height: 80, text: "Zone applicative",
                      stroke: bleu, background: "#f7faff"),
                .init(x: 270, y: 260, width: 280, height: 80, text: "Zone données",
                      stroke: WorkshopPalette.entries[3].hex),
            ],
            connectors: [.init(from: 0, to: 1, stroke: bleu),
                         .init(from: 1, to: 2, stroke: bleu)],
            seed: 2)
    }

    /// `Notes de Patrice`, en mode **Manuscrit** : des tracés `freedraw` avec
    /// leurs pressions, comme un stylet en produit.
    static func workshopInkScene() -> String {
        let elements: [[String: Any]] = [
            inkStroke(id: "one2one-4-i0", x: 80, y: 90,
                      points: [[0, 0], [40, -12], [90, 6], [150, -18], [210, 4], [260, -10]]),
            inkStroke(id: "one2one-4-i1", x: 80, y: 200,
                      points: [[0, 0], [50, 14], [110, -8], [160, 10], [220, -6]]),
            inkStroke(id: "one2one-4-i2", x: 90, y: 320,
                      points: [[0, 0], [30, 20], [60, -4], [95, 16]]),
        ]
        let scene: [String: Any] = [
            "type": "excalidraw",
            "version": 2,
            "source": "OneToOne",
            "elements": elements,
            "appState": ["viewBackgroundColor": "transparent", "gridSize": NSNull()],
            "files": [String: Any](),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys]),
              let texte = String(data: data, encoding: .utf8)
        else { return BoardScene.empty }
        return texte
    }

    /// Un tracé à main levée, pressions comprises. `simulatePressure = false` :
    /// c'est ce que pose le mode Manuscrit quand une tablette a dessiné, et le
    /// semis doit produire une planche indiscernable d'une vraie.
    private static func inkStroke(id: String,
                                  x: Double,
                                  y: Double,
                                  points: [[Double]]) -> [String: Any] {
        let largeur = points.map { $0[0] }.max() ?? 0
        let hauteur = (points.map { $0[1] }.max() ?? 0) - (points.map { $0[1] }.min() ?? 0)
        // Une pression qui monte puis retombe : le geste d'un trait posé.
        let pressures = points.enumerated().map { index, _ -> Double in
            let position = Double(index) / Double(max(1, points.count - 1))
            return 0.25 + 0.6 * sin(position * .pi)
        }
        return [
            "id": id,
            "type": "freedraw",
            "x": x, "y": y,
            "width": largeur, "height": max(1, hauteur),
            "angle": 0,
            "strokeColor": WorkshopPalette.entries[1].hex,
            "backgroundColor": "transparent",
            "fillStyle": "solid",
            "strokeWidth": 2,
            "strokeStyle": "solid",
            "roughness": 1,
            "opacity": 100,
            "groupIds": [],
            "frameId": NSNull(),
            "roundness": NSNull(),
            "seed": abs(id.hashValue % 100_000),
            "version": 1,
            "versionNonce": abs(id.hashValue % 90_000),
            "isDeleted": false,
            "boundElements": NSNull(),
            "updated": 1,
            "link": NSNull(),
            "locked": false,
            "points": points,
            "pressures": pressures,
            "simulatePressure": false,
            "lastCommittedPoint": points.last ?? [0, 0],
        ]
    }

    /// La scène de chaque planche, version lot 17 : les modes Schéma et
    /// Manuscrit produisent de vraies scènes de leur mode, et la planche active
    /// porte ses annotations.
    static func workshopSceneWithModes(forIndex index: Int) -> String {
        switch index {
        case 1:  return workshopDiagramScene()
        case 2:  return workshopAnnotatedTargetScene()
        case 3:  return workshopInkScene()
        default: return workshopScene(forIndex: index)
        }
    }

    // MARK: - Semis complet

    /// L'écran 6a **complet** : le semis du lot 16, puis les scènes du lot 17
    /// (modes réels, annotations, connecteurs liés) et les deux lignes de
    /// `PIÈCES & CAPTURES`.
    ///
    /// Une fonction de plus plutôt qu'une modification de `seedWorkshop` :
    /// plusieurs lots sèment la même réunion en parallèle, et le lot 16 doit
    /// rester rebasable tel quel.
    ///
    /// Idempotent : `seedWorkshop` rend la réunion existante, la réécriture des
    /// scènes produit le même contenu, et les pièces sont reconnues par leur
    /// nom.
    @discardableResult
    static func seedWorkshopComplete(in context: ModelContext,
                                     store: BoardStore? = nil,
                                     root: URL? = nil) -> Meeting {
        let magasin = store ?? .shared
        let reunion = seedWorkshop(in: context, store: magasin)

        for planche in BoardOrdering.sorted(reunion.boards) {
            _ = try? magasin.save(scene: workshopSceneWithModes(forIndex: planche.index),
                                  board: planche,
                                  meetingStableID: reunion.ensuredStableID)
        }

        seedWorkshopResources(in: context,
                              meeting: reunion,
                              root: root ?? magasin.recordingsRoot)
        try? context.save()
        return reunion
    }

    // MARK: - Pièces et captures

    /// Sème la pièce et la capture de la section `PIÈCES & CAPTURES`, écrit
    /// leurs fichiers, et rend la réunion.
    ///
    /// `root` est injectable : un test ne doit pas écrire dans le
    /// `recordings/` de production, et une capture sans fichier apparaîtrait
    /// orpheline dans le dock.
    @discardableResult
    static func seedWorkshopResources(in context: ModelContext,
                                      meeting: Meeting,
                                      root: URL? = nil) -> Meeting {
        let racine = root ?? AudioRecorderService.recordingsDirectory
        let dossier = racine
            .appendingPathComponent(meeting.ensuredStableID.uuidString, isDirectory: true)

        // Idempotent par le nom, comme le reste du semis.
        let dejaSemee = meeting.attachments.contains { $0.fileName == workshopPieceName }
        if dejaSemee { return meeting }

        // La pièce déposée par Yann.
        let documents = dossier.appendingPathComponent("documents", isDirectory: true)
        let piece = ecritFichier(nom: workshopPieceName,
                                 dans: documents,
                                 contenu: Data("%PDF-1.4\n% pièce de démonstration\n".utf8))
        let attachement = MeetingAttachment(url: piece, kind: "pdf")
        attachement.scope = .meeting
        attachement.addedByName = "Yann"
        attachement.byteCount = 32
        context.insert(attachement)
        attachement.meeting = meeting

        // La capture Teams de 21:10, rangée sous son lot `slides` comme le veut
        // le modèle.
        let slides = dossier.appendingPathComponent("slides", isDirectory: true)
        let png = ecritFichier(nom: "capture-21-10.png",
                               dans: slides,
                               contenu: pngDeDemonstration())
        let lot = MeetingAttachment(url: slides, kind: AttachmentCopyPolicy.slidesKind)
        lot.scope = .meeting
        context.insert(lot)
        lot.meeting = meeting

        let capture = SlideCapture(index: 0,
                                   capturedAt: meeting.date.addingTimeInterval(1_270),
                                   imagePath: png.path)
        capture.t = 1_270  // 21:10
        capture.source = .teams
        capture.ocrText = "schéma réseau partagé"
        context.insert(capture)
        capture.attachment = lot

        try? context.save()
        return meeting
    }

    /// Le nom de la pièce de la capture de référence.
    static let workshopPieceName = "Archi_cible_Cléva.pdf"

    private static func ecritFichier(nom: String, dans dossier: URL, contenu: Data) -> URL {
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let url = dossier.appendingPathComponent(nom)
        try? contenu.write(to: url, options: .atomic)
        return url
    }

    /// Un PNG minuscule mais valide : `NSImage` doit savoir l'ouvrir, sinon
    /// `Insérer` échouerait sur le jeu de démonstration.
    private static func pngDeDemonstration() -> Data {
        // 1 × 1 pixel, gris clair. Le plus court PNG conforme qui soit.
        let base64 = """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
        """
        return Data(base64Encoded: base64) ?? Data()
    }
}
