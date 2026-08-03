# Éditeur — Fondations : aller-retour fiable et images affichées

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre l'aller-retour markdown fiable pour les blocs multi-lignes et les images, puis afficher les images dans l'éditeur — les fondations sans lesquelles mermaid ne peut pas être ajouté.

**Architecture:** `MarkdownSerializer` passe d'une émission ligne-à-ligne à une émission par *run d'attributs* pour les blocs fencés. Les images deviennent un caractère `U+FFFC` porteur de deux attributs (`mdImageURL`, `mdImageAlt`), affiché via un `NSTextAttachment` mis en cache. `ImagePasteService` déménage dans le module markdown sous le nom `MediaStore`.

**Tech Stack:** Swift 6, AppKit (`NSTextView`, `NSTextStorage`, `NSTextAttachment`, TextKit 1), `swift-markdown` (Apple), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-03-editeur-slash-blocs-design.md` — couvre l'étape 1 (unification) et l'étape 2 (attachments + images). Le menu `/` et mermaid font l'objet de plans séparés.

---

## Contexte : deux défauts confirmés par lecture du code

**1. Les blocs de code multi-lignes ne font pas l'aller-retour.**
`MarkdownParser.emitCodeBlock` (`MarkdownParser.swift:138-144`) stocke le corps du bloc comme **une seule suite d'attributs contenant des `\n`**. `MarkdownSerializer.serialize` (`MarkdownSerializer.swift:18-30`) découpe sur les `\n` et appelle `emitParagraph` par ligne, qui réémet une paire de fences complète à chaque fois. Entrée `` ```swift\nprint(1)\nprint(2)\n``` `` → sortie `` ```swift\nprint(1)\n```\n```swift\nprint(2)\n``` ``. Aucune fixture de `MarkdownRoundTripTests.swift:9-21` ne contient de bloc fencé, d'où l'absence de détection.

**2. Les images perdent leur URL.**
`MarkdownParser.emitInlineNode` (`MarkdownParser.swift:158-206`) n'a pas de cas `Image`. Le nœud tombe dans `default:` qui descend dans ses enfants, c'est-à-dire le texte alternatif. `![Plan](file:///x.png)` devient le texte `Plan` et l'URL disparaît définitivement au premier enregistrement.

Le défaut 1 doit être corrigé avant tout ajout : mermaid est un bloc fencé multi-ligne.

---

## File map

| Chemin | Responsabilité | Action |
|---|---|---|
| `Tests/MarkdownRoundTripTests.swift` | fixtures d'aller-retour | modifier |
| `OneToOne/Markdown/Markdown/MarkdownSerializer.swift` | `NSAttributedString` → markdown | modifier |
| `OneToOne/Markdown/Markdown/MarkdownParser.swift` | markdown → `NSAttributedString` | modifier |
| `OneToOne/Markdown/Model/MarkdownAttributeKeys.swift` | clés d'attributs | modifier |
| `OneToOne/Markdown/Blocks/ImageAttachmentFactory.swift` | URL → `NSTextAttachment` mis en cache | créer |
| `Tests/ImageAttachmentFactoryTests.swift` | mise à l'échelle, cache | créer |
| `OneToOne/Markdown/Media/MediaStore.swift` | sauvegarde disque des images | créer (déplacement) |
| `OneToOne/Markdown/Core/StyleRenderer.swift` | attributs → affichage | modifier |
| `OneToOne/Markdown/Core/EditorTextView.swift` | `NSTextView` sous-classé | modifier |
| `OneToOne/Views/EditableTextField.swift` | ancien emplacement d'`ImagePasteService` | modifier |

---

### Task 1 : prouver le défaut des blocs de code multi-lignes

**Files:**
- Test: `Tests/MarkdownRoundTripTests.swift`

- [ ] **Step 1 : ajouter les fixtures manquantes**

Dans `Tests/MarkdownRoundTripTests.swift`, ajouter à la fin du tableau `fixtures` (après `"Mix _italic_ and **bold** here"`, en ajoutant une virgule à cette ligne) :

```swift
        // Blocs fencés — non couverts jusqu'ici.
        // Pas de ligne vide entre les blocs : `MarkdownParser.appendNewline`
        // n'en émet qu'une seule après chaque bloc, donc `\n\n` en entrée
        // ressortirait en `\n` et ferait échouer le test pour une raison
        // étrangère à ce qu'on cherche à prouver.
        "```swift\nprint(1)\n```",
        "```swift\nlet a = 1\nlet b = 2\nprint(a + b)\n```",
        "```\nsans langage\nsur deux lignes\n```",
        "texte avant\n```json\n{\n  \"a\": 1\n}\n```\ntexte après"
```

- [ ] **Step 2 : lancer les tests et constater l'échec**

```bash
swift test --filter MarkdownRoundTripTests
```

Attendu : ÉCHEC. Les fixtures d'une seule ligne passent ; celles de plusieurs lignes échouent avec une sortie où chaque ligne du corps est entourée de sa propre paire de fences.

- [ ] **Step 3 : committer le test rouge**

```bash
git add Tests/MarkdownRoundTripTests.swift
git commit -m "test(markdown): fixtures d'aller-retour pour blocs de code fencés (rouge)"
```

---

### Task 2 : émettre les blocs fencés par run d'attributs

**Files:**
- Modify: `OneToOne/Markdown/Markdown/MarkdownSerializer.swift:13-35`

- [ ] **Step 1 : remplacer `serialize` et ajouter le détecteur de bloc fencé**

Remplacer intégralement la méthode `serialize` (lignes 13 à 35) par :

```swift
    /// Émet une ligne markdown par paragraphe, sauf pour les blocs fencés qui
    /// sont émis d'un seul tenant. Le parser stocke le corps d'un bloc de code
    /// comme un unique run d'attributs contenant des `\n` ; le découper ligne à
    /// ligne produirait une paire de fences par ligne.
    /// Une éventuelle ligne vide finale est supprimée : elle reviendrait sinon
    /// sous forme de paragraphe vide supplémentaire.
    static func serialize(_ source: NSAttributedString) -> String {
        guard source.length > 0 else { return "" }
        var lines: [String] = []
        let ns = source.string as NSString
        var cursor = 0

        while cursor < source.length {
            if let fence = fencedCodeBlock(in: source, at: cursor, ns: ns) {
                lines.append(fence.markdown)
                cursor = fence.nextCursor
                continue
            }

            var paragraphEnd = cursor
            while paragraphEnd < source.length, ns.character(at: paragraphEnd) != 0x0A {
                paragraphEnd += 1
            }
            if paragraphEnd > cursor {
                let range = NSRange(location: cursor, length: paragraphEnd - cursor)
                lines.append(emitParagraph(source: source, range: range))
            } else {
                lines.append("")
            }
            cursor = paragraphEnd + 1
        }

        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Si un bloc de code commence à `cursor`, renvoie son markdown complet et
    /// la position juste après le bloc — saut de ligne de séparation compris,
    /// celui que `MarkdownParser.appendNewline` ajoute après chaque bloc.
    /// Renvoie `nil` quand `cursor` n'est pas sur un bloc de code.
    private static func fencedCodeBlock(in source: NSAttributedString,
                                        at cursor: Int,
                                        ns: NSString) -> (markdown: String, nextCursor: Int)? {
        var effective = NSRange(location: NSNotFound, length: 0)
        let searchRange = NSRange(location: cursor, length: source.length - cursor)
        let block = source.attribute(.mdBlockType,
                                     at: cursor,
                                     longestEffectiveRange: &effective,
                                     in: searchRange) as? BlockType
        guard block == .codeBlock, effective.length > 0 else { return nil }

        let language = source.attribute(.mdCodeLanguage, at: cursor, effectiveRange: nil) as? String ?? ""
        let body = ns.substring(with: effective)
        var next = effective.location + effective.length
        if next < source.length, ns.character(at: next) == 0x0A {
            next += 1
        }
        return ("```\(language)\n\(body)\n```", next)
    }
```

- [ ] **Step 2 : supprimer le cas `.codeBlock` devenu mort dans `emitParagraph`**

Dans `emitParagraph`, remplacer le cas :

```swift
        case .codeBlock:
            let lang = (source.attribute(.mdCodeLanguage, at: range.location, effectiveRange: nil) as? String) ?? ""
            let body = (source.string as NSString).substring(with: range)
            return "```\(lang)\n\(body)\n```"
```

par :

```swift
        case .codeBlock:
            // Traité en amont par `fencedCodeBlock`, qui émet le bloc entier.
            // Ce cas n'est atteignable que si un run `.codeBlock` se retrouve
            // isolé au milieu d'un paragraphe : on émet alors le texte brut.
            return inline
```

- [ ] **Step 3 : relancer les tests d'aller-retour**

```bash
swift test --filter MarkdownRoundTripTests
```

Attendu : SUCCÈS, toutes fixtures comprises.

- [ ] **Step 4 : lancer la suite markdown complète pour vérifier l'absence de régression**

```bash
swift test --filter Markdown
```

Attendu : SUCCÈS pour `MarkdownParserTests`, `MarkdownSerializerTests`, `MarkdownRoundTripTests`, `MarkdownEditingCommandsTests`, `MarkdownToHTMLRendererTests`.

- [ ] **Step 5 : committer**

```bash
git add OneToOne/Markdown/Markdown/MarkdownSerializer.swift
git commit -m "fix(markdown): émettre les blocs fencés d'un seul tenant

Le sérialiseur découpait sur les \\n et réémettait une paire de fences par
ligne, cassant l'aller-retour de tout bloc de code multi-ligne. Les blocs
sont maintenant émis par run d'attributs."
```

---

### Task 3 : prouver la perte d'URL des images

**Files:**
- Test: `Tests/MarkdownRoundTripTests.swift`

- [ ] **Step 1 : ajouter les fixtures d'images**

Ajouter à la fin du tableau `fixtures` :

```swift
        // Images — l'URL était perdue faute de cas `Image` dans le parser.
        // Les textes alternatifs évitent les caractères de
        // `MarkdownEscaping.inlineSpecials` (`+`, `-`, `_`, `#`, `!`…) : ils
        // ressortiraient échappés (`R+2` → `R\+2`) et feraient échouer le test
        // sur l'échappement plutôt que sur le bug visé.
        "![Plan du R2](file:///Users/x/img_ab12.png)",
        "Avant ![schéma](file:///Users/x/s.png) après",
        "![](file:///Users/x/sansalt.png)"
```

- [ ] **Step 2 : lancer les tests et constater l'échec**

```bash
swift test --filter MarkdownRoundTripTests
```

Attendu : ÉCHEC. `![Plan du R2](file:///Users/x/img_ab12.png)` produit `Plan du R2` — l'URL a disparu.

- [ ] **Step 3 : committer le test rouge**

```bash
git add Tests/MarkdownRoundTripTests.swift
git commit -m "test(markdown): fixtures d'aller-retour pour les images (rouge)"
```

---

### Task 4 : conserver les images dans le modèle

**Files:**
- Modify: `OneToOne/Markdown/Model/MarkdownAttributeKeys.swift:20`
- Modify: `OneToOne/Markdown/Markdown/MarkdownParser.swift:158`
- Modify: `OneToOne/Markdown/Markdown/MarkdownSerializer.swift:100`

- [ ] **Step 1 : déclarer les deux clés d'attributs**

Dans `MarkdownAttributeKeys.swift`, après la déclaration de `mdCodeLanguage` (ligne 20) et avant l'accolade fermante de l'extension :

```swift
    /// Value: `URL` — destination d'une image inline. Portée par l'unique
    /// caractère `U+FFFC` qui représente l'image dans le texte.
    static let mdImageURL      = NSAttributedString.Key("mdImageURL")
    /// Value: `String` — texte alternatif de l'image, réémis entre crochets.
    static let mdImageAlt      = NSAttributedString.Key("mdImageAlt")
```

- [ ] **Step 2 : parser le nœud `Image`**

Dans `MarkdownParser.emitInlineNode`, insérer ce cas **avant** `case let link as Markdown.Link:` :

```swift
            case let image as Markdown.Image:
                // Une image devient un unique caractère « object replacement »
                // porteur de sa destination : le texte reste sérialisable même
                // si le fichier est absent ou illisible.
                guard let destination = image.source,
                      let url = URL(string: destination) else {
                    out.append(NSAttributedString(string: image.plainText))
                    return
                }
                out.append(NSAttributedString(
                    string: "\u{FFFC}",
                    attributes: [.mdImageURL: url, .mdImageAlt: image.plainText]
                ))
```

- [ ] **Step 3 : réémettre l'image**

Dans `MarkdownSerializer.emitInline`, insérer au tout début de la closure passée à `enumerateAttributes`, **avant** le test `if (attrs[.mdInlineCode] as? Bool) == true` :

```swift
            if let url = attrs[.mdImageURL] as? URL {
                let alt = (attrs[.mdImageAlt] as? String) ?? ""
                out.append("![")
                out.append(MarkdownEscaping.escapeInline(alt))
                out.append("](")
                out.append(MarkdownEscaping.escapeURL(url.absoluteString))
                out.append(")")
                return
            }
```

- [ ] **Step 4 : lancer les tests d'aller-retour**

```bash
swift test --filter MarkdownRoundTripTests
```

Attendu : SUCCÈS sur toutes les fixtures, images comprises.

- [ ] **Step 5 : committer**

```bash
git add OneToOne/Markdown/Model/MarkdownAttributeKeys.swift \
        OneToOne/Markdown/Markdown/MarkdownParser.swift \
        OneToOne/Markdown/Markdown/MarkdownSerializer.swift
git commit -m "fix(markdown): conserver la destination des images

Le visiteur inline n'avait pas de cas Image : le nœud tombait dans le
default qui descend dans ses enfants, ne gardant que le texte alternatif.
L'URL était perdue au premier aller-retour."
```

---

### Task 5 : fabrique d'attachments image

**Files:**
- Create: `OneToOne/Markdown/Blocks/ImageAttachmentFactory.swift`
- Test: `Tests/ImageAttachmentFactoryTests.swift`

- [ ] **Step 1 : écrire le test de mise à l'échelle**

Créer `Tests/ImageAttachmentFactoryTests.swift` :

```swift
import XCTest
import AppKit
@testable import OneToOne

final class ImageAttachmentFactoryTests: XCTestCase {

    func test_imageNarrowerThanMaxWidth_isNotScaled() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 200, height: 100))
        XCTAssertEqual(bounds.width, 200)
        XCTAssertEqual(bounds.height, 100)
    }

    func test_imageWiderThanMaxWidth_isScaledKeepingAspectRatio() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 960, height: 480))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertEqual(bounds.height, ImageAttachmentFactory.maxWidth / 2)
    }

    func test_degenerateSize_fallsBackToPlaceholderBounds() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 0, height: 0))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertGreaterThan(bounds.height, 0)
    }

    func test_missingFile_returnsNil() {
        let url = URL(fileURLWithPath: "/tmp/onetoone-inexistant-\(UUID().uuidString).png")
        XCTAssertNil(ImageAttachmentFactory.attachment(for: url))
    }
}
```

- [ ] **Step 2 : lancer le test et constater l'échec**

```bash
swift test --filter ImageAttachmentFactoryTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'ImageAttachmentFactory' in scope`.

- [ ] **Step 3 : écrire la fabrique**

Créer `OneToOne/Markdown/Blocks/ImageAttachmentFactory.swift` :

```swift
import AppKit

/// Construit — et met en cache — le `NSTextAttachment` affiché à la place d'une
/// image markdown inline. Le cache est indexé par URL pour que le restylage du
/// texte, déclenché à chaque frappe, ne relise pas le fichier sur disque.
enum ImageAttachmentFactory {

    /// Largeur maximale d'affichage. Les images plus larges sont réduites en
    /// conservant leur rapport d'aspect.
    static let maxWidth: CGFloat = 480

    /// Hauteur du cadre affiché quand la taille de l'image est inexploitable.
    private static let placeholderHeight: CGFloat = 120

    private static let cache = NSCache<NSURL, NSTextAttachment>()

    /// Renvoie l'attachment correspondant à `url`, ou `nil` si le fichier est
    /// absent ou illisible — auquel cas le caractère `U+FFFC` reste affiché tel
    /// quel et le markdown source demeure intact.
    static func attachment(for url: URL) -> NSTextAttachment? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = displayBounds(for: image.size)
        cache.setObject(attachment, forKey: url as NSURL)
        return attachment
    }

    /// Réduit `size` pour tenir dans `maxWidth` sans déformation. Une taille
    /// dégénérée (largeur ou hauteur nulle) donne un cadre de remplacement.
    static func displayBounds(for size: NSSize) -> NSRect {
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: 0, width: maxWidth, height: placeholderHeight)
        }
        guard size.width > maxWidth else {
            return NSRect(origin: .zero, size: size)
        }
        let scale = maxWidth / size.width
        return NSRect(x: 0, y: 0, width: maxWidth, height: (size.height * scale).rounded())
    }

    /// Vide le cache — à appeler quand une image est remplacée sur disque.
    static func invalidate() {
        cache.removeAllObjects()
    }
}
```

- [ ] **Step 4 : relancer le test**

```bash
swift test --filter ImageAttachmentFactoryTests
```

Attendu : SUCCÈS, 4 tests.

- [ ] **Step 5 : committer**

```bash
git add OneToOne/Markdown/Blocks/ImageAttachmentFactory.swift Tests/ImageAttachmentFactoryTests.swift
git commit -m "feat(markdown): fabrique d'attachments image avec cache"
```

---

### Task 6 : afficher les images dans l'éditeur

**Files:**
- Modify: `OneToOne/Markdown/Core/StyleRenderer.swift:26-45`

- [ ] **Step 1 : poser l'attachment pendant le stylage**

Dans `StyleRenderer.applyVisualStyle`, à l'intérieur de la closure `storage.enumerateAttributes`, insérer juste après la ligne `let link = attrs[.mdLink] as? URL` :

```swift
            // Une image occupe un unique caractère U+FFFC : on lui accroche
            // l'attachment et on n'applique aucun style textuel dessus.
            if let imageURL = attrs[.mdImageURL] as? URL {
                if let attachment = ImageAttachmentFactory.attachment(for: imageURL) {
                    storage.addAttribute(.attachment, value: attachment, range: range)
                } else {
                    storage.removeAttribute(.attachment, range: range)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
                }
                return
            }
```

- [ ] **Step 2 : nettoyer l'attribut `.attachment` en début de restylage**

Toujours dans `applyVisualStyle`, ajouter après `storage.removeAttribute(.obliqueness, range: renderRange)` (ligne 24) :

```swift
        storage.removeAttribute(.attachment, range: renderRange)
```

- [ ] **Step 3 : compiler**

```bash
swift build
```

Attendu : compilation sans erreur.

- [ ] **Step 4 : vérifier dans l'app**

```bash
Scripts/bump-and-build.sh dev
```

Ouvrir une réunion, coller une image dans les notes (⌘V avec une image dans le presse-papiers), vérifier qu'elle s'affiche dans l'éditeur au lieu du texte `![image](…)`. Fermer puis rouvrir la note : l'image doit toujours être là.

- [ ] **Step 5 : committer**

```bash
git add OneToOne/Markdown/Core/StyleRenderer.swift
git commit -m "feat(markdown): afficher les images inline dans l'éditeur"
```

---

### Task 7 : déplacer `ImagePasteService` dans le module

**Files:**
- Create: `OneToOne/Markdown/Media/MediaStore.swift`
- Modify: `OneToOne/Views/EditableTextField.swift:1-59`

- [ ] **Step 1 : créer `MediaStore` avec le contenu déplacé**

Créer `OneToOne/Markdown/Media/MediaStore.swift` avec le corps exact d'`ImagePasteService` (`EditableTextField.swift:6-59`), renommé :

```swift
import AppKit

/// Stockage disque des images collées ou importées dans un éditeur markdown.
/// Les fichiers vivent dans `Application Support/OneToOne/images/`, à côté des
/// enregistrements audio et des sauvegardes.
enum MediaStore {

    static var imagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OneToOne/images", isDirectory: true)
    }

    static var clipboardHasImage: Bool {
        let pb = NSPasteboard.general
        return pb.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue,
                                                          NSPasteboard.PasteboardType.tiff.rawValue])
    }

    /// Enregistre l'image du presse-papiers et renvoie son URL sur disque.
    /// Au-delà de 2 Mo l'image est réencodée en JPEG qualité 0,8.
    static func saveClipboardImage() -> URL? {
        let pb = NSPasteboard.general

        var imageData: Data?
        if let png = pb.data(forType: .png) {
            imageData = png
        } else if let tiff = pb.data(forType: .tiff),
                  let bitmapRep = NSBitmapImageRep(data: tiff),
                  let png = bitmapRep.representation(using: .png, properties: [:]) {
            imageData = png
        }
        guard let data = imageData else { return nil }

        var finalData = data
        if finalData.count > 2_000_000 {
            if let bitmapRep = NSBitmapImageRep(data: data),
               let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                finalData = jpeg
            }
        }

        let isJpeg = finalData.count != data.count
        let ext = isJpeg ? "jpg" : "png"
        let fileName = "img_\(UUID().uuidString).\(ext)"
        let dir = imagesDirectory

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(fileName)
            try finalData.write(to: fileURL)
            return fileURL
        } catch {
            print("[MediaStore] Échec d'enregistrement de l'image : \(error)")
            return nil
        }
    }

    /// Référence markdown standard pointant vers le fichier enregistré.
    static func markdownReference(for imageURL: URL, alt: String = "image") -> String {
        "![\(alt)](\(imageURL.absoluteString))"
    }
}
```

- [ ] **Step 2 : supprimer l'ancien et rediriger les appelants**

Dans `OneToOne/Views/EditableTextField.swift`, supprimer le bloc `// MARK: - Image Paste Service` et l'`enum ImagePasteService` en entier (lignes 4 à 59). Remplacer les trois références restantes dans le fichier :

- ligne ~70 : `if ImagePasteService.clipboardHasImage {` → `if MediaStore.clipboardHasImage {`
- ligne ~71 : `if let imageURL = ImagePasteService.saveClipboardImage() {` → `if let imageURL = MediaStore.saveClipboardImage() {`
- ligne ~72 : `let ref = ImagePasteService.markdownReference(for: imageURL)` → `let ref = MediaStore.markdownReference(for: imageURL)`
- ligne ~372 : `guard let imageURL = ImagePasteService.saveClipboardImage() else { return }` → `guard let imageURL = MediaStore.saveClipboardImage() else { return }`
- ligne ~373 : `let ref = ImagePasteService.markdownReference(for: imageURL)` → `let ref = MediaStore.markdownReference(for: imageURL)`

- [ ] **Step 3 : vérifier qu'aucune référence ne subsiste**

```bash
grep -rn "ImagePasteService" OneToOne --include="*.swift"
```

Attendu : aucune sortie.

- [ ] **Step 4 : compiler et lancer la suite**

```bash
swift build && swift test
```

Attendu : compilation sans erreur, tous les tests au vert.

- [ ] **Step 5 : committer**

```bash
git add OneToOne/Markdown/Media/MediaStore.swift OneToOne/Views/EditableTextField.swift
git commit -m "refactor(markdown): déplacer ImagePasteService dans le module sous le nom MediaStore"
```

---

### Task 8 : coller une image depuis l'éditeur du module

**Files:**
- Modify: `OneToOne/Markdown/Core/EditorTextView.swift`

- [ ] **Step 1 : intercepter le collage**

Dans `EditorTextView`, ajouter cette méthode après `commonInit()` :

```swift
    // MARK: - Collage

    /// Si le presse-papiers contient une image, l'enregistre sur disque et
    /// insère sa référence markdown ; sinon délègue au collage standard.
    override func paste(_ sender: Any?) {
        guard MediaStore.clipboardHasImage,
              let imageURL = MediaStore.saveClipboardImage() else {
            super.paste(sender)
            return
        }
        let reference = MediaStore.markdownReference(for: imageURL)
        insertText("\n\(reference)\n", replacementRange: selectedRange())
    }
```

- [ ] **Step 2 : compiler**

```bash
swift build
```

Attendu : compilation sans erreur.

- [ ] **Step 3 : vérifier dans l'app**

```bash
Scripts/bump-and-build.sh dev
```

Copier une capture d'écran (⌃⇧⌘4), la coller dans les notes de préparation d'une réunion : l'image doit apparaître directement dans l'éditeur. Fermer et rouvrir : elle est conservée.

- [ ] **Step 4 : committer**

```bash
git add OneToOne/Markdown/Core/EditorTextView.swift
git commit -m "feat(markdown): coller une image directement dans l'éditeur du module"
```

---

### Task 9 : vérification finale

**Files:** aucun

- [ ] **Step 1 : suite complète**

```bash
swift test
```

Attendu : SUCCÈS, aucun échec.

- [ ] **Step 2 : build de l'app**

```bash
Scripts/bump-and-build.sh dev
```

Attendu : l'app se lance. Vérifier dans une réunion :
- une note contenant un bloc de code sur plusieurs lignes est rechargée à l'identique après fermeture/réouverture ;
- une image collée s'affiche et survit à un aller-retour ;
- les cases à cocher restent cliquables ;
- l'auto-format à la frappe (`**gras**`, `# titre`) fonctionne toujours.

- [ ] **Step 3 : committer si des ajustements ont été nécessaires**

```bash
git status
```

Si des fichiers ont été modifiés pendant la vérification, les committer avec un message décrivant le correctif.

---

## Ce que ce plan ne couvre pas

- **Menu `/`** — plan séparé, s'appuie sur `MarkdownEditingCommands` déjà en place.
- **Mermaid, cache de rendu, import draw.io** — plan séparé, s'appuie sur `ImageAttachmentFactory` introduite ici, généralisée en `BlockRenderer`.
- **Unification de `MarkdownText.swift`** — son analyseur ligne-à-ligne maison ne diverge de façon gênante qu'à l'arrivée de mermaid ; le remplacer par un modèle de blocs issu de `swift-markdown` est traité dans le plan mermaid, là où le besoin devient réel.
- **`MarkdownToHTMLRenderer` et mermaid** — même raison, plan mermaid.
