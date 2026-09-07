import Testing
import Foundation
@testable import OneToOne

/// Critère du lot 4, spec §2.6 : « **Aucun chrome** hors la barre d'état (point
/// d'enregistrement, titre, temps, avatars, locuteur courant, `Clore la
/// séance`). »
///
/// Un critère de cette forme ne se vérifie pas par l'état d'un modèle : un
/// `MeetingSpacesBar` ajouté demain par distraction — ou une carte
/// d'indicateurs recopiée depuis le mode fenêtré — passerait toutes les autres
/// suites. Ces tests **lisent les sources** du dossier `Session/`, comme
/// `ActionsRailNoModalTests` le fait pour le rail.
@Suite("Le mode séance n'a pas de chrome")
struct SessionNoChromeTests {

    /// La racine du paquet, déduite de l'emplacement de ce fichier :
    /// `<racine>/Tests/SessionNoChromeTests.swift`.
    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var dossierSession: URL {
        racine.appendingPathComponent("OneToOne/Views/Meeting/Session", isDirectory: true)
    }

    private func sources() throws -> [(nom: String, texte: String)] {
        let fichiers = try FileManager.default
            .contentsOfDirectory(at: dossierSession, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try fichiers.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("Le dossier du mode séance est bien celui qu'on croit lire")
    func sessionSourcesAreFound() throws {
        let noms = try sources().map(\.nom)
        // Si ce test tombe, c'est le chemin qui a bougé — et alors les
        // suivants ne prouveraient plus rien en passant.
        #expect(noms.contains("SessionFullscreenView.swift"))
        #expect(noms.contains("SessionStatusBar.swift"))
        #expect(noms.contains("TimeRailColumn.swift"))
        #expect(noms.contains("SessionAssistantPanel.swift"))
        #expect(noms.count >= 9)
    }

    @Test("Aucune surface de chrome du mode fenêtré n'est montée en séance")
    func noWindowedChrome() throws {
        // Chacune est du chrome que la spec §2.6 retire : barre d'espaces,
        // bandeau d'indicateurs, barre du haut, sélecteur de mode, badge de
        // préparation, barre d'enregistrement contextuelle, dock d'assistant
        // du mode fenêtré, et le rail de 330 px.
        let interdits = ["MeetingSpacesBar", "MeetingKPIBand", "MeetingTopChromeBar(",
                         "MeetingContextualRecorderBar", "MeetingPrepBadge",
                         "MeetingAssistantDock(", "ActionsRail(", "MeetingSpaceLayout"]
        for source in try sources() {
            for interdit in interdits {
                #expect(!source.texte.contains(interdit),
                        "\(source.nom) monte \(interdit) : le mode séance n'a de chrome que sa barre d'état (spec §2.6)")
            }
        }
    }

    @Test("Aucune couleur nommée hors One2OneToken")
    func noNamedColors() throws {
        // Même règle que le rail (lot 3) : `One2OneTokens.swift` est le seul
        // fichier autorisé à nommer une couleur. `NSColor(c.ink1)` convertit un
        // jeton, il ne le nomme pas.
        let interdits = ["Color.red", "Color.blue", "Color.green", "Color.orange",
                         "Color.gray", "Color.black", "Color.white", "Color.yellow",
                         "Color.purple", "Color.pink", "Color.primary", "Color.secondary",
                         "Color.accentColor", ".foregroundColor(.red", "Color(hex:",
                         "Color(red:", "NSColor.red", "NSColor.systemBlue"]
        for source in try sources() {
            for interdit in interdits {
                #expect(!source.texte.contains(interdit),
                        "\(source.nom) nomme la couleur \(interdit) : seul One2OneTokens.swift le fait")
            }
        }
    }

    @Test("La grille est bien 78 | 1fr | 400, et les deux largeurs sont des jetons")
    func gridWidths() throws {
        #expect(One2OneToken.timeColumnWidth == 78)
        #expect(One2OneToken.sessionTranscriptWidth == 400)
        let assemblage = try sources().first { $0.nom == "SessionFullscreenView.swift" }
        let texte = try #require(assemblage?.texte)
        // Les largeurs sont lues dans les jetons, pas réécrites en clair.
        #expect(texte.contains("One2OneToken.sessionTranscriptWidth"))
        #expect(!texte.contains("width: 400"))
        #expect(!texte.contains("width: 78"))
    }

    @Test("Le mode séance impose son thème, il ne l'hérite pas")
    func imposesItsTheme() throws {
        let assemblage = try sources().first { $0.nom == "SessionFullscreenView.swift" }
        let texte = try #require(assemblage?.texte)
        #expect(texte.contains(".one2OneTheme(theme)"))
        #expect(texte.contains("One2OneTheme { .session }"))
    }

