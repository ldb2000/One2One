import CoreGraphics
import ScreenCaptureKit

/// Capture un **écran entier** via ScreenCaptureKit : c'est la source
/// `Écran entier` du sélecteur (spec §5.1), celle qui reste disponible quand
/// ni Teams ni Zoom ne tournent.
///
/// Le contenu est réénuméré à chaque capture, comme dans `WindowFrameSource` :
/// cela absorbe le branchement d'un écran, un changement de résolution ou le
/// verrouillage de session sans aucun code de reconfiguration.
///
/// Les fenêtres de OneToOne sont **exclues** du filtre : sans cela, le
/// sélecteur, la bande de captures et la pastille se photographieraient
/// elles-mêmes, et la première capture d'une séance montrerait l'application
/// plutôt que ce qui est partagé.
///
/// ⚠️ `SCScreenshotManager` plante (`CGS_REQUIRE_INIT`) hors session
/// graphique : les tests ne construisent jamais ce type, ils remplacent
/// `FrameSource`.
struct DisplayFrameSource: FrameSource {

    /// Écran visé. `nil` = l'écran principal, celui que `SCShareableContent`
    /// rend en premier.
    let displayID: CGDirectDisplayID?
    /// 2 sur un écran Retina, pour capturer à la résolution native.
    let scale: Int

    init(displayID: CGDirectDisplayID? = nil, scale: Int = 2) {
        self.displayID = displayID
        self.scale = max(1, scale)
    }

    func captureFrame() async throws -> CGImage? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }

        let display: SCDisplay?
        if let displayID {
            display = content.displays.first { $0.displayID == displayID }
        } else {
            display = content.displays.first
        }
        // Écran débranché, ou session verrouillée : la source a **disparu**,
        // ce n'est pas un échec d'API. La session se met en pause et reprend
        // si l'écran revient.
        guard let display else { return nil }

        let ownWindows = content.windows.filter { fenetre in
            guard let nom = fenetre.owningApplication?.applicationName.lowercased() else { return false }
            return WindowCatalog.ownAppNames.contains(nom)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width * scale
        configuration.height = display.height * scale
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: ownWindows),
                configuration: configuration
            )
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
