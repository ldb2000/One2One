import AppKit
import SwiftUI

/// Présente le sélecteur de date de l'entrée « Date » du menu `/` : un
/// `NSPopover` ancré près du texte, remplaçant l'ancienne `NSAlert` modale
/// centrée (`presentDateAlertPicker`, supprimée).
///
/// ## Pourquoi un `NSPopover`, pas le modèle non-activant de `SlashPanel`
///
/// `SlashPanel` (le menu `/` lui-même, `SlashPanel.swift`) ne doit **jamais**
/// devenir key window : pendant qu'il est ouvert, l'utilisateur continue de
/// **taper** dans l'éditeur pour filtrer la liste (`/head`, par ex.) — lui
/// voler le focus casserait cette frappe en cours. Ce sélecteur de date n'a
/// pas cette contrainte : il s'ouvre **après** que « /date » a déjà été
/// effacé du texte par `SlashController.apply`, comme une interaction
/// ponctuelle et distincte (choisir un jour, basculer l'heure, valider) —
/// rien à taper simultanément dans l'éditeur pendant que ce popover est
/// ouvert.
///
/// Point mesuré (conflit signalé par le plan de tâche) : un champ de texte
/// éditable hébergé dans une fenêtre qui ne peut jamais devenir key ne peut
/// jamais devenir premier répondant, donc ne peut jamais recevoir de frappe
/// clavier (`NSWindow.makeFirstResponder` échoue sur une fenêtre qui n'est
/// pas key — comportement documenté d'AppKit). Le modèle `SlashPanel` aurait
/// donc rendu le champ de texte du haut inerte. Tranché ici en faveur de
/// l'édition : un vrai `NSPopover` gère lui-même la bascule de focus (devient
/// key à l'affichage, la restitue automatiquement à la fenêtre précédente à
/// la fermeture) — ni `NSApp.activate`, ni changement de fenêtre au premier
/// plan au sens utilisateur, juste un déplacement du focus clavier à
/// l'intérieur de la même app, le temps du choix. Ça ne rend pas l'éditeur
/// inutilisable : aucune frappe n'y est en cours à ce moment (contrairement
/// au cas de `SlashPanel`), et AppKit restitue le focus dès que le popover se
/// ferme.
///
/// `SlashPanelPositioning.origin` (écrite pour `SlashPanel`) ne s'applique
/// pas ici : elle place un `NSPanel` en coordonnées **écran** avec un calcul
/// manuel de débordement, alors que `NSPopover.show(relativeTo:of:preferredEdge:)`
/// attend un rectangle dans le référentiel de la **vue** ancre et gère
/// lui-même le débordement d'écran (bascule de bord, flèche). Le rectangle
/// d'ancrage lui-même reste calculé avec la même API que `SlashPanel`
/// (`firstRect(forCharacterRange:actualRange:)`, vérifiée sur cette pile
/// TextKit 1 — voir `SlashController.dateAnchorRect`), simplement converti
/// du référentiel écran vers celui de la vue avant l'appel à `show`.
@MainActor
final class SlashDatePickerPresenter: NSObject, NSPopoverDelegate {

    /// Instance partagée, réutilisée à chaque invocation de l'entrée
    /// « Date » — même raison que `SlashPanel` (construit une fois, pas à
    /// chaque frappe/chaque ouverture).
    static let shared = SlashDatePickerPresenter()

    private let state = SlashDatePickerState()
    private let popover = NSPopover()
    private var completion: ((SlashDateSelection?) -> Void)?

