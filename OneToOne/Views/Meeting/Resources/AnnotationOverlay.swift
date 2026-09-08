import SwiftUI
import AppKit
import SwiftData
import Observation

/// Le calque d'annotation posé **au-dessus** de l'aperçu (spec §4.2 :
/// « calque de dessin simple — rectangle, flèche, texte — sauvegardé comme
/// `Capture` dérivée, jamais comme modification du fichier source »).
///
/// Trois formes et pas une de plus : entourer un chiffre, désigner une ligne,
/// écrire un mot. Un éditeur graphique complet serait un autre produit, et le
/// besoin en séance est d'attirer l'œil en trois secondes.
///
/// **Le fichier source n'est jamais touché.** Ce que produit `Enregistrer`
/// est un PNG neuf sous `recordings/<uuid>/slides/`, enregistré comme
/// `SlideCapture` horodatée à la tête de lecture — donc retrouvable sur la
/// frise, exactement comme une capture d'écran.
@MainActor
@Observable
final class AnnotationOverlayModel {

    /// Les trois outils.
    enum Tool: String, CaseIterable, Identifiable, Sendable {
        case rectangle
        case arrow
        case text

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rectangle: return "Cadre"
            case .arrow:     return "Flèche"
            case .text:      return "Texte"
            }
        }

        var symbol: String {
            switch self {
            case .rectangle: return "rectangle"
            case .arrow:     return "arrow.up.right"
            case .text:      return "textformat"
            }
        }
    }

    /// Une forme posée, en coordonnées **normalisées** `0…1`.
    ///
    /// Normalisées et non en points : l'aperçu se redimensionne avec la
    /// fenêtre, et une annotation en points glisserait à côté de ce qu'elle
    /// désigne dès le premier redimensionnement.
    struct Shape: Identifiable, Equatable, Sendable {
        var id = UUID()
        var tool: Tool
        var from: CGPoint
        var to: CGPoint
        var text: String = ""
    }

    var tool: Tool = .rectangle
    private(set) var shapes: [Shape] = []
    /// La forme en cours de tracé.
    private(set) var draft: Shape?

    // MARK: - Tracé

    func beginDraft(at point: CGPoint) {
        draft = Shape(tool: tool, from: clamp(point), to: clamp(point))
    }

    func updateDraft(to point: CGPoint) {
        draft?.to = clamp(point)
    }

    /// Termine le tracé. **Rejette les formes trop petites** (moins de 1 % de
    /// la largeur) : un simple clic sur l'aperçu ne doit pas semer un point
    /// invisible qu'on ne saura plus sélectionner pour l'effacer.
    func endDraft() {
        guard let forme = draft else { return }
        draft = nil
        let dx = abs(forme.to.x - forme.from.x)
        let dy = abs(forme.to.y - forme.from.y)
        guard forme.tool == .text || dx > 0.01 || dy > 0.01 else { return }
        shapes.append(forme)
    }

    func undo() {
        _ = shapes.popLast()
    }

    func clear() {
        shapes.removeAll()
        draft = nil
    }

    var isEmpty: Bool { shapes.isEmpty }

    /// Le texte d'une forme `text`, éditable après le tracé.
    func setText(_ texte: String, for id: UUID) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        shapes[index].text = texte
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}

/// Le dessin du calque, sans interaction : sert aussi au rendu du PNG.
struct AnnotationOverlay: View {
    typealias Model = AnnotationOverlayModel

    let model: Model

    var body: some View {
        Canvas { contexte, taille in
            for forme in model.shapes {
                Self.dessiner(forme, in: &contexte, taille: taille)
            }
            if let brouillon = model.draft {
                Self.dessiner(brouillon, in: &contexte, taille: taille)
            }
        }
        .allowsHitTesting(false)
    }

    /// Trace une forme. Rouge `accent/report` — la couleur des alertes du jeu
    /// de jetons, et celle du `21 000 € — à confirmer` de la capture.
    static func dessiner(_ forme: Model.Shape,
                         in contexte: inout GraphicsContext,
                         taille: CGSize) {
        let depart = CGPoint(x: forme.from.x * taille.width, y: forme.from.y * taille.height)
        let arrivee = CGPoint(x: forme.to.x * taille.width, y: forme.to.y * taille.height)
        let teinte = One2OneToken.report

        switch forme.tool {
        case .rectangle:
            let rect = CGRect(x: min(depart.x, arrivee.x), y: min(depart.y, arrivee.y),
                              width: abs(arrivee.x - depart.x), height: abs(arrivee.y - depart.y))
            contexte.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(teinte),
                            lineWidth: 2)
        case .arrow:
            var chemin = Path()
            chemin.move(to: depart)
            chemin.addLine(to: arrivee)
            contexte.stroke(chemin, with: .color(teinte), lineWidth: 2)
            // La pointe : deux segments à 28° de l'axe, longueur bornée pour
            // qu'une flèche courte n'ait pas une pointe plus grande qu'elle.
            let angle = atan2(arrivee.y - depart.y, arrivee.x - depart.x)
            let longueur = min(12, hypot(arrivee.x - depart.x, arrivee.y - depart.y) * 0.4)
            for ecart in [0.49, -0.49] as [CGFloat] {
                var barbe = Path()
                barbe.move(to: arrivee)
                barbe.addLine(to: CGPoint(x: arrivee.x - longueur * cos(angle + ecart),
                                          y: arrivee.y - longueur * sin(angle + ecart)))
                contexte.stroke(barbe, with: .color(teinte), lineWidth: 2)
            }
        case .text:
            let texte = forme.text.isEmpty ? "Texte…" : forme.text
            contexte.draw(Text(texte).font(.plexSans(12, .semibold)).foregroundColor(teinte),
                          at: depart, anchor: .topLeading)
        }
    }
}

