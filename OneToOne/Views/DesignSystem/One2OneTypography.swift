import AppKit
import CoreText
import SwiftUI

/// Les trois graisses de Plex utilisées par la conception.
enum PlexWeight: Sendable {
    case regular
    case medium
    case semibold

    /// Nom PostScript de la variante sans-serif.
    ///
    /// Attention aux abréviations : `Medm` et `SmBld`, pas `Medium` ni
    /// `SemiBold`. Les noms longs n'existent pas dans les fichiers d'IBM Plex ;
    /// les demander rend `nil` et fait retomber silencieusement sur la fonte
    /// système.
    var sansPostScriptName: String {
        switch self {
        case .regular: "IBMPlexSans"
        case .medium: "IBMPlexSans-Medm"
        case .semibold: "IBMPlexSans-SmBld"
        }
    }

    /// Nom PostScript de la variante monospace. Même piège d'abréviation.
    var monoPostScriptName: String {
        switch self {
        case .regular: "IBMPlexMono"
        case .medium: "IBMPlexMono-Medm"
        case .semibold: "IBMPlexMono-SmBld"
        }
    }

    /// Graisse équivalente sur la fonte système, pour la retombée.
    var systemWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }

    /// Même retombée, côté AppKit : `NSFont` a son propre type de graisse, et
    /// les `NSViewRepresentable` en ont besoin (cf. `NSFont.plexSans`).
    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}

/// Résolution des fontes Plex : enregistrement des fichiers embarqués, puis
/// interrogation par nom PostScript.
enum PlexFont {

    /// Les cinq noms dont la conception a besoin (spec §1.2, Typographie). Un
    /// test vérifie qu'ils résolvent : leur disparition doit être un échec
    /// bruyant, pas une typographie qui change de fonte sans le dire.
    static let requiredPostScriptNames = [
        "IBMPlexSans",
        "IBMPlexSans-Medm",
        "IBMPlexSans-SmBld",
        "IBMPlexMono-Medm",
        "IBMPlexMono-SmBld",
    ]

    /// Les fichiers embarqués, dans `OneToOne/Resources/Fonts/` (SIL Open Font
    /// License 1.1, texte copié à côté dans `OFL.txt`). Plex Sans 400/500/600 et
    /// Plex Mono 500/600 : exactement les cinq rôles de
    /// `requiredPostScriptNames`.
    static let bundledFileNames = [
        "IBMPlexSans-Regular.ttf",
        "IBMPlexSans-Medium.ttf",
        "IBMPlexSans-SemiBold.ttf",
        "IBMPlexMono-Medium.ttf",
        "IBMPlexMono-SemiBold.ttf",
    ]

    private static let resourceBundleName = "OneToOne_OneToOne.bundle"

    /// URL des fichiers de fonte réellement trouvés.
    ///
    /// Deux dispositions à couvrir, comme pour `mermaid.min.js` (cf.
    /// `MermaidResourceLocator`) : en développement `Bundle.module` résout
    /// (l'exécutable et `OneToOne_OneToOne.bundle` sont voisins dans
    /// `.build/<config>/`) ; dans le `.app` packagé par
    /// `Scripts/bump-and-build.sh`, le bundle de ressources est copié un niveau
    /// plus bas, sous `Contents/Resources/`, là où l'accesseur généré ne
    /// regarde pas. `.process("Resources")` peut par ailleurs aplatir `Fonts/`
    /// à la racine du bundle selon la version de SwiftPM : les deux
    /// emplacements sont donc essayés.
    static func bundledFontURLs() -> [URL] {
        bundledFileNames.compactMap { fileName in
            let stem = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            if let url = Bundle.module.url(forResource: stem, withExtension: ext, subdirectory: "Fonts") {
                return url
            }
            if let url = Bundle.module.url(forResource: stem, withExtension: ext) {
                return url
            }
            return packagedFontURL(fileName: fileName)
        }
    }

    /// `resourceRoot/OneToOne_OneToOne.bundle/[Fonts/]<fichier>` — disposition
    /// produite par `bump-and-build.sh`, qui copie le bundle de ressources
    /// SwiftPM en bloc sous `Contents/Resources`. `resourceRoot` par défaut à
    /// `Bundle.main.resourceURL` ; injectable pour les tests.
    static func packagedFontURL(fileName: String, resourceRoot: URL? = Bundle.main.resourceURL) -> URL? {
        guard let resourceRoot else { return nil }
        let bundleRoot = resourceRoot.appendingPathComponent(resourceBundleName, isDirectory: true)
        for candidate in [
            bundleRoot.appendingPathComponent("Fonts", isDirectory: true).appendingPathComponent(fileName),
            bundleRoot.appendingPathComponent(fileName),
        ] where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    /// Enregistrement au premier besoin, une seule fois pour tout le process
    /// (`static let` = initialisation garantie unique par le runtime Swift).
    /// Portée `.process` : les fontes ne sont pas installées sur le poste de
    /// l'utilisateur, elles vivent le temps de l'exécution.
    ///
    /// Rend la liste des échecs, ce qui n'intéresse que le débogage : il n'y a
    /// pas de `fatalError` ici. Une fonte manquante dégrade le rendu, elle ne
    /// casse pas l'application, et `Font.plexSans`/`plexMono` retombent sur la
    /// fonte système. C'est `bundledFontFilesArePresent` qui garantit que la
    /// dégradation ne passe pas inaperçue en intégration.
    private static let registration: [String] = {
        var failures: [String] = []
        for url in bundledFontURLs() {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let message = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "raison inconnue"
                failures.append("\(url.lastPathComponent) : \(message)")
            }
        }
        if !failures.isEmpty {
            print("[PlexFont] enregistrement partiel : \(failures.joined(separator: ", "))")
        }
        return failures
    }()

