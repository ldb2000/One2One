import XCTest
import AppKit
@testable import OneToOne

/// Couvre `SlashDatePickerPresenter` : l'état sous-jacent au popover de
/// l'entrée « Date » (`OneToOne/Markdown/Slash/SlashDatePickerPresenter.swift`),
/// via `configure`/`currentDate`/`simulateSelectionForTesting`/
/// `confirmForTesting`/`cancelForTesting` — API réservée aux tests, voir leur
/// doc respective. Le popover lui-même (rendu SwiftUI : calendrier, champ de
/// texte, bascule, menu) n'a **pas** de couverture automatisée ici, comme
/// `SlashPanel` (voir `Tests/SlashPanelPositioningTests.swift`) : pas de
/// dépendance permettant de piloter une vue SwiftUI hébergée dans ce projet.
/// Ces tests vérifient uniquement le comportement de `SlashDatePickerPresenter`
/// par ses effets observables (`currentDate`, la closure de complétion),
/// jamais en inspectant le rendu.
@MainActor
final class SlashDatePickerPresenterTests: XCTestCase {

    // MARK: - Bug historique (2001) : la valeur initiale n'est jamais la date de référence d'AppKit

    /// Preuve directe et indépendante de toute affectation explicite : l'état
    /// par défaut de `SlashDatePickerState.date` (`@Published var date: Date
    /// = Date()`) n'est jamais la date de référence d'`NSDatePicker`/AppKit
    /// (1ᵉʳ janvier 2001, `Date(timeIntervalSinceReferenceDate: 0)`) — c'est
    /// exactement le bug historique de l'ancienne `presentDateAlertPicker`
    /// (`NSDatePicker()` sans `dateValue` explicitement affecté). Ce nouveau
    /// présentateur ne construit plus de `NSDatePicker` du tout : rien ici ne
    /// peut retomber sur cette valeur par défaut d'AppKit.
    func test_freshPresenter_defaultDateState_isNotThe2001ReferenceDate() {
        let presenter = SlashDatePickerPresenter()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

        XCTAssertGreaterThan(
            abs(presenter.currentDate.timeIntervalSince(referenceDate)),
            60 * 60 * 24 * 365 * 20,
            "un présentateur fraîchement créé ne doit pas partir de la date de référence AppKit (1ᵉʳ janvier 2001)"
        )
    }

    /// `configure(initialDate:)` doit imposer la date passée, pas la laisser
    /// à une valeur par défaut ni conserver une sélection précédente — ce
    /// présentateur est une instance partagée (`SlashDatePickerPresenter.shared`),
    /// réutilisée d'une ouverture du sélecteur à l'autre.
    func test_configure_setsDateToExactlyThePassedInitialDate() {
        let presenter = SlashDatePickerPresenter()
        let fixedDate = Self.fixedTestDate

        presenter.configure(initialDate: fixedDate, completion: { _ in })

        XCTAssertEqual(presenter.currentDate, fixedDate)
    }

    /// `configure` doit aussi remettre à zéro `includesTime`/`reminder`, pas
    /// seulement `date` — sinon rouvrir le sélecteur (même instance
    /// partagée) montrerait l'heure/le rappel choisis lors d'une session
    /// précédente. Mesuré par mutation : sans les deux lignes de reset dans
    /// `configure`, ce test est le seul de la suite à échouer (les deux
    /// autres champs ne sont vérifiés nulle part ailleurs sur une même
    /// instance réutilisée).
    func test_configure_resetsIncludesTimeAndReminder_fromAPreviousSession() {
        let presenter = SlashDatePickerPresenter()
        presenter.configure(initialDate: Date(), completion: { _ in })
        presenter.simulateSelectionForTesting(date: Self.fixedTestDate, includesTime: true, reminder: .oneWeekBefore)
        presenter.confirmForTesting() // termine une première « session »

        var received: SlashDateSelection?
        presenter.configure(initialDate: Self.fixedTestDate, completion: { received = $0 })
        presenter.confirmForTesting() // sans re-choisir heure/rappel : doit repartir à zéro

        XCTAssertEqual(received?.includesTime, false, "rouvrir le sélecteur ne doit pas montrer l'heure activée d'une session précédente")
        // `.none` serait ambigu ici (résolu comme `Optional<DateReminder>.none`,
        // c'est-à-dire `nil`, plutôt que `DateReminder.none`) — piège classique
        // de Swift avec `XCTAssertEqual` sur un `Optional` : `DateReminder.none`
        // explicite lève l'ambiguïté.
        XCTAssertEqual(received?.reminder, DateReminder.none, "rouvrir le sélecteur ne doit pas montrer le rappel choisi lors d'une session précédente")
    }

    /// Variante bout-en-bout, au niveau où le bug était réellement visible :
    /// `SlashController.presentDatePickerPopover` (implémentation par défaut
    /// injectée dans `presentDatePicker`) doit configurer le présentateur
    /// partagé avec la date **du moment de l'appel**, jamais 2001. Utilise un
    /// `EditorTextView` réellement attaché à une `NSWindow` (jamais affichée
    /// à l'écran — même précédent que `EditorTextViewTaskToggleTests.makeWiredEditorInWindow`) :
    /// sans fenêtre, `presentDatePickerPopover` traite l'appel comme une
    /// annulation (voir `test_present_withoutWindow_doesNotCrash_andCancelsImplicitly`
    /// ci-dessous) et ne configure rien, ce qui ne prouverait pas la valeur
    /// initiale réellement utilisée en production.
    func test_presentDatePickerPopover_defaultImplementation_configuresWithTodayAsInitialDate() {
        let (editor, window) = makeWiredEditorInWindow(markdown: "")
        let before = Date()
        var completionCalled = false

        SlashController.presentDatePickerPopover(editor, .zero) { _ in completionCalled = true }

        let shown = SlashDatePickerPresenter.shared.currentDate
        let after = Date()

        XCTAssertGreaterThanOrEqual(shown, before)
        XCTAssertLessThanOrEqual(shown, after)

        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertGreaterThan(abs(shown.timeIntervalSince(referenceDate)), 60 * 60 * 24 * 365 * 20)

        // Nettoyage : referme le popover partagé pour ne pas laisser une
        // closure de complétion en attente affecter un test suivant.
        SlashDatePickerPresenter.shared.cancelForTesting()
        XCTAssertTrue(completionCalled)
        withExtendedLifetime(window) {}
    }

