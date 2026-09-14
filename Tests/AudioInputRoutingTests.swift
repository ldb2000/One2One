import Testing
import Foundation
@testable import OneToOne

/// La règle qui choisit l'entrée audio au démarrage et le repli à la
/// déconnexion (spec §4.1, décisions D2, D6, D7). Pure : aucun CoreAudio.
@Suite("AudioInputRouting — choix de l'entrée audio")
struct AudioInputRoutingTests {

    private let macBook = AudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "Microphone MacBook Pro",
                                           isBuiltIn: true, isSystemDefault: false)
    private let iphone = AudioInputDevice(uid: "iPhone-Continuity-1234", name: "iPhone de Laurent",
                                          isBuiltIn: false, isSystemDefault: true)
    private let usb = AudioInputDevice(uid: "USB-Yeti-0001", name: "Yeti Stereo Microphone",
                                       isBuiltIn: false, isSystemDefault: false)

    // MARK: - Démarrage

    @Test("Réglage « par défaut du système » → l'UID concret du défaut, jamais nil")
    func systemDefaultResolvesToConcreteUID() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: AudioInputRouting.systemDefaultUID,
                                                     devices: [macBook, iphone])
        #expect(verdict == .use(uid: iphone.uid))
    }

    @Test("Aucun périphérique marqué défaut → nil, on laisse macOS choisir")
    func noDeviceFlaggedDefaultUsesNil() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: AudioInputRouting.systemDefaultUID,
                                                     devices: [macBook, usb])
        #expect(verdict == .use(uid: nil))
    }

    @Test("Micro préféré présent → on l'utilise")
    func preferredPresent() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: iphone.uid, devices: [macBook, iphone])
        #expect(verdict == .use(uid: iphone.uid))
    }

    @Test("Micro préféré absent et d'autres entrées existent → on demande à l'utilisateur")
    func preferredMissingAsksUser() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: iphone.uid, devices: [macBook, usb])
        #expect(verdict == .askUser(candidates: [macBook, usb], missingPreferredUID: iphone.uid))
    }

    @Test("Aucune entrée détectée → noInput, même avec un préféré")
    func noDevices() {
        #expect(AudioInputRouting.resolveStart(preferredUID: iphone.uid, devices: []) == .noInput)
        #expect(AudioInputRouting.resolveStart(preferredUID: "", devices: []) == .noInput)
    }

    // MARK: - Repli

    @Test("Le périphérique retiré n'est pas celui en cours → ignore")
    func unrelatedRemovalIsIgnored() {
        let verdict = AudioInputRouting.fallback(removedUID: usb.uid, currentUID: iphone.uid, devices: [macBook, iphone])
        #expect(verdict == .ignore)
    }

    // `currentUID == nil` ne survient plus que lorsque **aucune** entrée n'est
    // marquée défaut au démarrage (`resolveStart` rend sinon un UID concret) :
    // l'engine n'est alors épinglé sur rien et macOS reroute lui-même.
    @Test("Entrée en cours = défaut système (nil) → ignore, macOS reroute lui-même")
    func systemDefaultRemovalIsIgnored() {
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: nil, devices: [macBook])
        #expect(verdict == .ignore)
    }

    @Test("iPhone retiré → micro intégré, reconnu par son type de transport et non par son nom")
    func fallsBackToBuiltIn() {
        let anglais = AudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone",
                                       isBuiltIn: true, isSystemDefault: false)
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [usb, anglais])
        #expect(verdict == .switchTo(anglais))
    }

    @Test("Sans micro intégré → l'entrée par défaut du système")
    func fallsBackToSystemDefault() {
        let defautUSB = AudioInputDevice(uid: usb.uid, name: usb.name, isBuiltIn: false, isSystemDefault: true)
        let autre = AudioInputDevice(uid: "Other", name: "Autre", isBuiltIn: false, isSystemDefault: false)
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [autre, defautUSB])
        #expect(verdict == .switchTo(defautUSB))
    }

    @Test("Ni intégré ni défaut → la première entrée restante")
    func fallsBackToFirstRemaining() {
        let autre = AudioInputDevice(uid: "Other", name: "Autre", isBuiltIn: false, isSystemDefault: false)
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [autre])
        #expect(verdict == .switchTo(autre))
    }

    @Test("Plus aucune entrée → arrêt")
    func stopsWhenNothingRemains() {
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [])
        #expect(verdict == .stopRecording)
    }

    @Test("Le périphérique retiré encore listé (liste non rafraîchie) n'est jamais choisi comme repli")
    func removedDeviceIsNeverTheFallback() {
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [iphone, macBook])
        #expect(verdict == .switchTo(macBook))
    }
}
