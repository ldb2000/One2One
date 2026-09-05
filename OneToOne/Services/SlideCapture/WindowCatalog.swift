import CoreGraphics
import ScreenCaptureKit

/// Énumère les fenêtres que l'utilisateur peut choisir comme source.
enum WindowCatalog {

    /// Noms (minuscules) sous lesquels l'app elle-même apparaît : à exclure de la liste.
    static let ownAppNames: Set<String> = ["onetoone", "one2one"]

    /// Fenêtres partageables, filtrées et triées. Traduit le refus d'autorisation.
    ///
    /// `onScreenWindowsOnly: false`, comme dans `WindowFrameSource` : une réunion Teams
    /// en plein écran vit sur son **propre Space** et n'est donc pas « à l'écran » du
    /// point de vue de ScreenCaptureKit. La filtrer ici la rendrait introuvable dans la
    /// liste, et la ferait passer pour disparue dans la face « arrêtée » (Reprendre
    /// désactivé). Le tri du bruit que `true` faisait gratuitement est repris par
    /// `filtered(_:excludingAppNames:)`.
    static func shareableWindows(excludingAppNames blacklist: Set<String>) async throws -> [ShareableWindow] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
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
                frame: $0.frame,
                isOnScreen: $0.isOnScreen,
                layer: $0.windowLayer
            )
        }
        let kept = filtered(windows, excludingAppNames: blacklist)
        guard !kept.isEmpty else { throw SlideCaptureError.noShareableWindows }
        return prioritized(kept)
    }

    /// Écarte les fenêtres de OneToOne, celles de la liste noire (noms d'app, insensible
    /// à la casse), les fenêtres sans titre, celles trop petites pour un slide lisible,
    /// les calques non nuls (panneaux flottants, infobulles, incrustations) et les
    /// fenêtres hors écran qui ne sont **pas** des fenêtres de réunion.
    ///
    /// La dernière condition est le compromis de `onScreenWindowsOnly: false` : garder
    /// Teams en plein écran sur un autre Space, sans déverser tout ce qui traîne dans
    /// les autres Spaces et les fenêtres minimisées.
    static func filtered(_ windows: [ShareableWindow], excludingAppNames blacklist: Set<String>) -> [ShareableWindow] {
        let excluded = ownAppNames.union(blacklist.map { $0.lowercased() })
        let minimum = SlideCaptureSettings.minimumWindowSide
        return windows.filter { w in
            !w.title.isEmpty
                && w.layer == 0
                && (w.isOnScreen || w.isMeetingApp)
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