    /// Force l'enregistrement. Appelé par `isInstalled`, donc par tout usage de
    /// `plexSans`/`plexMono` : il n'y a pas d'ordre de lancement à respecter.
    /// Également appelé explicitement au démarrage de l'application, pour que la
    /// première image dessinée soit déjà à la bonne fonte.
    static func ensureRegistered() {
        _ = registration
    }

    static func isInstalled(_ postScriptName: String) -> Bool {
        ensureRegistered()
        return NSFont(name: postScriptName, size: 12) != nil
    }
}

extension Font {
    /// Plex Sans à la taille et la graisse demandées, ou la fonte système si
    /// Plex ne résout pas.
    ///
    /// Ne jamais chaîner `.weight(...)` par-dessus : la graisse est déjà dans le
    /// fichier de fonte, et la redemander pousse SwiftUI à en synthétiser une.
    static func plexSans(_ size: CGFloat, _ weight: PlexWeight = .regular) -> Font {
        PlexFont.isInstalled(weight.sansPostScriptName)
            ? .custom(weight.sansPostScriptName, fixedSize: size)
            : .system(size: size, weight: weight.systemWeight)
    }

    /// Plex Mono, mêmes règles. Sert aux timecodes et aux libellés de section.
    static func plexMono(_ size: CGFloat, _ weight: PlexWeight = .medium) -> Font {
        PlexFont.isInstalled(weight.monoPostScriptName)
            ? .custom(weight.monoPostScriptName, fixedSize: size)
            : .system(size: size, weight: weight.systemWeight, design: .monospaced)
    }
}

extension NSFont {
    /// Pendant AppKit de `Font.plexSans`, pour les `NSViewRepresentable`.
    ///
    /// Un `NSTextField` ne lit pas le `.font()` de l'environnement SwiftUI : le
    /// titre de la barre du haut portait un `.font(.plexSans(13, .semibold))`
    /// sans effet, et sortait en fonte système (écart (c) n° 3 de la recette
    /// des vagues 1–4). Mêmes règles que côté SwiftUI : repli explicite sur la
    /// fonte système si Plex ne résout pas, et jamais de graisse synthétisée
    /// par-dessus — elle est déjà dans le fichier de fonte.
    static func plexSans(_ size: CGFloat, _ weight: PlexWeight = .regular) -> NSFont {
        guard PlexFont.isInstalled(weight.sansPostScriptName),
              let fonte = NSFont(name: weight.sansPostScriptName, size: size)
        else { return .systemFont(ofSize: size, weight: weight.appKitWeight) }
        return fonte
    }

    /// Plex Mono, mêmes règles. Sert aux timecodes et aux libellés de section.
    static func plexMono(_ size: CGFloat, _ weight: PlexWeight = .medium) -> NSFont {
        guard PlexFont.isInstalled(weight.monoPostScriptName),
              let fonte = NSFont(name: weight.monoPostScriptName, size: size)
        else { return .monospacedSystemFont(ofSize: size, weight: weight.appKitWeight) }
        return fonte
    }
}

extension View {
    /// Libellé de section : Plex Mono 600 à 9,5 pt, majuscules, interlettrage
    /// 0,07 em, couleur `ink/4`. Jamais `ink/muted` : sous 12 pt il faut 4,5:1
    /// de contraste (spec §1.2).
    func sectionLabel() -> some View {
        modifier(SectionLabelModifier())
    }
}

/// Le libellé de section, en encre de libellé mono **du thème courant**.
///
/// Un `ViewModifier` et non un simple enchaînement de modificateurs : une
/// extension de `View` n'a pas accès à l'environnement, et le mode séance du
/// lot 4 affiche les mêmes libellés (`NOTES`, `TRANSCRIPTION LIVE`,
/// `ASSISTANT`, `CAPTURÉ CETTE SÉANCE`) sur `#1c1a17`, où `ink/4` (`#6b6659`)
/// est illisible. En `.paper`, la couleur résolue est exactement celle d'avant.
private struct SectionLabelModifier: ViewModifier {
    @Environment(\.one2OneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(.plexMono(9.5, .semibold))
            .tracking(9.5 * 0.07)
            .textCase(.uppercase)
            .foregroundStyle(theme.colors.ink4)
    }
}
