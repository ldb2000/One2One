import Testing
import SwiftUI
import AppKit
@testable import OneToOne

/// « La consigne est la reproduction stricte ; repli système si le chargement
/// échoue. » — décision D2 du programme de refonte.
///
/// Porté de `Teams-Capture/Tests/CaptureDesignTests/TypographyTests.swift`, où
/// Plex était seulement *installé sur le poste*. OneToOne embarque en plus les
/// fichiers, donc deux choses sont à prouver et non une : que les cinq noms
/// résolvent, et que les fichiers voyagent bien dans le bundle — sans quoi le
/// rendu se dégraderait silencieusement sur un poste sans Plex installé.
@Suite("Typographie Plex — les cinq noms PostScript")
struct One2OneTypographyTests {

    @Test("Les cinq graisses de la conception sont embarquées dans le bundle")
    func bundledFontFilesArePresent() {
        let urls = PlexFont.bundledFontURLs()
        #expect(urls.count == PlexFont.bundledFileNames.count,
                "fichiers trouvés : \(urls.map(\.lastPathComponent))")
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("Après enregistrement, les cinq noms PostScript résolvent")
    func plexResolvesAfterRegistration() {
        PlexFont.ensureRegistered()
        for name in PlexFont.requiredPostScriptNames {
            #expect(NSFont(name: name, size: 12) != nil, "fonte absente : \(name)")
        }
    }

    @Test("L'API rend les noms PostScript abrégés, pas les noms longs auxquels on s'attendrait")
    func apiUsesAbbreviatedNames() {
        // Ce test-ci documente le piège : `PlexWeight` rend bien les noms
        // abrégés (`Medm`, `SmBld`), pas les noms longs (`Medium`, `SemiBold`)
        // qu'une lecture naïve du design attendrait. Demander le nom long rend
        // `nil` et fait retomber silencieusement sur la fonte système — d'où le
        // besoin de le figer par un test.
        #expect(PlexWeight.regular.sansPostScriptName == "IBMPlexSans")
        #expect(PlexWeight.medium.sansPostScriptName == "IBMPlexSans-Medm")
        #expect(PlexWeight.semibold.sansPostScriptName == "IBMPlexSans-SmBld")
        #expect(PlexWeight.medium.monoPostScriptName == "IBMPlexMono-Medm")
        #expect(PlexWeight.semibold.monoPostScriptName == "IBMPlexMono-SmBld")
        #expect(PlexFont.isInstalled("IBMPlexSans-SemiBold") == false)
        #expect(PlexFont.isInstalled("IBMPlexSans-Medium") == false)
    }

    @Test("Les cinq rôles typographiques de la conception sont couverts")
    func requiredNamesCoverSpec() {
        #expect(Set(PlexFont.requiredPostScriptNames) == Set([
            "IBMPlexSans", "IBMPlexSans-Medm", "IBMPlexSans-SmBld",
            "IBMPlexMono-Medm", "IBMPlexMono-SmBld",
        ]))
    }

    @Test("Une fonte inexistante retombe sur la fonte système sans lever")
    func unknownNameFallsBack() {
        #expect(PlexFont.isInstalled("IBMPlexSans-Fantome") == false)
        // `plexSans` ne doit jamais lever ni rendre une fonte nulle : le repli
        // est la garantie que l'écran reste lisible sur un poste dégradé.
        _ = Font.plexSans(12, .semibold)
        _ = Font.plexMono(10, .medium)
    }
}