    /// Vrai entre l'appel à `finish(with:)` (bouton Insérer/Annuler, ou
    /// `configure` suivant d'un nouvel appel) et la notification de
    /// fermeture qu'il déclenche lui-même sur `popover`. Distingue cette
    /// fermeture **déjà traitée** d'une fermeture « périphérique » (clic en
    /// dehors du popover — `.behavior = .transient`) que `popoverDidClose`
    /// doit alors traiter comme une annulation.
    private var isFinishing = false

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: SlashDatePickerMetrics.width, height: SlashDatePickerMetrics.height)
        popover.contentViewController = NSHostingController(rootView: SlashDatePickerContent(state: state))
        popover.delegate = self

        state.onConfirm = { [weak self] in
            guard let self else { return }
            self.finish(with: SlashDateSelection(
                date: self.state.date,
                includesTime: self.state.includesTime,
                reminder: self.state.reminder
            ))
        }
        state.onCancel = { [weak self] in self?.finish(with: nil) }
    }

    /// Affiche le popover ancré près de `screenRect` (coordonnées écran,
    /// mêmes conventions que `SlashPanel.show(near:on:)` — voir
    /// `SlashController.dateAnchorRect`), converti dans le référentiel
    /// d'`anchorView` (exigence de `NSPopover.show(relativeTo:of:preferredEdge:)`,
    /// qui attend un rectangle **vue**, pas écran). Réinitialise l'état sur
    /// `initialDate` à chaque appel : ce présentateur est une instance
    /// partagée — sans cette remise à zéro, rouvrir le sélecteur montrerait
    /// la sélection laissée par l'appel précédent, pas la date passée ici
    /// (même risque que le bug historique du 1ᵉʳ janvier 2001, sous une
    /// autre forme : une valeur périmée plutôt qu'une valeur jamais posée).
    ///
    /// **Mesuré** : `NSPopover.show(relativeTo:of:preferredEdge:)` lève une
    /// exception Objective-C (crash immédiat, pas un simple no-op) si
    /// `anchorView` n'est rattachée à aucune fenêtre — reproduit
    /// indépendamment de ce projet avant d'écrire cette garde. Ne devrait pas
    /// arriver en production (l'entrée « Date » n'est accessible qu'une fois
    /// l'éditeur affiché à l'écran, donc rattaché à une fenêtre), mais un
    /// filet de sécurité vaut mieux qu'un crash si l'hypothèse s'avérait
    /// fausse : sans fenêtre, traite l'appel comme une annulation
    /// (`completion(nil)`) plutôt que de tenter l'affichage.
    func present(near screenRect: NSRect, in anchorView: NSView, initialDate: Date, completion: @escaping (SlashDateSelection?) -> Void) {
        guard let window = anchorView.window else {
            completion(nil)
            return
        }
        configure(initialDate: initialDate, completion: completion)
        let windowRect = window.convertFromScreen(screenRect)
        let viewRect = anchorView.convert(windowRect, from: nil)
        popover.show(relativeTo: viewRect, of: anchorView, preferredEdge: .minY)
    }

    /// Sépare la configuration de l'état (testable sans afficher de popover
    /// réel — un popover jamais montré n'a pas d'effet de bord visible) de
    /// l'affichage effectif (`present`). Voir
    /// `Tests/SlashDatePickerPresenterTests.swift` pour la preuve du bug
    /// historique corrigé (aujourd'hui, jamais le 1ᵉʳ janvier 2001).
    func configure(initialDate: Date, completion: @escaping (SlashDateSelection?) -> Void) {
        isFinishing = false
        self.completion = completion
        state.date = initialDate
        state.includesTime = false
        state.reminder = .none
    }

    /// Date actuellement portée par l'état du popover — `internal`, pas
    /// `private`, uniquement pour que les tests vérifient l'état sans
    /// dupliquer la construction du popover ni l'afficher réellement. Aucun
    /// code de production ne doit lire cette propriété : `SlashController`
    /// ne parle qu'à la closure `presentDatePicker` injectée, jamais
    /// directement à ce présentateur.
    var currentDate: Date { state.date }

    // MARK: - Réservé aux tests

    /// Simule le choix fait par l'utilisateur dans le popover (calendrier,
    /// bascule « Inclure l'heure », menu « Rappel ») sans piloter de vraie
    /// interaction souris/clavier — le popover lui-même n'est pas pilotable
    /// depuis les tests, comme `SlashPanel` (voir sa doc de tête de
    /// fichier). Suivi de `confirmForTesting()`/`cancelForTesting()` pour
    /// simuler le clic sur le bouton correspondant.
    func simulateSelectionForTesting(date: Date, includesTime: Bool, reminder: DateReminder) {
        state.date = date
        state.includesTime = includesTime
        state.reminder = reminder
    }

    /// Simule un clic sur le bouton « Insérer ».
    func confirmForTesting() { state.onConfirm?() }

    /// Simule un clic sur le bouton « Annuler ».
    func cancelForTesting() { state.onCancel?() }

    private func finish(with selection: SlashDateSelection?) {
        isFinishing = true
        popover.close()
        let callback = completion
        completion = nil
        callback?(selection)
    }

    /// `NSPopoverDelegate` : une fermeture qui n'est pas passée par
    /// `finish(with:)` (clic en dehors du popover — `.behavior = .transient`)
    /// doit être traitée comme une annulation, sinon `completion` ne serait
    /// jamais appelée dans ce cas et l'appelant resterait bloqué en attente
    /// d'une réponse qui ne vient pas.
    func popoverDidClose(_ notification: Notification) {
        guard !isFinishing else { return }
        let callback = completion
        completion = nil
        callback?(nil)
    }
}

// MARK: - État observable (poussé par `SlashDatePickerPresenter`)

@MainActor
private final class SlashDatePickerState: ObservableObject {
    @Published var date: Date = Date()
    @Published var includesTime: Bool = false
    @Published var reminder: DateReminder = .none
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
}

// MARK: - Contenu SwiftUI

