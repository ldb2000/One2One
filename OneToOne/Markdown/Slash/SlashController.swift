import AppKit
import UniformTypeIdentifiers

/// Détection du `/`, navigation clavier et application d'une `SlashCommand`
/// (catalogue de la tâche 3) sur l'`EditorTextView` réel — la pièce qui relie
/// `SlashCatalog`/`SlashCommand` (tâche 3, logique pure) et `SlashPanel`
/// (tâche 4, affichage) au texte édité.
///
/// Reçoit son `EditorTextView` **directement** au lieu de le chercher dans
/// `MarkdownEditorRegistry` (`EditableTextField.swift`) : ce singleton n'est
/// pas isolé et ses clés viennent de l'appelant — deux vues sur le même objet
/// y partageraient le même identifiant. Rien ici ne le référence.
///
/// ## Câblage prévu (tâche 6, **non fait ici**)
///
/// Ce fichier ne modifie pas `EditorRepresentable.swift`. Pour que ce
/// contrôleur prenne effet, `Coordinator` (déjà `NSTextViewDelegate`) devra :
///
/// 1. Posséder un `SlashController?`, créé dans `makeNSView` juste après
///    l'`EditorTextView`, et le démonter dans `dismantleNSView` en appelant
///    `teardown()` avant de relâcher la référence.
/// 2. Appeler `updateFeatures(_:)` à chaque `updateNSView`, comme c'est déjà
///    fait pour `coordinator.features`.
/// 3. Au tout début de `textDidChange(_:)`, appeler `slashController.textDidChange()` ;
///    s'il renvoie `true`, la frappe vient d'être absorbée par le menu
///    (ouverture, filtrage ou fermeture) : `return` immédiatement, **sans**
///    lancer `ShortcutDetector`, sans sérialiser, sans (re)programmer le
///    debounce. C'est ce qui règle à la fois le piège 1 (une requête `/xyz`
///    tapée lentement ne doit jamais atteindre `SwiftData`) et le piège 3
///    (un `*`/`_`/`` ` `` tapé comme partie de la requête ne doit pas
///    déclencher un raccourci inline parasite pendant qu'elle est composée).
///    Un restylage visuel de `pendingStyleRange` avant ce retour anticipé
///    reste possible si désiré ; cette classe ne l'impose pas et ne le fait
///    pas elle-même.
/// 4. Implémenter `NSTextViewDelegate.textViewDidChangeSelection(_:)` (absent
///    du module aujourd'hui) et y appeler `slashController.selectionDidChange()`
///    — c'est ce qui ferme le menu sur un clic ailleurs ou une flèche
///    gauche/droite qui sort de la requête.
/// 5. Implémenter `NSTextViewDelegate.textView(_:doCommandBy:)` (absent du
///    module aujourd'hui — aucun `keyDown`/`doCommandBy` n'existe encore) et
///    y renvoyer `slashController.handle(commandSelector:)`.
///
/// Ces cinq points sont volontairement **non appliqués ici** : la tâche 6 les
/// câble.
@MainActor
final class SlashController {

    // MARK: - Dépendances

    private weak var textView: EditorTextView?
    private var features: Set<MarkdownFeature>
    private let panel: SlashPanel

    /// Annule la tâche de debounce du binding markdown
    /// (`EditorRepresentable.Coordinator.cancelPendingWrite`, injectée par
    /// l'appelant). Invoquée à chaque frappe absorbée par le menu tant qu'il
    /// est ouvert (piège 1) — indépendamment de l'endroit où la tâche 6
    /// choisit d'appeler `textDidChange()`, ce contrôleur annule lui-même
    /// toute tâche en vol dès qu'il détecte que la requête est en cours de
    /// composition.
    private let cancelPendingWrite: () -> Void

    /// Ouvre le sélecteur de fichier pour l'entrée « Image » et renvoie l'URL
    /// choisie (`nil` si annulé). Point d'injection pour les tests — la valeur
    /// par défaut (`presentImageOpenPanel`) ouvre un vrai `NSOpenPanel`.
    private let presentImagePicker: (@escaping (URL?) -> Void) -> Void

    /// Ouvre le sélecteur de date pour l'entrée « Date » et renvoie la
    /// sélection choisie via `completion` — **`nil` signifie annulation** :
    /// rien n'a été validé, l'appelant ne doit ni insérer de texte ni muter
    /// le storage. Reçoit la vue à ancrer (`EditorTextView`) et le rectangle
    /// écran de l'emplacement d'insertion (`dateAnchorRect`, même technique
    /// que `reposition()` pour `SlashPanel`) : le popover par défaut en a
    /// besoin pour s'afficher près du texte plutôt qu'au centre de l'écran.
    /// Même raison d'être injectable que `presentImagePicker` : point
    /// d'injection pour les tests — la valeur par défaut
    /// (`presentDatePickerPopover`) ouvre un vrai `NSPopover`
    /// (`SlashDatePickerPresenter`), qui remplace l'ancienne `NSAlert` +
    /// `NSDatePicker` modale (`presentDateAlertPicker`, supprimée — son
    /// commentaire affirmait à tort que `NSDatePicker.dateValue` valait déjà
    /// la date du jour à la création ; en réalité il vaut la date de
    /// référence d'AppKit, le 1ᵉʳ janvier 2001, tant qu'on ne l'affecte pas
    /// explicitement, d'où le calendrier s'ouvrant sur 2001 constaté par
    /// l'utilisateur. `SlashDatePickerPresenter` ne dépend plus de
    /// `NSDatePicker` du tout : son état SwiftUI est explicitement
    /// initialisé à `Date()` — voir `SlashDatePickerPresenter.present`).
    private let presentDatePicker: (EditorTextView, NSRect, @escaping (SlashDateSelection?) -> Void) -> Void

    /// Ouvre le sélecteur d'emoji système pour l'entrée « Emoji ». Point
    /// d'injection pour les tests — la valeur par défaut
    /// (`presentCharacterPalette`) ouvre le vrai panneau « Caractères »
    /// d'AppKit (`NSApp.orderFrontCharacterPalette(nil)`).
    ///
    /// **Limite connue, structurelle** : contrairement à `presentImagePicker`/
    /// `presentDatePicker`, cette closure ne prend ni ne renvoie rien — la
    /// palette système tape directement dans le premier répondant une fois un
    /// emoji choisi (même mécanisme que le collage ou la frappe normale), et
    /// `NSApp.orderFrontCharacterPalette(nil)` n'offre aucun callback pour
    /// observer ce qui a été inséré, ni même *si* quelque chose l'a été
    /// (l'utilisateur peut fermer le panneau sans rien choisir). Les tests de
    /// cette entrée se limitent donc à vérifier que le présentateur injecté
    /// est bien appelé — ils ne peuvent pas, et ne prétendent pas, vérifier
    /// le texte réellement inséré.
    private let presentEmojiPicker: () -> Void

