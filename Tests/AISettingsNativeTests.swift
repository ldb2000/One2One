import AppKit
import SwiftUI
import Testing
@testable import OneToOne

@MainActor
@Suite("Champs natifs des réglages IA", .serialized)
struct AISettingsNativeTests {
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @Test("Le champ sécurisé est natif et son binding suit le changement de profil")
    func secureFieldBinding() async throws {
        _ = NSApplication.shared
        var firstKey = "first"
        var secondKey = "second"
        let first = Binding(get: { firstKey }, set: { firstKey = $0 })
        let second = Binding(get: { secondKey }, set: { secondKey = $0 })
        let host = NSHostingView(rootView: EditableTextField(placeholder: "Jeton", text: first, isSecure: true))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 28)
        host.layoutSubtreeIfNeeded()
        let field = try #require(descendants(host).compactMap { $0 as? NSSecureTextField }.first)
        #expect(field.isEditable)
        #expect(field.acceptsFirstResponder)
        host.rootView = EditableTextField(placeholder: "Jeton", text: second, isSecure: true)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        let updated = try #require(descendants(host).compactMap { $0 as? NSSecureTextField }.first)
        updated.stringValue = "updated-second"
        updated.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: updated))
        #expect(secondKey == "updated-second")
        #expect(firstKey == "first")
    }

    @Test("L'écran IA utilise les champs natifs de recherche, modèle et jeton")
    func settingsFieldsAndSnapshot() async throws {
        _ = NSApplication.shared
        let settings = AppSettings()
        let view = AISettingsView(settings: settings, automaticallyLoadsModels: false).padding(16)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        let fields = descendants(host).compactMap { $0 as? NSTextField }
        #expect(fields.contains { $0.placeholderString == "Rechercher un modèle" && $0.isEditable })
        #expect(fields.contains { $0.placeholderString == "Choisir ci-dessous ou saisir un identifiant" && $0.isEditable })
        #expect(fields.contains { $0 is NSSecureTextField })
        if let path = ProcessInfo.processInfo.environment["ONETOONE_AI_SETTINGS_SNAPSHOT"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
