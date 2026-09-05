import CoreGraphics
import ScreenCaptureKit

/// Capture une fenêtre précise via ScreenCaptureKit, un appel par tick.
///
/// Le filtre est **reconstruit à chaque capture**. C'est volontaire : cela absorbe le
/// déplacement, le redimensionnement et le changement d'écran de la fenêtre source sans
/// aucun code de reconfiguration. Ne pas le mettre en cache « pour optimiser ».
///
/// `onScreenWindowsOnly: false` est délibéré : capturer une fenêtre occultée (ou en
/// plein écran sur un autre Space) est la prémisse même de la fonctionnalité.
///
/// ⚠️ `SCScreenshotManager` plante (`CGS_REQUIRE_INIT`) hors session graphique : les
/// tests ne construisent jamais ce type, ils remplacent `FrameSource`.
struct WindowFrameSource: FrameSource {

    let windowID: CGWindowID
    /// 2 sur un écran Retina, pour capturer à la résolution native.
    let scale: Int

    init(windowID: CGWindowID, scale: Int = 2) {
        self.windowID = windowID
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

        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil // la fenêtre a disparu
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width) * scale
        configuration.height = Int(window.frame.height) * scale
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