    @Test("La colonne temps ne calcule rien : tout vient de TimeRailGeometry")
    func railDelegatesGeometry() throws {
        let colonne = try sources().first { $0.nom == "TimeRailColumn.swift" }
        let texte = try #require(colonne?.texte)
        #expect(texte.contains("TimeRailGeometry.y("))
        #expect(texte.contains("TimeRailGeometry.t("))
        #expect(texte.contains("TimeRailGeometry.labels("))
        // Aucune division par la durée dans la vue : c'est là que les `NaN`
        // naissent, et c'est pour cela que le calcul est ailleurs.
        #expect(!texte.contains("/ duree"))
        #expect(!texte.contains("/ duration"))
    }
}

/// L'entrée et la sortie du mode (spec §2.6, périmètre n° 6 du lot).
@Suite("Entrée et sortie du mode séance")
@MainActor
struct SessionFullscreenEntryTests {

    private func actions(kind: MeetingKind, isRecording: Bool = false) -> MeetingMenuActions {
        MeetingMenuActions(
            meetingTitle: "[P25_110] Partage statut final",
            kind: kind,
            isRecording: isRecording,
            isPaused: false,
            isTranscribing: false,
            isGeneratingReport: false,
            hasWav: false,
            hasPlayableAudio: false,
            hasReport: false,
            hasTranscript: false,
            startRecording: {}, stopRecording: {}, appendRecording: {},
            togglePause: {}, retranscribe: {}, generateReport: {},
            toggleCustomPrompt: {}, importCalendar: {}, importExistingWAV: {},
            editAudio: {}, revealWAV: {}, deleteMeeting: {},
            exportMarkdown: {}, exportPDF: {}, exportMail: { _ in },
            exportOutlook: { _ in }, exportAppleNotes: { _ in },
            openAssistant: {}, addPlayheadMarker: {},
            pasteResource: {}, openResources: {}
        )
    }

    @Test("`⌃⌘F` est actif sans audio : on y passe pour prendre des notes")
    func enabledWithoutAudio() {
        #expect(actions(kind: .project).isEnabled(.sessionFullscreen))
        #expect(actions(kind: .global).isEnabled(.sessionFullscreen))
        #expect(actions(kind: .workshop).isEnabled(.sessionFullscreen))
    }

    @Test("Une note n'a pas de mode séance")
    func disabledForNote() {
        #expect(!actions(kind: .note).isEnabled(.sessionFullscreen))
    }

    @Test("L'action par défaut passe par le présentateur, sans toucher MeetingView")
    func defaultActionGoesThroughPresenter() {
        // Sans hôte enregistré, la demande est ignorée : le jeton ne bouge pas,
        // et l'application ne présente pas un plein écran vide.
        let presentateur = SessionFullscreenPresenter.shared
        let avant = presentateur.jeton
        actions(kind: .project).toggleSessionFullscreen()
        #expect(presentateur.jeton == avant)
    }

    @Test("Le présentateur n'accepte une demande qu'avec un hôte")
    func presenterNeedsAHost() {
        let presentateur = SessionFullscreenPresenter.shared
        let reunion = UUID()
        presentateur.declarerHote(reunion, capable: false)
        #expect(!presentateur.peutEntrer(reunion))
        #expect(!presentateur.peutEntrer(nil))

        presentateur.declarerHote(reunion, capable: true)
        #expect(presentateur.peutEntrer(reunion))
        #expect(!presentateur.peutEntrer(UUID()))

        let avant = presentateur.jeton
        presentateur.demanderBascule()
        #expect(presentateur.jeton == avant + 1)

        // Deux demandes de suite doivent toutes deux passer : un jeton, pas un
        // booléen.
        presentateur.demanderBascule()
        #expect(presentateur.jeton == avant + 2)

        // Le renoncement ne débranche que son propre hôte.
        presentateur.declarerHote(UUID(), capable: false)
        #expect(presentateur.peutEntrer(reunion))
        presentateur.declarerHote(reunion, capable: false)
        #expect(!presentateur.peutEntrer(reunion))
    }

    @Test("Le point d'entrée n'est posé qu'une fois dans l'application")
    func singleEntryPoint() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OneToOne", isDirectory: true)
        let enumerateur = FileManager.default.enumerator(at: racine,
                                                         includingPropertiesForKeys: nil)
        var poses: [String] = []
        while let url = enumerateur?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let texte = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if texte.contains(".sessionFullscreen(meeting:") || texte.contains(".sessionFullscreen(") {
                // La déclaration de l'extension elle-même ne compte pas.
                guard url.lastPathComponent != "SessionFullscreenPresenter.swift" else { continue }
                poses.append(url.lastPathComponent)
            }
        }
        // Deux poses substitueraient deux fois le contenu de la même fenêtre,
        // et la seconde restauration rendrait la première.
        #expect(poses == ["MeetingSpaceView.swift"], "poses trouvées : \(poses)")
    }

    @Test("MeetingView n'est pas touché par le lot 4")
    func meetingViewUntouched() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OneToOne/Views/MeetingView.swift")
        let texte = try String(contentsOf: url, encoding: .utf8)
        #expect(!texte.contains("SessionFullscreen"))
        #expect(!texte.contains("toggleSessionFullscreen"))
    }
}
