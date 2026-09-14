import Testing
import Foundation
@testable import OneToOne

/// La feuille d'aide autorisations doit envoyer au **bon** volet des Réglages
/// Système selon ce qui a été refusé (spec §1, ligne 4).
@Suite("AudioPermissionKind — aide autorisations")
struct AudioPermissionHelpTests {

    @Test("Le micro pointe sur l'ancre Privacy_Microphone, moderne puis historique")
    func microphoneAnchors() {
        let urls = AudioPermissionKind.microphone.candidateURLs.map(\.absoluteString)
        #expect(urls.count == 2)
        #expect(urls.allSatisfy { $0.hasSuffix("?Privacy_Microphone") })
        #expect(urls[0].contains("com.apple.settings.PrivacySecurity.extension"))
        #expect(urls[1].contains("com.apple.preference.security"))
    }

    @Test("L'audio système réutilise le lien d'enregistrement de l'écran")
    func systemAudioReusesScreenRecordingLink() {
        #expect(AudioPermissionKind.systemAudio.candidateURLs == ScreenRecordingSettingsLink.candidateURLs)
        #expect(AudioPermissionKind.systemAudio.manualPath == ScreenRecordingSettingsLink.manualPath)
    }

    @Test("Le chemin manuel du micro nomme le volet Microphone")
    func microphoneManualPath() {
        #expect(AudioPermissionKind.microphone.manualPath.hasSuffix("→ Microphone"))
    }

    @Test("Les textes distinguent les deux cas")
    func textsDiffer() {
        #expect(AudioPermissionKind.microphone.title != AudioPermissionKind.systemAudio.title)
        #expect(AudioPermissionKind.microphone.explanation.contains("micro"))
        #expect(AudioPermissionKind.systemAudio.explanation.contains("écran"))
    }

    @Test("open s'arrête à la première URL acceptée")
    @MainActor
    func openStopsAtFirstSuccess() {
        var tentatives: [URL] = []
        let ok = MicrophoneSettingsLink.open { url in tentatives.append(url); return true }
        #expect(ok)
        #expect(tentatives.count == 1)
    }

    @Test("open rend faux quand aucune URL n'est acceptée")
    @MainActor
    func openReportsFailure() {
        var tentatives: [URL] = []
        let ok = MicrophoneSettingsLink.open { url in tentatives.append(url); return false }
        #expect(!ok)
        #expect(tentatives.count == 2)
    }
}