    // MARK: - État

    /// Vrai entre l'ouverture du menu et sa fermeture (application, Échap,
    /// `⌫` avant le `/`, ou sélection qui sort de la requête).
    private(set) var isOpen: Bool = false
    /// Position du caractère `/` qui a ouvert le menu.
    private var triggerLocation: Int = 0
    private var currentGroups: [(group: SlashCommand.Group, commands: [SlashCommand])] = []
    /// `currentGroups.flatMap { $0.commands }` — même aplatissement que celui
    /// documenté par `SlashPanel.update(groups:selectedIndex:)`, pour que
    /// `selectedIndex` désigne la même entrée des deux côtés.
    private var flatCommands: [SlashCommand] = []
    private var selectedIndex: Int = 0

    /// `panel`, `presentImagePicker`, `presentDatePicker` et
    /// `presentEmojiPicker` n'ont volontairement pas de valeur par défaut :
    /// un défaut faisant appel à un initialiseur/une méthode `@MainActor`
    /// depuis une position de paramètre par défaut échoue à la compilation en
    /// mode Swift 6 (isolation d'acteur d'une expression de défaut non
    /// résolue au contexte de l'appelant) — mesuré. L'appelant (tâche 6, ou un
    /// test) passe explicitement `SlashPanel()`, `SlashController.
    /// presentImageOpenPanel`, `SlashController.presentDatePickerPopover` et
    /// `SlashController.presentCharacterPalette`.
    init(
        textView: EditorTextView,
        features: Set<MarkdownFeature>,
        panel: SlashPanel,
        cancelPendingWrite: @escaping () -> Void,
        presentImagePicker: @escaping (@escaping (URL?) -> Void) -> Void,
        presentDatePicker: @escaping (EditorTextView, NSRect, @escaping (SlashDateSelection?) -> Void) -> Void,
        presentEmojiPicker: @escaping () -> Void
    ) {
        self.textView = textView
        self.features = features
        self.panel = panel
        self.cancelPendingWrite = cancelPendingWrite
        self.presentImagePicker = presentImagePicker
        self.presentDatePicker = presentDatePicker
        self.presentEmojiPicker = presentEmojiPicker
        panel.onSelect = { [weak self] command in self?.apply(command) }
    }

    /// À appeler depuis `updateNSView` (tâche 6), comme pour
    /// `coordinator.features` : les fonctionnalités actives peuvent changer
    /// en cours de vie de la vue (changement de `MarkdownTextEditor(features:)`).
    func updateFeatures(_ features: Set<MarkdownFeature>) {
        self.features = features
    }

    // MARK: - Détection et filtrage (hook 1 : `Coordinator.textDidChange`)

    /// Réagit à une frappe. Renvoie `true` si le menu vient d'absorber cette
    /// frappe (ouverture ou mise à jour de la requête) — voir le câblage
    /// prévu en tête de fichier pour ce que l'appelant doit alors **ne pas**
    /// faire.
    ///
    /// Le `/` ouvre le menu s'il est en début de ligne ou précédé d'une
    /// espace (`isValidTriggerPosition`) — jamais en milieu de mot.
    @discardableResult
    func textDidChange() -> Bool {
        guard let textView, let storage = textView.textStorage else {
            close()
            return false
        }
        let ns = storage.string as NSString
        let cursor = textView.selectedRange().location

        if isOpen {
            guard let query = Self.currentQuery(in: ns, triggerLocation: triggerLocation, cursor: cursor) else {
                close()
                return false
            }
            updateFilter(query: query)
            cancelPendingWrite()
            return true
        }

        guard cursor > 0, cursor <= ns.length else { return false }
        let slashLocation = cursor - 1
        guard ns.character(at: slashLocation) == 0x2F /* "/" */ else { return false }
        guard Self.isValidTriggerPosition(in: ns, slashLocation: slashLocation) else { return false }

        open(triggerLocation: slashLocation)
        cancelPendingWrite()
        return true
    }

    /// Réagit à un déplacement du curseur qui ne passe pas par
    /// `textDidChange()` (clic ailleurs, flèches gauche/droite). Ferme le
    /// menu si le curseur est sorti de la plage de la requête ; ne fait rien
    /// s'il est encore dedans (ex. flèche gauche à l'intérieur du texte tapé
    /// après le `/`).
    func selectionDidChange() {
        guard isOpen, let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let cursor = textView.selectedRange().location
        if Self.currentQuery(in: ns, triggerLocation: triggerLocation, cursor: cursor) == nil {
            close()
        }
    }

    /// Vrai si le caractère à `slashLocation` (déjà vérifié `"/"` par
    /// l'appelant) ouvre valablement le menu : position 0 du document, juste
    /// après un `\n`, ou juste après une espace. Fonction pure, testable sans
    /// `NSTextView`.
    static func isValidTriggerPosition(in text: NSString, slashLocation: Int) -> Bool {
        guard slashLocation >= 0, slashLocation < text.length else { return false }
        guard text.character(at: slashLocation) == 0x2F else { return false }
        if slashLocation == 0 { return true }
        let previous = text.character(at: slashLocation - 1)
        return previous == 0x0A /* "\n" */ || previous == 0x20 /* " " */
    }

    /// Texte tapé depuis le `/` situé à `triggerLocation` jusqu'à `cursor`.
    /// `nil` invalide l'état « menu ouvert » et doit fermer le menu :
    /// `triggerLocation` hors bornes ou ne portant plus `"/"` (le caractère a
    /// été supprimé — cas du `⌫` juste avant le `/`), `cursor` avant le début
    /// de la requête (le curseur est remonté avant/sur le `/`), ou un saut de
    /// ligne dans l'intervalle (ne devrait pas arriver — Entrée est
    /// intercepté pendant que le menu est ouvert — gardé par défense). Fonction
    /// pure, testable sans `NSTextView`.
    static func currentQuery(in text: NSString, triggerLocation: Int, cursor: Int) -> String? {
        guard triggerLocation >= 0, triggerLocation < text.length else { return nil }
        guard text.character(at: triggerLocation) == 0x2F else { return nil }
        let queryStart = triggerLocation + 1
        guard cursor >= queryStart, cursor <= text.length else { return nil }
        let query = text.substring(with: NSRange(location: queryStart, length: cursor - queryStart))
        guard !query.contains("\n") else { return nil }
        return query
    }

    // MARK: - Clavier (hook 2 : `Coordinator.textView(_:doCommandBy:)`)

