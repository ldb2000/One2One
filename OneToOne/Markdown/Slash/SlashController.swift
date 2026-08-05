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

    /// `panel` et `presentImagePicker` n'ont volontairement pas de valeur par
    /// défaut : un défaut faisant appel à un initialiseur/une méthode
    /// `@MainActor` depuis une position de paramètre par défaut échoue à la
    /// compilation en mode Swift 6 (isolation d'acteur d'une expression de
    /// défaut non résolue au contexte de l'appelant) — mesuré. L'appelant
    /// (tâche 6, ou un test) passe explicitement `SlashPanel()` et
    /// `SlashController.presentImageOpenPanel`.
    init(
        textView: EditorTextView,
        features: Set<MarkdownFeature>,
        panel: SlashPanel,
        cancelPendingWrite: @escaping () -> Void,
        presentImagePicker: @escaping (@escaping (URL?) -> Void) -> Void
    ) {
        self.textView = textView
        self.features = features
        self.panel = panel
        self.cancelPendingWrite = cancelPendingWrite
        self.presentImagePicker = presentImagePicker
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
    /// l'origine du titre.
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
            return breakOutOfHeadingIfNeeded()
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
        case .insertThematicBreak:
            insertThematicBreak(at: applyLocation, in: textView)
        case .insertImage:
            presentImagePicker { [weak self, weak textView] url in
                guard let self, let textView, let url else { return }
                self.insertImage(url, at: applyLocation, in: textView)
            }
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

    private func insertImage(_ url: URL, at location: Int, in textView: EditorTextView) {
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        // `insertImagePlaceholder` purge déjà lui-même les attributs inline
        // hérités (`.mdInlineCode`/`.mdBold`/`.mdItalic`/`.mdStrikethrough`/
        // `.mdLink`, cf. sa doc) avant d'insérer — précédent explicitement
        // désigné par le plan, pas dupliqué ici.
        textView.insertImagePlaceholder(for: url)
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
}