    // MARK: - Annulation

    /// `nil` côté closure de complétion signifie annulation — voir la doc de
    /// `SlashController.presentDatePicker`.
    func test_cancelForTesting_completionReceivesNil() {
        let presenter = SlashDatePickerPresenter()
        var completionCalled = false
        var received: SlashDateSelection?
        presenter.configure(initialDate: Self.fixedTestDate, completion: { selection in
            completionCalled = true
            received = selection
        })

        presenter.cancelForTesting()

        XCTAssertTrue(completionCalled)
        XCTAssertNil(received)
    }

    // MARK: - Validation : la sélection complète (date, heure, rappel) est remontée telle quelle

    /// Preuve directe que le rappel choisi dans le menu « Rappel » est bien
    /// remonté par le sélecteur — même si rien ne le déclenche encore
    /// (chantier 3 de la spec, hors périmètre). Couvre aussi
    /// `includesTime` : les trois champs de `SlashDateSelection` sont
    /// vérifiés indépendamment pour détecter un champ oublié dans
    /// `finish(with:)`.
    func test_confirmForTesting_completionReceivesTheChosenDateTimeAndReminder() {
        let presenter = SlashDatePickerPresenter()
        var received: SlashDateSelection?
        presenter.configure(initialDate: Date(), completion: { received = $0 })

        presenter.simulateSelectionForTesting(date: Self.fixedTestDate, includesTime: true, reminder: .twoDaysBefore)
        presenter.confirmForTesting()

        XCTAssertEqual(received?.date, Self.fixedTestDate)
        XCTAssertEqual(received?.includesTime, true)
        XCTAssertEqual(received?.reminder, .twoDaysBefore)
    }

    /// Chacun des cinq rappels de `DateReminder` doit survivre au
    /// round-trip choix → confirmation → complétion, pas seulement le cas
    /// choisi par le test précédent.
    func test_confirmForTesting_eachReminderCase_isReturnedUnchanged() {
        for reminder in DateReminder.allCases {
            let presenter = SlashDatePickerPresenter()
            var received: SlashDateSelection?
            presenter.configure(initialDate: Self.fixedTestDate, completion: { received = $0 })

            presenter.simulateSelectionForTesting(date: Self.fixedTestDate, includesTime: false, reminder: reminder)
            presenter.confirmForTesting()

            XCTAssertEqual(received?.reminder, reminder, "le rappel \(reminder) doit être remonté inchangé")
        }
    }

    // MARK: - Garde mesurée : pas de crash sans fenêtre

    /// `NSPopover.show(relativeTo:of:preferredEdge:)` lève une exception
    /// Objective-C si la vue ancre n'a pas de fenêtre — mesuré
    /// indépendamment de ce projet avant d'écrire la garde dans
    /// `SlashDatePickerPresenter.present`. Ce test protège cette garde :
    /// sans elle, cet appel planterait le process de test entier (une
    /// exception ObjC non interceptée n'est pas récupérable par XCTest).
    func test_present_withoutWindow_doesNotCrash_andCancelsImplicitly() {
        let (editor, _) = makeWiredEditor(markdown: "")
        XCTAssertNil(editor.window, "prémisse du test : la vue ne doit avoir aucune fenêtre")

        var completionCalled = false
        var received: SlashDateSelection?
        SlashDatePickerPresenter.shared.present(
            near: .zero,
            in: editor,
            initialDate: Date(),
            completion: { selection in
                completionCalled = true
                received = selection
            }
        )

        XCTAssertTrue(completionCalled, "sans fenêtre, l'appel doit être traité comme une annulation immédiate, pas laissé sans réponse")
        XCTAssertNil(received)
    }

    // MARK: - Fixtures

    private static var fixedTestDate: Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 25
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    /// Reprend le câblage TextKit minimal des autres suites de tests du menu
    /// `/` (`Tests/SlashControllerTests.swift`), sans `Coordinator`/binding :
    /// ce fichier n'a besoin que d'un `EditorTextView` valide à passer en
    /// ancre.
    private func makeWiredEditor(markdown: String) -> (EditorTextView, NSTextStorage) {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)

        let parsed = MarkdownParser.parse(markdown)
        textStorage.setAttributedString(parsed)
        layoutManager.ensureLayout(for: container)

        return (editor, textStorage)
    }

    /// Comme `makeWiredEditor`, mais attache la vue à une vraie `NSWindow`
    /// (jamais affichée à l'écran) — même précédent et même raison de
    /// renvoyer la fenêtre à l'appelant qu'`EditorTextViewTaskToggleTests.makeWiredEditorInWindow`
    /// (`NSWindow.contentView` ne retient pas son propriétaire : sans
    /// référence forte gardée en vie par l'appelant, `editor.window`
    /// redeviendrait `nil`).
    private func makeWiredEditorInWindow(markdown: String) -> (EditorTextView, NSWindow) {
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = editor
        return (editor, window)
    }
}