/// L'enregistrement d'une annotation en `SlideCapture` dérivée.
@MainActor
enum AnnotationSaver {

    enum SaveError: LocalizedError {
        case renderFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed:        return "Impossible de rendre l'annotation en image."
            case .writeFailed(let m):  return "Enregistrement impossible : \(m)"
            }
        }
    }

    /// Compose l'aperçu et le calque en un PNG, l'écrit sous
    /// `recordings/<uuid>/slides/` et crée la `SlideCapture` horodatée.
    ///
    /// Le fichier source n'est **pas** lu en écriture : on rend l'image de la
    /// page, on peint le calque par-dessus, on écrit ailleurs.
    @discardableResult
    static func save(annotation model: AnnotationOverlayModel,
                     over page: NSImage,
                     of item: ResourceItem,
                     in meeting: Meeting,
                     at t: Double?,
                     context: ModelContext,
                     base: URL = AttachmentImporter.baseDirectory()) throws -> SlideCapture {
        guard let png = compose(model: model, over: page) else { throw SaveError.renderFailed }

        let dossier = base
            .appending(path: "recordings/\(meeting.ensuredStableID.uuidString)/slides",
                       directoryHint: .isDirectory)
        let nom = "annotation-\(AttachmentCopyPolicy.destinationFileName(for: "\(AttachmentPinning.displayName(item.name)).png"))"
        let destination = dossier.appending(path: nom)
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            try png.write(to: destination)
        } catch {
            throw SaveError.writeFailed(error.localizedDescription)
        }

        // La capture pend du **lot de captures** de la réunion, comme celles du
        // moteur de capture d'écran : une seconde structure de rangement pour
        // les annotations ferait deux endroits à lire dans la frise.
        let lot = slidesBundle(in: meeting, context: context)
        let capture = SlideCapture(index: (lot.slides.map(\.index).max() ?? -1) + 1,
                                   capturedAt: Date(),
                                   imagePath: destination.path)
        capture.t = t
        capture.source = .screen
        capture.trigger = .manual
        capture.ocrText = model.shapes.compactMap { $0.text.isEmpty ? nil : $0.text }
            .joined(separator: " ")
        capture.attachment = lot
        context.insert(capture)
        try? context.save()
        return capture
    }

    /// Le PNG composé. `internal` pour être testable sans base ni disque.
    static func compose(model: AnnotationOverlayModel, over page: NSImage) -> Data? {
        let taille = page.size
        guard taille.width > 0, taille.height > 0 else { return nil }
        let rendu = NSImage(size: taille)
        rendu.lockFocus()
        page.draw(in: CGRect(origin: .zero, size: taille))
        if let cg = NSGraphicsContext.current?.cgContext {
            dessiner(model: model, in: cg, taille: taille)
        }
        rendu.unlockFocus()
        guard let tiff = rendu.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return png
    }

    /// Les formes en CoreGraphics. `Canvas` sert à l'écran ; ici il faut peindre
    /// dans un contexte hors écran, et les deux chemins partagent la
    /// géométrie normalisée du modèle.
    private static func dessiner(model: AnnotationOverlayModel,
                                 in cg: CGContext,
                                 taille: CGSize) {
        cg.setStrokeColor(NSColor(One2OneToken.report).cgColor)
        cg.setLineWidth(max(2, taille.width / 400))
        for forme in model.shapes {
            // L'origine de `NSImage` est en bas à gauche, celle du modèle en
            // haut à gauche : sans cette inversion, chaque annotation
            // apparaîtrait symétrique de ce qu'on a dessiné.
            let depart = CGPoint(x: forme.from.x * taille.width,
                                 y: (1 - forme.from.y) * taille.height)
            let arrivee = CGPoint(x: forme.to.x * taille.width,
                                  y: (1 - forme.to.y) * taille.height)
            switch forme.tool {
            case .rectangle:
                cg.stroke(CGRect(x: min(depart.x, arrivee.x), y: min(depart.y, arrivee.y),
                                 width: abs(arrivee.x - depart.x),
                                 height: abs(arrivee.y - depart.y)))
            case .arrow:
                cg.move(to: depart)
                cg.addLine(to: arrivee)
                let angle = atan2(arrivee.y - depart.y, arrivee.x - depart.x)
                let longueur = min(taille.width / 30,
                                   hypot(arrivee.x - depart.x, arrivee.y - depart.y) * 0.4)
                for ecart in [0.49, -0.49] as [CGFloat] {
                    cg.move(to: arrivee)
                    cg.addLine(to: CGPoint(x: arrivee.x - longueur * cos(angle + ecart),
                                           y: arrivee.y - longueur * sin(angle + ecart)))
                }
                cg.strokePath()
            case .text:
                let attributs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: max(12, taille.width / 45), weight: .semibold),
                    .foregroundColor: NSColor(One2OneToken.report)
                ]
                NSAttributedString(string: forme.text, attributes: attributs)
                    .draw(at: CGPoint(x: depart.x, y: depart.y - taille.width / 45))
            }
        }
    }

    /// Le lot de captures de la réunion, créé au premier besoin.
    static func slidesBundle(in meeting: Meeting, context: ModelContext) -> MeetingAttachment {
        if let existant = meeting.attachments.first(where: { $0.kind == AttachmentCopyPolicy.slidesKind }) {
            return existant
        }
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        lot.fileName = "Captures de la séance"
        lot.filePath = ""
        lot.bookmarkData = nil
        lot.scope = .meeting
        _ = lot.ensuredStableID
        lot.meeting = meeting
        context.insert(lot)
        return lot
    }
}
