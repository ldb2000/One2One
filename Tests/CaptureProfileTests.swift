import Testing
import Foundation
@testable import OneToOne

/// Les profils de capture par type de réunion, portés de
/// `CaptureCore/MeetingType.swift` du dépôt Teams-Capture (programme §2.5,
/// décision D7).
@Suite("CaptureProfile")
struct CaptureProfileTests {

    @Test("Globale et Projet : réglage de référence, détection automatique, sans périodique")
    func referenceProfiles() {
        for kind in [MeetingKind.global, .project] {
            let profil = kind.captureProfile
            #expect(profil.sensitivity == .normal)
            #expect(profil.detectsAutomatically)
            #expect(profil.periodicCapture == nil)
        }
    }

    @Test("1:1, 1:1 Manager et Note : aucune capture sans geste, sensibilité faible")
    func manualOnlyProfiles() {
        for kind in [MeetingKind.oneToOne, .manager, .note] {
            let profil = kind.captureProfile
            #expect(profil.sensitivity == .low)
            #expect(!profil.detectsAutomatically)
            #expect(profil.periodicCapture == nil)
        }
    }

    @Test("Architecture : sensibilité élevée, les changements d'un schéma sont ténus")
    func architectureProfile() {
        let profil = MeetingKind.work.captureProfile
        #expect(profil.sensitivity == .high)
        #expect(profil.detectsAutomatically)
        #expect(profil.periodicCapture == nil)
    }

    @Test("Atelier : sensibilité élevée et capture forcée toutes les 2 minutes")
    func workshopProfile() {
        let profil = MeetingKind.workshop.captureProfile
        #expect(profil.sensitivity == .high)
        #expect(profil.detectsAutomatically)
        #expect(profil.periodicCapture == .seconds(120))
    }

    /// L'invariant du profil : l'échéance périodique **arme** l'écriture, et
    /// c'est le détecteur qui dit si l'image est stable. Un type qui
    /// demanderait la périodicité sans la détection n'écrirait jamais rien.
    @Test("aucun type ne demande la périodicité sans la détection automatique")
    func periodicRequiresDetection() {
        for kind in MeetingKind.allCases {
            let profil = kind.captureProfile
            if profil.periodicCapture != nil {
                #expect(profil.detectsAutomatically, "\(kind.label) : périodique sans détection")
            }
        }
    }

    @Test("chaque type explique son défaut")
    func everyKindExplainsItself() {
        for kind in MeetingKind.allCases {
            #expect(!kind.captureHint.isEmpty)
        }
    }

    @Test("les réglages se construisent depuis le type de réunion")
    func settingsFromKind() {
        let atelier = SlideCaptureSettings(meetingKind: .workshop)
        #expect(atelier.sensitivity == .high)
        #expect(atelier.detectsAutomatically)
        #expect(atelier.periodicCapture == .seconds(120))

        let unAUn = SlideCaptureSettings(meetingKind: .oneToOne)
        #expect(!unAUn.detectsAutomatically)
        #expect(unAUn.periodicCapture == nil)
    }

    // MARK: - TunedField

    @Test("changer de type n'écrase pas un réglage touché à la main")
    func tuningSparesTouchedFields() {
        var tuning = CaptureTuning()
        tuning.markTouched(.sensitivity)

        var reglages = SlideCaptureSettings(meetingKind: .oneToOne)
        reglages.sensitivity = .high

        let apres = tuning.apply(MeetingKind.project.captureProfile, to: reglages)
        // La sensibilité réglée à la main survit…
        #expect(apres.sensitivity == .high)
        // …mais les champs jamais touchés prennent bien le profil du type.
        #expect(apres.detectsAutomatically)
        #expect(apres.periodicCapture == nil)
    }

    @Test("sans réglage manuel, le profil du type s'applique en entier")
    func tuningAppliesWholeProfile() {
        let tuning = CaptureTuning()
        let apres = tuning.apply(MeetingKind.workshop.captureProfile,
                                 to: SlideCaptureSettings(meetingKind: .oneToOne))
        #expect(apres.sensitivity == .high)
        #expect(apres.detectsAutomatically)
        #expect(apres.periodicCapture == .seconds(120))
    }

    @Test("chaque champ se protège indépendamment")
    func tuningIsPerField() {
        var tuning = CaptureTuning()
        tuning.markTouched(.automaticDetection)
        var reglages = SlideCaptureSettings(meetingKind: .project)
        reglages.detectsAutomatically = false

        let apres = tuning.apply(MeetingKind.workshop.captureProfile, to: reglages)
        #expect(!apres.detectsAutomatically)
        #expect(apres.periodicCapture == .seconds(120))
        #expect(tuning.contains(.automaticDetection))
        #expect(!tuning.contains(.periodicCapture))
    }
}
