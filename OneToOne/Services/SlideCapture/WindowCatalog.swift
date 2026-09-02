import CoreGraphics
import ScreenCaptureKit

/// Énumère les fenêtres que l'utilisateur peut choisir comme source.
enum WindowCatalog {

    /// Noms (minuscules) sous lesquels l'app elle-même apparaît : à exclure de la liste.
    static let ownAppNames: Set<String> = ["onetoone", "one2one"]

    /// Fenêtres à l'écran, filtrées et triées. Traduit le refus d'autorisation.
    static func shareableWindows(excludingAppNames blacklist: Set<String>) async throws -> [ShareableWindow] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            if SlideCaptureError.isPermissionDenial(error) { throw SlideCaptureError.screenRecordingDenied }
            throw SlideCaptureError.captureFailed(error.localizedDescription)
        }
        let windows = content.windows.map {
            ShareableWindow(
                id: $0.windowID,
                title: $0.title ?? "",
                appName: $0.owningApplication?.applicationName ?? "Application inconnue",
                bundleIdentifier: $0.owningApplication?.bundleIdentifier,
                frame: $0.frame
            )
        }
        let kept = filtered(windows, excludingAppNames: blacklist)
        guard !kept.isEmpty else { throw SlideCaptureError.noShareableWindows }
        return prioritized(kept)
    }

    /// Écarte les fenêtres de OneToOne, celles de la liste noire (noms d'app, insensible
    /// à la casse), les fenêtres sans titre et celles trop petites pour un slide lisible.
    static func filtered(_ windows: [ShareableWindow], excludingAppNames blacklist: Set<String>) -> [ShareableWindow] {
        let excluded = ownAppNames.union(blacklist.map { $0.lowercased() })
        let minimum = SlideCaptureSettings.minimumWindowSide
        return windows.filter { w in
            !w.title.isEmpty
                && w.frame.width >= minimum && w.frame.height >= minimum
                && !excluded.contains(w.appName.lowercased())
        }
    }

    /// Applications de réunion en tête, puis surface décroissante : la fenêtre de
    /// réunion, la plus grande, arrive naturellement en premier.
    static func prioritized(_ windows: [ShareableWindow]) -> [ShareableWindow] {
        windows.sorted { l, r in
            if l.isMeetingApp != r.isMeetingApp { return l.isMeetingApp }
            return l.frame.width * l.frame.height > r.frame.width * r.frame.height
        }
    }
}