    /// Traite une commande d'édition standard (`doCommandBy:`). Renvoie
    /// `true` si elle a été consommée (l'appelant ne doit pas laisser
    /// `NSTextView` exécuter son comportement par défaut).
    ///
    /// Menu ouvert : flèches haut/bas naviguent, Entrée/Tab appliquent
    /// l'entrée sélectionnée, Échap ferme (le `/` tapé reste dans le texte —
    /// aucune mutation du storage ici). Tout le reste (dont `⌫`) n'est **pas**
    /// intercepté : le comportement par défaut s'applique, et
    /// `textDidChange()`/`selectionDidChange()` referment le menu s'il est
    /// devenu invalide après coup.
    ///
    /// Menu fermé : seule Entrée est regardée, pour le correctif du piège 4
    /// (voir `breakOutOfHeadingIfNeeded`) — général, pas limité aux titres
    /// appliqués par ce menu : le bug (`typingAttributes` qui perpétue
    /// `.mdBlockType` d'un titre au `\n`) est le même quelle que soit
    /// l'origine du titre. Essaie ensuite `exitEmptyCodeBlockIfNeeded` (même
    /// geste que `ListEditingCommands` pour un item de liste vide, transposé
    /// au bloc de code — voir sa doc) : sans lui, le curseur resterait piégé
    /// dans le bloc, `setBlockType`/`setListKind` refusant tous deux
    /// d'opérer sur une ligne `.codeBlock`.
    func handle(commandSelector: Selector) -> Bool {
        if isOpen {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                moveSelection(by: 1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                moveSelection(by: -1)
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                applySelected()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                close()
                return true
            default:
                return false
            }
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if breakOutOfHeadingIfNeeded() { return true }
            return exitEmptyCodeBlockIfNeeded()
        }
        return false
    }

    // MARK: - Fermeture

    /// Ferme le menu (masque le panneau, réinitialise l'état de filtrage) —
    /// **sans** toucher au texte : le `/` et la requête tapés restent tels
    /// quels (spec : Échap « ferme, conserve le `/` tapé »). Réutilisable
    /// (`SlashPanel` n'est pas recréé) — voir `teardown()` pour la
    /// destruction définitive.
    func close() {
        isOpen = false
        triggerLocation = 0
        currentGroups = []
        flatCommands = []
        selectedIndex = 0
        panel.dismiss()
    }

    /// À appeler quand l'`EditorTextView` associé est démonté
    /// (`dismantleNSView`, tâche 6). Ferme réellement la fenêtre du panneau
    /// (`NSWindow.close()`) plutôt que `dismiss()`/`orderOut(_:)` : ce
    /// contrôleur ne sera pas réutilisé après, contrairement au cycle normal
    /// ouverture/fermeture du menu que `close()` sert.
    func teardown() {
        isOpen = false
        panel.close()
    }

    // MARK: - Ouverture / filtrage

    private func open(triggerLocation: Int) {
        self.triggerLocation = triggerLocation
        self.isOpen = true
        updateFilter(query: "")
    }

    private func updateFilter(query: String) {
        let groups = SlashCatalog.grouped(matching: query, features: features)
        currentGroups = groups
        flatCommands = groups.flatMap { $0.commands }
        selectedIndex = 0
        panel.update(groups: groups, selectedIndex: selectedIndex)
        reposition()
    }

