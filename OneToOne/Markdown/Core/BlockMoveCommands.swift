import AppKit

/// ⌥↑ / ⌥↓ — déplace le bloc entier portant le curseur au-dessus du bloc
/// précédent (⌥↑) ou en dessous du bloc suivant (⌥↓), curseur inclus. Geste
/// clavier substitué au glisser-déposer d'AppFlowy : `EditorTextView` ne gère
/// que `mouseDown`, aucune infrastructure de survol/drag n'existe — un
/// raccourci donne le même geste utile pour une fraction du coût.
///
/// Routé depuis `EditorTextView.keyDown(with:)` via la closure
/// `onOptionVerticalArrow` — **pas** `Coordinator.textView(_:doCommandBy:)`,
/// contrairement à `ListEditingCommands` : mesuré, ⌥↑/⌥↓ résout (voir
/// `StandardKeyBinding.dict`) en DEUX sélecteurs `doCommandBy:` par frappe,
/// chacun partagé avec un tout autre raccourci (`^b`/`^a` pour ⌥↑, `^f`/`^e`
/// pour ⌥↓) — les intercepter à ce niveau détournerait ces derniers aussi.
/// Voir la doc de `EditorTextView.keyDown(with:)`.
///
/// Bloc au sens `BlockRange` : une ligne logique (paragraphe, item de liste,
/// titre, citation) ou, pour les trois cas qui dépassent la ligne, le bloc
/// markdown entier (bloc de code, tableau, bloc brut) — jamais fragmenté par
/// le déplacement.
enum BlockMoveCommands {

    /// ⌥↑. `false` (aucun effet, pas de crash) si le bloc du curseur est déjà
    /// le premier du document — ou si l'éditeur est en lecture seule :
    /// `swapAdjacentBlocks` mute le storage sans bracket
    /// `shouldChangeText`, la garde d'éditabilité doit donc vivre ici (elle
    /// couvre à la fois ⌥↑/⌥↓ et les entrées Monter/Descendre du menu de
    /// bloc).
    @discardableResult
    static func moveUp(in textView: NSTextView) -> Bool {
        guard textView.isEditable, let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        let current = BlockRange.of(in: storage, at: selection.location)
        guard let previous = previousBlock(of: current, in: storage) else { return false }

        swapAdjacentBlocks(first: previous, second: current, in: textView, storage: storage)

        let offset = offsetWithinBlock(selection: selection, block: current)
        textView.setSelectedRange(NSRange(location: previous.range.location + offset, length: 0))
        return true
    }

    /// ⌥↓. `false` si le bloc du curseur est déjà le dernier du document —
    /// ou si l'éditeur est en lecture seule (voir `moveUp`).
    @discardableResult
    static func moveDown(in textView: NSTextView) -> Bool {
        guard textView.isEditable, let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        let current = BlockRange.of(in: storage, at: selection.location)
        guard let next = nextBlock(of: current, in: storage) else { return false }

        let separatorLength = next.range.location - (current.range.location + current.range.length)
        swapAdjacentBlocks(first: current, second: next, in: textView, storage: storage)

        let offset = offsetWithinBlock(selection: selection, block: current)
        let newStart = current.range.location + next.range.length + separatorLength
        textView.setSelectedRange(NSRange(location: newStart + offset, length: 0))
        return true
    }

    // MARK: - Glisser-déposer

