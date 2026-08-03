import Foundation

/// Point de construction unique de la représentation interne d'une image
/// inline dans le texte attribué de l'éditeur : un caractère « object
/// replacement » `U+FFFC` porteur de `.mdImageURL` (destination) et
/// `.mdImageAlt` (texte alternatif).
///
/// Trois endroits créent ce caractère : `MarkdownParser` (en parsant une
/// image markdown), `EditorTextView.paste(_:)` (collage depuis le
/// presse-papiers) et `MarkdownToolbar` (bouton coller-image). Avant cette
/// extraction, la représentation était écrite à la main aux deux premiers
/// endroits séparément — un attribut porté par un caractère marqueur, sans
/// constructeur partagé, a déjà causé plusieurs bugs de désynchronisation
/// sur ce module. Centraliser sa construction ici garantit qu'une évolution
/// future (ex. attribut supplémentaire) reste synchronisée aux trois.
enum ImagePlaceholder {
    static func attributedString(for url: URL, alt: String) -> NSAttributedString {
        NSAttributedString(string: "\u{FFFC}", attributes: [
            .mdImageURL: url,
            .mdImageAlt: alt
        ])
    }
}