/// Contenu du popover : champ de texte éditable (voir la doc de tête de
/// fichier — un vrai `NSPopover` peut devenir key, ce champ fonctionne
/// réellement), calendrier mensuel (`DatePicker` en style `.graphical` —
/// initiales des jours, navigation mois précédent/suivant, jour sélectionné
/// entouré et jour courant distinct sont fournis par ce style système, pas
/// redessinés à la main), bascule « Inclure l'heure », éditeur d'heure et
/// menu « Rappel ».
///
/// La ligne « Heure » reste **toujours présente** dans l'arbre de vues
/// (désactivée et estompée quand `includesTime` est faux) plutôt
/// qu'ajoutée/retirée conditionnellement : hauteur de contenu constante,
/// donc `popover.contentSize` fixe (`SlashDatePickerMetrics`) reste correct
/// sans dépendre du timing de mise à jour de SwiftUI — même précaution que
/// `SlashPanel.applySize` (voir sa doc) prend pour une raison différente
/// (nombre de lignes variable, pas bascule visible/masqué).
private struct SlashDatePickerContent: View {
    @ObservedObject var state: SlashDatePickerState
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Date", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                .onSubmit(commitTypedText)

            DatePicker("", selection: $state.date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            Toggle("Inclure l'heure", isOn: $state.includesTime)
                .toggleStyle(.switch)

            DatePicker("Heure", selection: $state.date, displayedComponents: .hourAndMinute)
                .disabled(!state.includesTime)
                .opacity(state.includesTime ? 1 : 0.35)

            Divider()

            HStack {
                Text("Rappel")
                Spacer()
                Picker("", selection: $state.reminder) {
                    ForEach(DateReminder.allCases, id: \.self) { reminder in
                        Text(reminder.label).tag(reminder)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            Divider()

            HStack {
                Spacer()
                Button("Annuler") { state.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                Button("Insérer") { state.onConfirm?() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(SlashDatePickerMetrics.padding)
        .frame(width: SlashDatePickerMetrics.width)
        .onAppear(perform: syncText)
        .onChange(of: state.date) { _, _ in syncText() }
        .onChange(of: state.includesTime) { _, _ in syncText() }
    }

    /// Reflète `state.date`/`state.includesTime` dans le champ de texte du
    /// haut — appelé après tout changement venant du calendrier, de la
    /// bascule ou de l'éditeur d'heure, jamais pendant que l'utilisateur
    /// tape dans le champ lui-même (rien ne modifie `state.date` à chaque
    /// frappe, seulement à la validation — `commitTypedText`, via
    /// `onSubmit` — donc pas de conflit d'écrasement pendant la saisie).
    private func syncText() {
        text = Self.formattedDate(state.date, includesTime: state.includesTime)
    }

    /// Reparse le texte tapé dans le champ du haut vers `state.date`, à la
    /// validation (Entrée). Essaie le format avec heure puis sans — les deux
    /// formats qui produisent l'affichage (`formattedDate`), donc round-trip
    /// garanti pour tout texte non modifié par l'utilisateur. Un texte qui
    /// ne correspond à aucun des deux formats est ignoré silencieusement :
    /// le champ revient à l'affichage de `state.date` inchangé — ce n'est
    /// pas un parseur de date en langage naturel, hors périmètre de cette
    /// tâche (apparence et ergonomie du sélecteur, pas une nouvelle syntaxe
    /// de saisie).
    private func commitTypedText() {
        if let parsed = Self.dateTimeParsingFormatter.date(from: text) {
            state.date = parsed
        } else if let parsed = SlashController.dateInsertionFormatter.date(from: text) {
            state.date = parsed
        } else {
            syncText()
        }
    }

    /// Même construction que `SlashController.insertDate` (date longue
    /// française + heure `HH:mm` séparées par une espace) : le texte affiché
    /// ici doit être exactement celui qui sera inséré, sinon l'aperçu
    /// mentirait sur ce que valider produit.
    private static func formattedDate(_ date: Date, includesTime: Bool) -> String {
        let dateText = SlashController.dateInsertionFormatter.string(from: date)
        guard includesTime else { return dateText }
        return dateText + " " + SlashController.timeInsertionFormatter.string(from: date)
    }

    /// Formateur de reparsing pour `commitTypedText`, symétrique de
    /// `formattedDate(_:includesTime: true)` (`dateInsertionFormatter` +
    /// espace + `timeInsertionFormatter`, combinés en un seul `dateFormat`
    /// plutôt qu'en deux appels : `DateFormatter.date(from:)` a besoin d'un
    /// patron unique couvrant toute la chaîne).
    private static let dateTimeParsingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy HH:mm"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter
    }()
}

// MARK: - Métriques

enum SlashDatePickerMetrics {
    static let width: CGFloat = 300
    static let height: CGFloat = 460
    static let padding: CGFloat = 14
}
