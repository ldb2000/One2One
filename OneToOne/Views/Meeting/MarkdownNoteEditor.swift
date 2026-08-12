import SwiftUI
import SwiftData

/// Éditeur de notes markdown basé sur le module natif `OneToOne/Markdown/`
/// (`MarkdownTextEditor` → `EditorRepresentable`, `NSTextView`/TextKit 1) :
/// stylage live en frappe (titres, gras, listes), marqueurs de liste dessinés,
/// cases à cocher cliquables, menu `/` pour les conversions de bloc, images
/// inline collées, mentions `@` de collaborateurs
/// (`CollaboratorMentionSource`, `docs/superpowers/specs/2026-08-05-mentions-collaborateurs.md`).
///
/// **Un seul mode.** L'ancien sélecteur Aperçu/Édition venait du moteur tiers,
/// qui séparait un rendu en lecture seule d'une saisie en texte source. Le
/// module stylise en frappe : le rendu *est* la saisie, les deux modes
/// affichaient donc la même chose et seule l'éditabilité changeait. Le
/// sélecteur a été retiré ; les cases à cocher redeviennent cliquables en
/// permanence, ce que le mode Aperçu empêchait.
///
/// Remplace l'éditeur tiers **MarkdownEngine** (nodes-app/swift-markdown-engine,
/// `NativeTextViewWrapper`) précédemment utilisé ici. Les deux moteurs lisent
/// et écrivent du markdown : les notes existantes s'ouvrent telles quelles et
/// se normalisent note par note à la première édition — aucune conversion en
/// masse n'a été faite.
///
/// Perdu dans la bascule, volontairement **non réimplémenté** :
/// - rendu des tableaux (le module les conserve tels quels, en texte brut monospace) ;
/// - LaTeX ;
/// - coloration syntaxique des blocs de code (le module les affiche en
///   monospace uni, sans coloration par langage) ;
/// - Writing Tools (macOS) ;
/// - recherche intégrée au document ;
/// - undo scoping par document ;
/// - mémorisation de la position de défilement ;
/// - `==surlignage==` ;
/// - conversion automatique d'une table HTML collée en tableau markdown.
struct MarkdownNoteEditor: View {
    @Binding var text: String
    /// Identifiant d'enregistrement dans `MarkdownEditorRegistry` (équivalent
    /// du `documentId` de l'ancien moteur).
    let editorID: String

    @Environment(\.modelContext) private var context
    /// Source des mentions `@` — voir `CollaboratorMentionSource`. Les
    /// archivés sont exclus par le prédicat de ce `@Query`, pas par
    /// `CollaboratorMentionSource.search` (qui les recevrait sinon).
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var mentionableCollaborators: [Collaborator]
    /// Collaborateur dont la fiche a été ouverte en cliquant une mention —
    /// voir `markdownLinks(handler:)` ci-dessous. `CollaboratorDetailView`
    /// n'a pas d'autre point d'entrée programmatique dans l'app (sa seule
    /// présentation existante est un `NavigationLink` de la barre latérale,
    /// non déclenchable depuis ici) : on réutilise la vue elle-même, présentée
    /// en feuille — même idiome que `NotesSection`/`Sidebar` pour ouvrir un
    /// contenu détaillé sans quitter le contexte courant.
    @State private var openedCollaborator: Collaborator?

    var body: some View {
        MarkdownTextEditor(text: $text)
            .markdownFeatures(.full)
            .markdownEditorID(editorID)
            .markdownMentions(
                search: { CollaboratorMentionSource.search($0, in: mentionableCollaborators) },
                create: { CollaboratorMentionSource.create($0, in: context) }
            )
            .markdownLinks { url in
                guard let collaborator = CollaboratorMentionSource.resolve(url, in: mentionableCollaborators) else {
                    return false
                }
                openedCollaborator = collaborator
                return true
            }
            .sheet(item: $openedCollaborator) { collaborator in
                NavigationStack {
                    CollaboratorFicheView(collaborator: collaborator)
                }
            }
    }
}