    /// Réécriture **pure** de la plage combinée d'un glisser-déposer de bloc
    /// (`EditorTextView.performDragOperation`) : retire `blockRange` — plus
    /// son `\n` séparateur s'il le suit — puis le réinsère à
    /// `insertionIndex` en garantissant un séparateur de chaque côté de la
    /// jointure. L'ancien algorithme insérait le bloc tel quel : déplacer le
    /// **dernier** bloc (sans `\n` final) ou déposer **en fin** de document
    /// collait deux blocs sur la même ligne (`"A\nB"` → `"BA\n"`).
    ///
    /// `blockRange` et `insertionIndex` sont exprimés dans le repère de
    /// `combined`. Renvoie `nil` si le dépôt tombe dans la plage déplacée
    /// (geste sans effet) ou hors bornes. `blockLocation` est la position du
    /// bloc déplacé dans le texte réécrit, pour reposer sélection et cadre
    /// de bloc.
    static func dragRewrite(
        combined: NSAttributedString, blockRange: NSRange, insertionIndex: Int
    ) -> (text: NSAttributedString, blockLocation: Int)? {
        let ns = combined.string as NSString
        guard blockRange.location >= 0, NSMaxRange(blockRange) <= ns.length,
              insertionIndex >= 0, insertionIndex <= ns.length
        else { return nil }

        let afterBlock = NSMaxRange(blockRange)
        let hasSeparator = afterBlock < ns.length && ns.character(at: afterBlock) == 0x0A
        let removalRange = NSRange(location: blockRange.location,
                                   length: blockRange.length + (hasSeparator ? 1 : 0))
        guard insertionIndex <= blockRange.location || insertionIndex >= NSMaxRange(removalRange)
        else { return nil }

        let block = combined.attributedSubstring(from: blockRange)
        let result = NSMutableAttributedString(attributedString: combined)
        result.deleteCharacters(in: removalRange)

        let insertAt = insertionIndex > blockRange.location
            ? insertionIndex - removalRange.length
            : insertionIndex

        // Le séparateur inséré est un `\n` nu : ses attributs visuels sont
        // recalculés par le restyle qui suit toute réécriture de plage.
        let piece = NSMutableAttributedString(attributedString: block)
        var blockLocation = insertAt
        if insertAt < result.length {
            piece.append(NSAttributedString(string: "\n"))
        } else if insertAt > 0, (result.string as NSString).character(at: insertAt - 1) != 0x0A {
            piece.insert(NSAttributedString(string: "\n"), at: 0)
            blockLocation += 1
        }
        result.insert(piece, at: insertAt)
        return (result, blockLocation)
    }

    // MARK: - Curseur

    /// Position du curseur relative au début du bloc déplacé, avant le
    /// déplacement — reportée telle quelle sur le nouveau départ du bloc
    /// après coup : « le curseur suit le bloc ».
    private static func offsetWithinBlock(selection: NSRange, block: BlockRange) -> Int {
        max(0, min(selection.location - block.range.location, block.range.length))
    }

    // MARK: - Bloc voisin

    /// Bloc juste avant `block`, ou `nil` si `block` commence déjà en tout
    /// début de storage. `block.range.location - 1` est la position du
    /// séparateur (typiquement un simple `\n`, sans attribut de bloc) qui
    /// termine le bloc précédent — pas un caractère de son propre contenu.
    /// `NSString.lineRange(for:)` sondé là renvoie la **ligne physique**
    /// terminée par ce séparateur, dont le début porte lui les attributs du
    /// bloc précédent (dernière ligne d'un bloc de code/brut/tableau
    /// multi-ligne, ou seule ligne d'un bloc simple) — `BlockRange.of` sondé
    /// à ce début résout alors le bloc précédent en entier, pas seulement sa
    /// dernière ligne.
    private static func previousBlock(of block: BlockRange, in storage: NSTextStorage) -> BlockRange? {
        guard block.range.location > 0 else { return nil }
        let ns = storage.string as NSString
        let physicalLastLineStart = ns.lineRange(for: NSRange(location: block.range.location - 1, length: 0)).location
        return BlockRange.of(in: storage, at: physicalLastLineStart)
    }

    /// Bloc juste après `block`, ou `nil` s'il n'y a rien après son
    /// séparateur (dernier bloc réel du document) ou pas de séparateur du
    /// tout (bloc qui va jusqu'à la fin du storage, sans `\n` final).
    private static func nextBlock(of block: BlockRange, in storage: NSTextStorage) -> BlockRange? {
        let afterContent = block.range.location + block.range.length
        guard afterContent < storage.length else { return nil }
        let nextStart = afterContent + 1
        guard nextStart < storage.length else { return nil }
        return BlockRange.of(in: storage, at: nextStart)
    }