    private func moveSelection(by delta: Int) {
        guard !flatCommands.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), flatCommands.count - 1)
        panel.update(groups: currentGroups, selectedIndex: selectedIndex)
    }

    /// Repositionne le panneau sous (ou au-dessus, cf. `SlashPanelPositioning`)
    /// le rectangle écran du `/` déclencheur. Ne fait rien si la vue n'a pas
    /// encore de fenêtre (ex. dans les tests de cette classe, qui n'attachent
    /// pas toujours l'éditeur à une fenêtre réelle) : le panneau lui-même
    /// n'est de toute façon pas testable ici, voir `SlashPanel.swift`.
    private func reposition() {
        guard let textView, let window = textView.window else { return }
        var actualRange = NSRange(location: 0, length: 0)
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: triggerLocation, length: 0),
            actualRange: &actualRange
        )
        panel.show(near: screenRect, on: window.screen)
    }

    private func applySelected() {
        guard selectedIndex >= 0, selectedIndex < flatCommands.count else { return }
        apply(flatCommands[selectedIndex])
    }

    // MARK: - Application d'une commande

    /// Efface le `/` et la requête (piège 2), ferme le menu, puis applique
    /// l'action de `command`. La fermeture précède la mutation du storage :
    /// les `insertText`/`didChangeText()` qui suivent redéclenchent
    /// `Coordinator.textDidChange` pour de vrai (même sans le câblage de la
    /// tâche 6, puisque `EditorTextView.delegate` reste branché), et ce doit
    /// être le pipeline normal — sérialisation, debounce — qui s'exécute à ce
    /// moment-là, pas le court-circuit du menu.
    private func apply(_ command: SlashCommand) {
        guard let textView, let storage = textView.textStorage else {
            close()
            return
        }
        var start = min(triggerLocation, storage.length)
        // Absorbe l'espace qui a validé le déclencheur (`isValidTriggerPosition`
        // n'accepte que début de ligne, `\n`, ou espace juste avant le `/`) :
        // sans ça, convertir une ligne non vide laisserait une espace
        // résiduelle en fin de contenu — invisible à l'écran mais bien réelle
        // dans le markdown sérialisé (`emitInline` ne trime rien). Ne mord
        // jamais sur un `\n`, seulement sur une véritable espace.
        let ns = storage.string as NSString
        if start > 0, ns.character(at: start - 1) == 0x20 /* " " */ {
            start -= 1
        }
        let cursor = min(textView.selectedRange().location, storage.length)
        let clearRange = NSRange(location: start, length: max(0, cursor - start))
        close()

        // `insertText("", replacementRange:)` — vérifié (piège 2) : déclenche
        // le délégué, positionne `pendingStyleRange`, enregistre l'annulation.
        // Une mutation directe de `textStorage` ne déclencherait rien.
        textView.insertText("", replacementRange: clearRange)

        guard let refreshedStorage = textView.textStorage else { return }
        let applyLocation = min(start, refreshedStorage.length)

        switch command.action {
        case .convertBlock(let type):
            applyBlockConversion(type, at: applyLocation, in: textView)
        case .convertList(let kind):
            applyListConversion(kind, at: applyLocation, in: textView)
        case .insertCallout:
            applyCallout(at: applyLocation, in: textView)
        case .insertThematicBreak:
            insertThematicBreak(at: applyLocation, in: textView)
        case .insertCodeBlock:
            insertCodeBlock(at: applyLocation, in: textView)
        case .insertTable:
            insertTable(at: applyLocation, in: textView)
        case .insertImage:
            presentImagePicker { [weak self, weak textView] url in
                guard let self, let textView, let url else { return }
                self.insertImage(url, at: applyLocation, in: textView)
            }
        case .insertDate:
            let anchor = dateAnchorRect(in: textView, at: applyLocation)
            presentDatePicker(textView, anchor) { [weak self, weak textView] selection in
                guard let self, let textView, let selection else { return }
                self.insertDate(selection, at: applyLocation, in: textView)
            }
        case .presentEmojiPicker:
            presentEmojiCharacterPalette(in: textView)
        }
    }

    /// `MarkdownBlockCommands.setBlockType` mute des attributs sur des
    /// caractères **existants** : sur une ligne vide (le cas le plus courant
    /// à l'ouverture du menu — `/` tapé seul sur sa ligne, puis effacé par
    /// `apply`), `MarkdownBlockCommands.lineRange` renvoie une plage de
    /// longueur 0 et la commande ne fait alors rien — mesuré sur la lecture
    /// de son code (`guard range.length > 0 else { return }`). Sans traiter
    /// ce cas, choisir « Titre 1 » sur une ligne vide n'aurait aucun effet
    /// visible. La parade : positionner `typingAttributes` pour que le
    /// **prochain caractère tapé** porte le bon `.mdBlockType` — même
    /// mécanisme que `primeTypingAttributes` utilise aussi pour la ligne non
    /// vide, où il pallie un défaut différent (voir sa doc).
    private func applyBlockConversion(_ type: MarkdownBlockCommands.LineBlockType, at location: Int, in textView: EditorTextView) {
        guard let storage = textView.textStorage else { return }
        let range = MarkdownBlockCommands.lineRange(in: storage, at: location)
        guard range.length > 0 else {
            primeTypingAttributes(blockType: type.blockType, listInfo: nil, in: textView)
            return
        }
        MarkdownBlockCommands.setBlockType(type, in: storage, at: location)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: range)
        textView.didChangeText()
        // Relit le type réellement posé plutôt que de supposer `type.blockType` :
        // `setBlockType` peut retomber sur `.paragraph` si `type` était déjà en
        // place (bascule réversible, cf. sa doc).
        let resultingType = storage.attribute(.mdBlockType, at: range.location, effectiveRange: nil) as? BlockType ?? .paragraph
        primeTypingAttributes(blockType: resultingType, listInfo: nil, in: textView)
    }

    /// Même raisonnement que `applyBlockConversion` pour `setListKind`.
    private func applyListConversion(_ kind: ListInfo.Kind, at location: Int, in textView: EditorTextView) {
        guard let storage = textView.textStorage else { return }
        let range = MarkdownBlockCommands.lineRange(in: storage, at: location)
        guard range.length > 0 else {
            let info = ListInfo(kind: kind, level: 0, index: nil, checked: kind == .task ? false : nil)
            primeTypingAttributes(blockType: .paragraph, listInfo: info, in: textView)
            return
        }
        MarkdownBlockCommands.setListKind(kind, in: storage, at: location)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: range)
        textView.didChangeText()
        let resultingInfo = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) as? ListInfo
        primeTypingAttributes(blockType: .paragraph, listInfo: resultingInfo, in: textView)
    }

    /// Insère un « encadré » (callout) : une citation ordinaire — donc
    /// `applyBlockConversion(.blockquote, …)`, réutilisée sans modification —
    /// précédée du texte littéral `"💡 "`. Aucun mécanisme nouveau : le
    /// round-trip d'une citation est déjà acquis (`> texte`) et
    /// `BlockquoteRuleLayout` peint déjà le filet ; c'est l'emoji en tête de
    /// ligne qui distingue visuellement l'encadré d'une citation ordinaire.
    ///
    /// Le préfixe est inséré **avant** `applyBlockConversion`, en tête de la
    /// ligne du curseur (`range.location`, pas `location` lui-même — `/encadré`
    /// tapé au milieu d'une ligne non vide doit produire `"> 💡 texte"`, pas
    /// `"texte💡 "` ni un préfixe planté au milieu du contenu existant). Cet
    /// ordre garantit aussi que la ligne est **toujours non vide** au moment
    /// où `applyBlockConversion` s'exécute (au pire `"💡 "` seul, sur une
    /// ligne vide au départ) : son unique embranchement réel — celui qui mute
    /// les attributs des caractères existants via
    /// `MarkdownBlockCommands.setBlockType` — s'applique donc uniformément,
    /// sans dupliquer ici sa distinction ligne vide/non vide (déjà traitée en
    /// tête d'`applyBlockConversion`, voir sa doc).
    ///
    /// `stripRiskyTypingAttributes` avant l'insertion du préfixe (piège 6,
    /// même parade que `insertThematicBreak`/`insertTable`/`insertDate`) :
    /// sans ça, un encadré inséré juste après du texte en gras ou du code
    /// inline hériterait de `.mdBold`/`.mdInlineCode` via
    /// `insertText(_:replacementRange:)`, qui fusionne les `typingAttributes`
    /// courants dans le texte simple qu'on lui passe.
    ///
    /// `setSelectedRange(_:)` **avant** de nettoyer les `typingAttributes` —
    /// pas seulement avant d'insérer : mesuré (test `test_applyingCallout_
    /// afterInlineCode_prefixDoesNotInheritInlineCode`, provoqué par mutation
    /// de cet ordre), `typingAttributes` n'est fiable que pour la sélection
    /// *courante* — ici la fin de la requête effacée par `apply()`, qui n'est
    /// pas forcément `range.location` (`/encadré` tapé au milieu d'une ligne
    /// non vide laisse le curseur après le mot précédent, pas en tête de
    /// ligne). Sans ce déplacement d'abord, `insertText` avec un
    /// `replacementRange` distinct de la sélection courante ne consulte pas
    /// `typingAttributes` du tout : il retombe sur les attributs du
    /// caractère voisin du point d'insertion réel — ici potentiellement
    /// `.mdInlineCode` du contenu existant, que `stripRiskyTypingAttributes`
    /// n'aurait alors jamais eu l'occasion de retirer puisqu'il ne modifie
    /// que `typingAttributes`, pas cet attribut de secours.
    private func applyCallout(at location: Int, in textView: EditorTextView) {
        guard let storage = textView.textStorage else { return }
        let range = MarkdownBlockCommands.lineRange(in: storage, at: location)
        let safeLocation = min(range.location, storage.length)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        stripRiskyTypingAttributes(in: textView)
        textView.insertText("💡 ", replacementRange: textView.selectedRange())
        applyBlockConversion(.blockquote, at: safeLocation, in: textView)
    }

    /// Insère une **nouvelle** ligne portant `.mdBlockType = .thematicBreak`,
    /// sans toucher à la ligne du curseur — `MarkdownBlockCommands.setBlockType`
    /// refuse `.thematicBreak` depuis le commit `f20b979` (appliqué à une
    /// ligne existante, il en détruisait le contenu inline à la
    /// sérialisation) ; ce n'est donc pas contourné ici, c'est une insertion.
    /// Forme exacte reprise de `MarkdownParser.emitThematicBreak` (le
    /// caractère `"—"` seul porte `.mdBlockType`, les `"\n"` n'ont aucun
    /// attribut explicite) : c'est la représentation qu'un reparse produit
    /// déjà, round-trip garanti par construction.
    private func insertThematicBreak(at location: Int, in textView: EditorTextView) {
        stripRiskyTypingAttributes(in: textView)
        let insertion = NSMutableAttributedString(string: "\n")
        insertion.append(NSAttributedString(string: "—", attributes: [.mdBlockType: BlockType.thematicBreak]))
        insertion.append(NSAttributedString(string: "\n"))
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        textView.insertText(insertion, replacementRange: NSRange(location: safeLocation, length: 0))
    }

    /// Insère un bloc de code vide comme nouveau bloc au point du curseur,
    /// sans convertir la ligne courante — même stratégie qu'`insertThematicBreak`
    /// (le modèle explicitement désigné) : `.codeBlock` est absent de
    /// `MarkdownBlockCommands.LineBlockType` (voir sa doc), ce n'est donc pas
    /// une conversion.
    ///
    /// Corps initial : **un espace**, pas une chaîne vide — mesuré
    /// (`MarkdownParser.parse("```\n\n```")` donne un `NSAttributedString` de
    /// longueur 0 : `CodeBlock.code`, une fois `trimmingCharacters(in:
    /// .newlines)` appliqué par `MarkdownParser.emitCodeBlock`, devient `""`,
    /// et `NSAttributedString(string: "", attributes:)` ne contribue aucun
    /// caractère à la sortie — impossible d'y accrocher `.mdBlockType`). Un
    /// bloc de code réellement vide ne survit donc à aucun aller-retour texte
    /// complet (sérialisation puis reparse), qu'il vienne de cette insertion
    /// ou d'un bloc fencé tapé à la main ailleurs dans l'app — limite
    /// structurelle du modèle de stockage (un attribut ne peut porter sur
    /// zéro caractère), pas un bug propre à cette insertion. Un espace,
    /// lui, survit intact (vérifié) : `fenceLength`/`fencedCodeBlock` le
    /// traitent comme un corps d'un caractère, ordinaire.
    ///
    /// Représentation, sur le modèle exact d'`insertThematicBreak` (`"\n"` +
    /// caractère de contenu attribué + `"\n"` nu) : `"\n"` (termine la ligne
    /// du curseur) + `" "` porteur de `.mdBlockType = .codeBlock` (le corps
    /// placeholder) + `"\n"` nu (terminateur du bloc, cf.
    /// `MarkdownParser.emitCodeBlock` → `appendNewline`, toujours nu après le
    /// corps).
    ///
    /// L'espace-placeholder est **sélectionné** (pas seulement le curseur
    /// placé avant) après l'insertion : la première frappe de l'utilisateur
    /// le remplace alors nativement plutôt que de s'insérer à côté, évitant
    /// un espace résiduel en tête ou en fin de code.
    private func insertCodeBlock(at location: Int, in textView: EditorTextView) {
        stripRiskyTypingAttributes(in: textView)
        let insertion = NSMutableAttributedString(string: "\n")
        insertion.append(NSAttributedString(string: " ", attributes: [.mdBlockType: BlockType.codeBlock]))
        insertion.append(NSAttributedString(string: "\n"))
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        textView.insertText(insertion, replacementRange: NSRange(location: safeLocation, length: 0))

        guard let storage = textView.textStorage else { return }
        let placeholderRange = NSRange(location: min(safeLocation + 1, storage.length), length: min(1, max(0, storage.length - (safeLocation + 1))))
        textView.setSelectedRange(placeholderRange)
        textView.typingAttributes[.mdBlockType] = BlockType.codeBlock
    }

    /// Insère un tableau GFM de 3 colonnes — la rangée d'en-tête (row 0,
    /// toujours en gras au rendu, cf. `StyleRenderer`) puis 2 rangées de
    /// corps, toutes les cellules vides — comme nouveau bloc au point du
    /// curseur, sans convertir la ligne courante : même stratégie
    /// qu'`insertThematicBreak`, le modèle le plus proche — un tableau
    /// n'a pas d'équivalent `MarkdownBlockCommands.LineBlockType` (voir la
    /// doc de `SlashCommand.Action.insertTable`), donc ce n'est pas une
    /// conversion.
    ///
    /// Squelette retenu : 3 colonnes × 2 lignes de corps plus l'en-tête,
    /// cellules vides, alignement `nil` sur toutes les colonnes (round-trip
    /// en `---` sans `:`) — exactement le squelette du plan. Une seule ligne
    /// de corps aurait aussi bien illustré la grille, mais deux montrent la
    /// continuité verticale entre rangées (le trait de bordure partagé,
    /// cf. `MarkdownTableRenderingTests.
    /// test_table_hasAContinuousVerticalBorderAtTheColumnBoundary`) dès
    /// l'insertion, sans que l'utilisateur ait à ajouter une rangée pour le
    /// constater.
    ///
    /// Représentation : un `\n` nu (termine la ligne du curseur, comme le
    /// `\n` initial d'`insertThematicBreak`) — **sauf** si le curseur est
    /// déjà en tout début de ligne (position 0 du document, ou juste après
    /// un `\n` existant) : ce `\n` nu n'aurait alors rien à terminer, et en
    /// ajouter un quand même produirait une ligne vide superflue en tête du
    /// tableau sérialisé (mesuré : `/tableau` tapé sur un document vierge
    /// sérialise en `"\n| … |\n…"`, un `\n` de tête qui ne survit pas à un
    /// aller-retour — `Document(parsing:)` ne matérialise aucun nœud pour une
    /// ligne vide, donc le reparse le fait disparaître ; stable seulement à
    /// la 2ᵉ passe plutôt qu'à la 1ʳᵉ). Puis une cellule par colonne × rangée
    /// (3×3 = 9), chacune un simple `\n` porteur de `.mdTableCell`
    /// (`TableCellInfo`) — même forme que `MarkdownParser.emitTableRow` pour
    /// une cellule vide (`emitInline` ne produit alors aucun caractère, seul
    /// le `\n` terminal porte l'attribut, cf. sa doc). Aucun `\n` nu
    /// supplémentaire après la dernière cellule : elle porte déjà le sien,
    /// qui joue le rôle de séparateur de bloc — exactement comme
    /// `MarkdownParser.emitTable` lui-même, qui n'ajoute aucun
    /// `appendNewline` après la dernière rangée (contrairement à
    /// `emitBlock`/`emitCodeBlock`/`emitThematicBreak`, qui en ajoutent un
    /// explicitement) : c'est la dernière cellule qui termine le bloc dans
    /// les deux cas, round-trip garanti par construction —
    /// `MarkdownSerializer.tableBlock` retrouve la même frontière.
    private func insertTable(at location: Int, in textView: EditorTextView) {
        stripRiskyTypingAttributes(in: textView)

        let tableID = UUID()
        let columnCount = 3
        let rowCount = 3 // rangée d'en-tête (0) + 2 rangées de corps (1, 2)

        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        let alreadyAtLineStart: Bool = {
            guard safeLocation > 0, let ns = textView.textStorage?.string as NSString? else { return true }
            return ns.character(at: safeLocation - 1) == 0x0A /* "\n" */
        }()

        let insertion = NSMutableAttributedString(string: alreadyAtLineStart ? "" : "\n")
        var firstCellInfo: TableCellInfo?
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let info = TableCellInfo(tableID: tableID, row: row, column: column,
                                         columnCount: columnCount, alignment: nil)
                if firstCellInfo == nil { firstCellInfo = info }
                insertion.append(NSAttributedString(string: "\n", attributes: [.mdTableCell: info]))
            }
        }

        textView.insertText(insertion, replacementRange: NSRange(location: safeLocation, length: 0))

        // Curseur dans la première cellule (row 0, column 0), juste avant son
        // `\n` (juste après le `\n` nu initial quand il a été inséré) : la
        // prochaine frappe s'y insère, poussant ce `\n` sans y toucher.
        guard let info = firstCellInfo, let storage = textView.textStorage else { return }
        let firstCellCursor = min(safeLocation + (alreadyAtLineStart ? 0 : 1), storage.length)
        textView.setSelectedRange(NSRange(location: firstCellCursor, length: 0))
        // `setSelectedRange` recalcule `typingAttributes` d'après le
        // caractère voisin de la nouvelle position — pas garanti porter
        // `.mdTableCell` (même incertitude que celle qui justifie
        // `primeTypingAttributes` après une mutation directe de storage,
        // voir sa doc). On nettoie donc à nouveau les clés à risque, au cas
        // où ce recalcul en aurait réintroduit une, puis on repose
        // explicitement `.mdTableCell` : sans lui, la première frappe de
        // l'utilisateur ne porterait pas cet attribut et
        // `MarkdownSerializer.tableBlock` ne reconnaîtrait plus la cellule
        // (elle vérifie `.mdTableCell` au tout début de la ligne, voir sa
        // doc) — mesuré, voir le rapport de tâche.
        stripRiskyTypingAttributes(in: textView)
        textView.typingAttributes[.mdTableCell] = info
    }

    private func insertImage(_ url: URL, at location: Int, in textView: EditorTextView) {
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        // `insertImagePlaceholder` purge déjà lui-même les attributs inline
        // hérités (`.mdInlineCode`/`.mdBold`/`.mdItalic`/`.mdStrikethrough`/
        // `.mdLink`, cf. sa doc) avant d'insérer — précédent explicitement
        // désigné par le plan, pas dupliqué ici.
        textView.insertImagePlaceholder(for: url)
    }

    /// Insère la date/heure de `selection` comme **lien markdown** —
    /// `docs/superpowers/specs/2026-08-05-dates-et-rappels.md` (chantier 1),
    /// exécuté ici après le popover (chantiers 4/5, livrés avant, voir
    /// l'annotation du 2026-08-06 en tête de la spec) : même patron que
    /// `MentionController.insertMention`, qui insère `"@nom"` porteur de
    /// `.mdLink` vers `MentionCatalog.mentionURL(for:)`.
    ///
    /// Libellé visible : `"@"` + le format français long
    /// (`dateInsertionFormatter` — ex. `"5 août 2026"`), suivi de l'heure
    /// (`timeInsertionFormatter` — ex. `"13:08"`) séparée par une espace si
    /// `selection.includesTime` est vrai (ex. `"@6 août 2026 13:08"`) — pas de
    /// risque d'échappement à la sérialisation, aucun de ces caractères ne
    /// figurant dans `MarkdownEscaping.inlineSpecials` (voir la justification
    /// détaillée conservée sur `dateInsertionFormatter`/`timeInsertionFormatter`
    /// ci-dessous) ; `[` et `]` (la syntaxe de lien elle-même) sont émis
    /// structurellement par `MarkdownSerializer`, pas par ce texte.
    ///
    /// URL : `DateLinkCatalog.dateURL(date:includesTime:reminder:)`, qui
    /// porte `selection.reminder` — contrairement à l'ancienne insertion en
    /// texte brut, le rappel choisi survit désormais à l'enregistrement
    /// (donnée conservée dans l'URL ; sa planification effective reste hors
    /// périmètre, chantier 3 de la spec).
    ///
    /// `stripRiskyTypingAttributes` (piège 6, même parade que pour le
    /// séparateur/le tableau) avant l'insertion : sans ça, une date insérée
    /// juste après du code inline ou du gras hériterait de
    /// `.mdInlineCode`/`.mdBold` via `insertText(_:replacementRange:)`, qui
    /// fusionne les `typingAttributes` courants dans la chaîne attribuée
    /// qu'on lui passe pour toute clé qu'elle ne porte pas déjà elle-même —
    /// `.mdLink`, lui, est fourni explicitement sur `insertion` et n'est donc
    /// jamais écrasé par cette fusion (même raisonnement que
    /// `MentionController.insertMention`, cf. sa doc).
    private func insertDate(_ selection: SlashDateSelection, at location: Int, in textView: EditorTextView) {
        stripRiskyTypingAttributes(in: textView)
        var text = "@" + Self.dateInsertionFormatter.string(from: selection.date)
        if selection.includesTime {
            text += " " + Self.timeInsertionFormatter.string(from: selection.date)
        }
        let url = DateLinkCatalog.dateURL(date: selection.date, includesTime: selection.includesTime, reminder: selection.reminder)
        let insertion = NSAttributedString(string: text, attributes: [.mdLink: url])
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        textView.insertText(insertion, replacementRange: NSRange(location: safeLocation, length: 0))
    }

    /// Ouvre le sélecteur d'emoji système (`presentEmojiPicker`, injecté —
    /// voir sa doc pour la limite connue : aucun callback, aucune
    /// vérification possible de ce qui est réellement inséré).
    /// `stripRiskyTypingAttributes` **avant** l'ouverture (piège 6, même
    /// parade que pour le séparateur/la date) : la palette insère l'emoji
    /// choisi dans le premier répondant via `typingAttributes`, comme une
    /// frappe normale — sans ce nettoyage, un emoji choisi juste après du
    /// texte en gras ou du code inline hériterait de `.mdBold`/`.mdInlineCode`.
    private func presentEmojiCharacterPalette(in textView: EditorTextView) {
        stripRiskyTypingAttributes(in: textView)
        presentEmojiPicker()
    }

    /// Format de la partie date de l'entrée « Date » — voir `insertDate`
    /// pour la justification du choix (`dateStyle = .long`, locale `fr_FR`)
    /// contre `MarkdownEscaping.inlineSpecials`. Internal (pas `private`) :
    /// les tests et `SlashDatePickerContent` (aperçu affiché dans le
    /// popover) s'y réfèrent directement plutôt que de dupliquer sa
    /// configuration (et risquer une divergence silencieuse, ex. de fuseau
    /// horaire, entre le format affiché/testé et le format réellement
    /// inséré).
    static let dateInsertionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter
    }()

    /// Format de la partie heure, ajoutée après `dateInsertionFormatter` par
    /// `insertDate` quand « Inclure l'heure » est activé. `dateFormat =
    /// "HH:mm"` explicite plutôt que `timeStyle` : garantit le séparateur
    /// (`:`, absent d'`MarkdownEscaping.inlineSpecials`) indépendamment de la
    /// locale, là où `timeStyle` pourrait un jour produire une espace
    /// insécable ou la lettre `h` selon la locale/version d'OS — vérifié pour
    /// `fr_FR`/macOS actuel (`"13:08"` dans les deux cas), mais `dateFormat`
    /// explicite retire toute dépendance à ce comportement système. Internal
    /// pour la même raison que `dateInsertionFormatter`.
    static let timeInsertionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter
    }()

    /// Rectangle écran à l'emplacement d'insertion (`location`) — sert
    /// d'ancrage au popover du sélecteur de date (`presentDatePicker`).
    /// Même API que `reposition()` (le repositionnement de `SlashPanel`) :
    /// `firstRect(forCharacterRange:actualRange:)`, vérifiée sur cette pile
    /// TextKit 1. `.zero` si la vue n'a pas encore de fenêtre — même garde
    /// que `reposition()`, pour la même raison (comportement non garanti
    /// sans fenêtre ; sans conséquence en pratique, l'entrée « Date » n'est
    /// accessible qu'une fois l'éditeur affiché à l'écran).
    private func dateAnchorRect(in textView: EditorTextView, at location: Int) -> NSRect {
        guard textView.window != nil else { return .zero }
        var actualRange = NSRange(location: 0, length: 0)
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        return textView.firstRect(
            forCharacterRange: NSRange(location: safeLocation, length: 0),
            actualRange: &actualRange
        )
    }

    /// Ouvre un vrai sélecteur de fichier (implémentation par défaut de
    /// `presentImagePicker`). `runModal()` plutôt qu'un `.begin` asynchrone :
    /// même style que le seul autre usage de `NSOpenPanel` du projet
    /// (`BackupService.openBackupPanel`) — bloquant, ce qui est le
    /// comportement attendu d'un sélecteur de fichier modal.
    static func presentImageOpenPanel(_ completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        completion(panel.runModal() == .OK ? panel.url : nil)
    }

    /// Ouvre le vrai sélecteur de date (implémentation par défaut de
    /// `presentDatePicker`) : un popover (`SlashDatePickerPresenter`, voir sa
    /// doc pour le choix d'`NSPopover` plutôt que le modèle non-activant de
    /// `SlashPanel`) ancré près de `screenRect`, initialisé sur la date du
    /// jour — jamais la date de référence d'AppKit (1ᵉʳ janvier 2001), qui
    /// était le bug de l'ancienne `NSAlert`/`NSDatePicker` (voir la doc de la
    /// propriété `presentDatePicker` pour le détail du bug).
    @MainActor
    static func presentDatePickerPopover(
        _ anchorView: EditorTextView,
        _ screenRect: NSRect,
        _ completion: @escaping (SlashDateSelection?) -> Void
    ) {
        SlashDatePickerPresenter.shared.present(near: screenRect, in: anchorView, initialDate: Date(), completion: completion)
    }

    /// Ouvre le vrai panneau « Caractères » d'AppKit (implémentation par
    /// défaut de `presentEmojiPicker`) — sélecteur système standard, déjà
    /// utilisé ailleurs sur macOS (menu Édition › Emoji et symboles) ; ce
    /// projet n'en construit pas de substitut. `orderFrontCharacterPalette(nil)`
    /// cible le premier répondant courant, pas une vue précise passée en
    /// paramètre — c'est pourquoi cette closure, contrairement à
    /// `presentImagePicker`/`presentDatePicker`, ne reçoit ni vue ni
    /// callback (voir la doc de la propriété `presentEmojiPicker`).
    @MainActor
    static func presentCharacterPalette() {
        NSApp.orderFrontCharacterPalette(nil)
    }

    // MARK: - Attributs de frappe hérités (piège 6)

    /// Clés `md*` à retirer de `typingAttributes` avant une insertion qui
    /// doit démarrer un contexte neuf plutôt que d'hériter de celui de la
    /// ligne courante — même parade qu'`EditorTextView.insertImagePlaceholder`
    /// (`inlineAttributesToStripBeforeImageInsertion`), étendue ici à
    /// `.mdBlockType`/`.mdListInfo` : un séparateur n'est ni un titre, ni un
    /// item de liste, quelle que soit la ligne d'où il est inséré. Sans ce
    /// nettoyage, `insertText` complète les clés absentes de la chaîne
    /// insérée avec les `typingAttributes` courants (vérifié empiriquement
    /// pour le cas de l'image, cf. doc-comment cité) — les deux `"\n"`
    /// entourant le séparateur en hériteraient sinon.
    private static let riskyTypingAttributeKeys: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink,
        .mdBlockType, .mdListInfo
    ]

    private func stripRiskyTypingAttributes(in textView: EditorTextView) {
        for key in Self.riskyTypingAttributeKeys {
            textView.typingAttributes.removeValue(forKey: key)
        }
    }

    /// Positionne `typingAttributes` pour que la prochaine frappe hérite du
    /// type de bloc/liste qu'on vient d'appliquer. `NSTextView` ne rafraîchit
    /// `typingAttributes` qu'au déplacement du curseur (`setSelectedRange`
    /// et assimilés) — jamais après une mutation directe de `NSTextStorage`,
    /// celle que fait `MarkdownBlockCommands` : sans cet appel, du texte tapé
    /// juste après une conversion sur une ligne **non vide** garderait
    /// l'ancien type malgré l'attribut déjà changé sur les caractères
    /// existants. Sert aussi la ligne **vide** (voir `applyBlockConversion`),
    /// où c'est la seule action effective.
    private func primeTypingAttributes(blockType: BlockType, listInfo: ListInfo?, in textView: EditorTextView) {
        textView.typingAttributes[.mdBlockType] = blockType
        if let listInfo {
            textView.typingAttributes[.mdListInfo] = listInfo
        } else {
            textView.typingAttributes.removeValue(forKey: .mdListInfo)
        }
    }

    // MARK: - Piège 4 : le type de bloc ne doit pas survivre au Retour après un titre

    /// Mesuré : `"## Titre"` + ⏎ + `"corps"` donne `"## Titre\n## corps"` —
    /// `typingAttributes` hérite `.mdBlockType = .h2` du caractère précédant
    /// le curseur (la fin de « Titre »), et rien ne l'override sur
    /// `insertNewline`. Général, pas limité aux titres appliqués par ce menu
    /// (voir `handle(commandSelector:)`) : le mécanisme est le même quelle
    /// que soit l'origine du titre. Souhaitable pour une liste (poursuivre la
    /// liste au retour) — non touché ici, cette méthode ne s'applique qu'aux
    /// titres.
    ///
    /// Ne traite que le curseur sans sélection (`selection.length == 0`) :
    /// remplacer une sélection non vide par un retour est un cas plus large,
    /// non mesuré, laissé au comportement par défaut.
    private func breakOutOfHeadingIfNeeded() -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location > 0 else { return false }
        guard let currentType = storage.attribute(.mdBlockType, at: selection.location - 1, effectiveRange: nil) as? BlockType,
              Self.isHeading(currentType) else { return false }

        textView.typingAttributes[.mdBlockType] = BlockType.paragraph
        textView.typingAttributes.removeValue(forKey: .mdListInfo)
        let insertion = NSAttributedString(string: "\n", attributes: [.mdBlockType: BlockType.paragraph])
        textView.insertText(insertion, replacementRange: selection)
        return true
    }

    private static func isHeading(_ type: BlockType) -> Bool {
        switch type {
        case .h1, .h2, .h3, .h4, .h5, .h6: return true
        case .paragraph, .blockquote, .codeBlock, .thematicBreak, .rawBlock: return false
        }
    }

    // MARK: - Sortie du bloc de code

    /// ⏎ sur une ligne vide **à l'intérieur** d'un bloc de code en sort,
    /// revient au paragraphe — même geste que
    /// `ListEditingCommands.exitEmptyListItem` pour un item de liste vide
    /// (inspiration explicitement désignée par la tâche), transposé au bloc
    /// de code : sans lui, le curseur resterait piégé — `setBlockType`/
    /// `setListKind` (`MarkdownBlockCommands`) refusent tous deux d'opérer
    /// sur une ligne `.codeBlock` (gardes délibérées, voir leur doc), et
    /// aucune conversion via le menu `/` ne peut donc en sortir. Une ligne
    /// **non vide** (le cas courant : le corps du code) n'est **pas** traitée
    /// ici — ⏎ y garde son comportement par défaut, qui insère un `"\n"`
    /// héritant `.mdBlockType = .codeBlock` de `typingAttributes` (continue
    /// le bloc sur une ligne de plus, sans code dédié à ce cas : c'est déjà
    /// le comportement natif d'`NSTextView`).
    ///
    /// Détection du type de bloc **en arrière** (le caractère qui précède le
    /// curseur), pas en avant comme `ListEditingCommands.currentListInfo` —
    /// mesuré : un bloc de code n'est **pas** structuré comme une liste. Une
    /// liste attribue `.mdListInfo` à **chaque** `"\n"` d'item (« contenu +
    /// retour à la ligne », cf. sa doc) ; un bloc de code est un unique run
    /// (`MarkdownParser.emitCodeBlock` : `attrs` posé une fois sur tout le
    /// corps, retours à la ligne internes compris) suivi d'un **seul**
    /// terminateur final nu (`appendNewline`, jamais attribué). Le `"\n"`
    /// qu'`NSTextView` insère par défaut pour continuer le bloc (cas non vide
    /// ci-dessus) hérite `.mdBlockType` de `typingAttributes` et rejoint donc
    /// ce run par continuité d'attribut — mais le terminateur nu du bloc,
    /// lui, reste toujours en aval, jamais rattrapé. Un contrôle en avant (au
    /// terminateur de la ligne vide courante) y lirait donc systématiquement
    /// `nil`/`.paragraph`, jamais `.codeBlock` — mesuré (`handled == false`
    /// au 2ᵉ ⏎ avec une première version qui lisait en avant, voir le
    /// rapport de tâche) : le bug que cette version corrige.
    ///
    /// Ne traite que le curseur sans sélection (`selection.length == 0`) —
    /// même restriction qu'`breakOutOfHeadingIfNeeded`/`ListEditingCommands
    /// .handleReturn`, un cas plus large non mesuré.
    private func exitEmptyCodeBlockIfNeeded() -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location > 0 else { return false }

        let contentRange = MarkdownBlockCommands.lineRange(in: storage, at: selection.location)
        guard contentRange.length == 0 else { return false }
        guard storage.attribute(.mdBlockType, at: selection.location - 1, effectiveRange: nil) as? BlockType == .codeBlock else {
            return false
        }

        // Recolore le `"\n"` qui précède le curseur (celui que le ⏎ précédent
        // vient d'ajouter au run du bloc, voir la doc ci-dessus) en paragraphe :
        // referme visuellement le bloc à cet endroit — sans effet sur la
        // sérialisation (`MarkdownSerializer.fencedCodeBlock` rogne de toute
        // façon les retours à la ligne de fin du corps, `trimmingTrailingNewlines`),
        // mais évite qu'une ligne vide sans code garde le fond visuel du bloc.
        let newlineRange = NSRange(location: selection.location - 1, length: 1)
        storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: newlineRange)
        storage.removeAttribute(.mdCodeLanguage, range: newlineRange)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: newlineRange)
        textView.didChangeText()

        textView.typingAttributes[.mdBlockType] = BlockType.paragraph
        textView.typingAttributes.removeValue(forKey: .mdCodeLanguage)
        return true
    }
}
