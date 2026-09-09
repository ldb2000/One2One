import AppIntents
import SwiftData
import Foundation

/// App Intent exposé dans Shortcuts.app + Spotlight (action) pour démarrer
/// un 1:1 avec enregistrement automatique. `openAppWhenRun = true` pour
/// que `perform()` tourne dans le process de l'app et écrive dans le store
/// SwiftData partagé.
struct StartOneToOneIntent: AppIntent {
    static var title: LocalizedStringResource = "Démarrer un 1:1"
    static var description = IntentDescription(
        "Crée un nouveau 1:1 avec le collaborateur sélectionné et démarre l'enregistrement."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Collaborateur")
    var collaborator: CollaboratorEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = OneToOneApp.sharedContainer.mainContext
        let target = collaborator.id
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == target }
        )
        guard let model = try context.fetch(descriptor).first else {
            throw $collaborator.needsValueError("Collaborateur introuvable.")
        }
        QuickLaunchRouter.shared.startOneToOne(
            collaborator: model,
            autoStartRecording: true,
            in: context
        )
        return .result()
    }
}

/// Enregistre les phrases Siri/Spotlight pour `StartOneToOneIntent`.
/// `\(.applicationName)` est substitué par le nom localisé de l'app ; les
/// phrases en doublon élargissent la reconnaissance vocale.
///
/// **`AppIntents.AppShortcut` est qualifié.** Le dépôt déclare depuis la
/// décision **D1** son propre `AppShortcut` (`Views/Menus/AppShortcut.swift`,
/// la table des raccourcis clavier), qui masque le type d'Apple dans tout le
/// module. Les deux noms sont légitimes et aucun n'est renommable sans
/// perdre : celui d'Apple appartient au framework, celui du dépôt est le nom
/// que la décision a arrêté. Le préfixe de module lève l'ambiguïté ici, où
/// elle se produit — et nulle part ailleurs.
struct OneToOneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppIntents.AppShortcut] {
        AppIntents.AppShortcut(
            intent: StartOneToOneIntent(),
            phrases: [
                "Démarrer un 1:1 dans \(.applicationName)",
                "Lancer un 1:1 \(.applicationName)"
            ],
            shortTitle: "Démarrer un 1:1",
            systemImageName: "mic.circle.fill"
        )
    }
}