    // MARK: - Échange

    /// Échange deux blocs adjacents (`first` précède `second`, rien d'autre
    /// entre les deux) : coupe la plage combinée
    /// `[first.range.location, second.range.upperBound[` et la réécrit
    /// `second` + séparateur + `first`, séparateur inclus tel quel (et ses
    /// attributs éventuels — ex. le `\n` d'une cellule de tableau porte
    /// `.mdTableCell`) — un pur échange de position, aucun texte ni attribut
    /// recalculé.
    ///
    /// N'utilise **pas** `shouldChangeText(in:replacementString:)`/
    /// `didChangeText()` en bracket autour de la mutation : mesuré (un
    /// premier geste de déplacement, cf. rapport de tâche), ce bracket
    /// n'enregistre rien auprès d'`undoManager` pour une mutation faite
    /// directement sur `NSTextStorage` — seule la variante `NSTextView`
    /// (`replaceCharacters(in:with: String)`, qui n'accepte pas de texte
    /// attribué et détruirait donc tous les attributs `md*` du bloc déplacé)
    /// bénéficierait de l'enregistrement automatique. `applyTaskToggle`
    /// documentait déjà ce même piège pour un attribut seul ; il vaut aussi
    /// pour un remplacement de plage entière. Parade : enregistrement
    /// manuel de l'inverse auprès d'`undoManager`, même schéma que
    /// `EditorTextView.applyTaskToggle` — `swapAdjacentBlocks` réenregistre
    /// son propre inverse à chaque exécution (échange initial, annulation,
    /// rétablissement), ce qui fait fonctionner ⌘Z et ⇧⌘Z symétriquement
    /// sans code dédié à chacun. `didChangeText()` est appelé à la main pour
    /// notifier `Coordinator.textDidChange` (sérialisation vers le binding),
    /// après un restyle explicite de `combinedRange` — sans lui,
    /// `Coordinator.textDidChange` ne restylerait que `pendingStyleRange`
    /// (jamais mis à jour ici, faute de passer par `shouldChangeTextIn:`),
    /// laissant un style visuel obsolète sur le texte déplacé.
    private static func swapAdjacentBlocks(first: BlockRange, second: BlockRange,
                                           in textView: NSTextView, storage: NSTextStorage) {
        let separatorLocation = first.range.location + first.range.length
        let separatorRange = NSRange(location: separatorLocation, length: second.range.location - separatorLocation)
        let combinedRange = NSRange(location: first.range.location,
                                    length: second.range.location + second.range.length - first.range.location)

        let firstChunk = storage.attributedSubstring(from: first.range)
        let separatorChunk = storage.attributedSubstring(from: separatorRange)
        let secondChunk = storage.attributedSubstring(from: second.range)

        let swapped = NSMutableAttributedString(attributedString: secondChunk)
        swapped.append(separatorChunk)
        swapped.append(firstChunk)

        storage.beginEditing()
        storage.replaceCharacters(in: combinedRange, with: swapped)
        storage.endEditing()
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: combinedRange)
        textView.didChangeText()

        // `second` occupe maintenant l'ancienne position de `first`, et
        // vice-versa (mêmes longueurs, juste permutées) : reconstruit les
        // deux `BlockRange` à leur nouvelle position pour que l'inverse
        // enregistré ci-dessous rejoue exactement le même échange, en sens
        // opposé.
        let newFirstRange = NSRange(location: first.range.location, length: second.range.length)
        let newSecondRange = NSRange(location: newFirstRange.location + newFirstRange.length + separatorRange.length,
                                     length: first.range.length)
        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            swapAdjacentBlocks(first: BlockRange(range: newFirstRange), second: BlockRange(range: newSecondRange),
                              in: tv, storage: storage)
        }
    }
}
