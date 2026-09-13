import Testing
import Foundation
import CoreGraphics
@testable import OneToOne

/// La typographie de l'écran de réunion, spec §1.2 — et le garde-fou qui
/// empêche la fonte système d'y revenir (retour d'usage du 2026-09-08,
/// défaut n° 2b).
///
/// Deux natures de tests, et c'est voulu :
///
/// 1. **Les tailles**, exposées en constantes par les vues qui les portent.
///    Une taille écrite en dur dans un `.font()` ne se vérifie pas ; sortie en
///    `static let`, elle tient dans un `#expect` et se compare à l'intervalle
///    de la spec.
/// 2. **L'interdit**, par lecture des sources. Le programme §7 dit « aucune
///    fonte hors `Font.plexSans` / `.plexMono` » ; c'est déjà tenu, et c'est
///    précisément le moment de l'écrire — quatre lots ont laissé le titre de
///    réunion sortir en fonte système sans qu'aucune suite ne bronche, parce
///    qu'un `.font(.body)` ajouté par distraction ne change l'état d'aucun
///    modèle. Même approche que `ActionsRailNoModalTests` et
///    `SessionNoChromeTests`.
///
/// `.font(.system(size:))` **n'est pas** dans l'interdit : c'est la seule façon
/// de dimensionner un `Image(systemName:)`, et un symbole SF n'a pas de fonte
/// Plex. Le test exige donc qu'il soit posé sur une image, jamais sur du texte.
@Suite("Typographie de l'écran de réunion")
struct RefonteTypographieTests {

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Les périmètres tenus par ce test : le rail, tous les espaces, la barre
    /// du haut et la barre d'espaces. Ce sont les surfaces que la recette
    /// photographie et que le retour d'usage a relevées.
    /// Étendu par la refonte de la gestion des projets (décision **D17**) :
    /// le routeur de navigation et l'écran projet entrent dans le périmètre.
    ///
    /// **Les autres dossiers de la refonte n'y sont pas encore**, parce qu'ils
    /// n'existent pas : `sourcesAreFound` ci-dessous vérifie que le périmètre
    /// est bien celui qu'on croit lire, et un dossier absent le rendrait faux
    /// à vide. À ajouter par le lot qui crée son premier fichier —
    /// `Views/Sidebar/` **au lot 1, fait**, `Views/Portfolio/` au lot 2,
    /// `Views/Palette/` au lot 3, `Views/AtRisk/` au lot 5.
    private static let perimetres = [
        "OneToOne/Views/Meeting/Spaces",
        "OneToOne/Views/Meeting/MeetingTopChromeBar.swift",
        "OneToOne/Views/Meeting/Chrome",
        "OneToOne/Views/Navigation",
        "OneToOne/Views/Project",
        "OneToOne/Views/Sidebar",
    ]

    private func sources() throws -> [(nom: String, texte: String)] {
        var resultat: [(nom: String, texte: String)] = []
        for perimetre in Self.perimetres {
            let url = racine.appendingPathComponent(perimetre)
            var estDossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &estDossier) else {
                continue
            }
            if estDossier.boolValue {
                let enumerateur = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                while let fichier = enumerateur?.nextObject() as? URL {
                    guard fichier.pathExtension == "swift" else { continue }
                    resultat.append((fichier.lastPathComponent,
                                     try String(contentsOf: fichier, encoding: .utf8)))
                }
            } else {
                resultat.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return resultat.sorted { $0.nom < $1.nom }
    }

    // MARK: - Le périmètre est bien celui qu'on croit lire

    @Test("Les six périmètres typographiques sont trouvés")
    func sourcesAreFound() throws {
        let noms = try sources().map(\.nom)
        // Le routeur de navigation (D0) et l'écran projet (D17).
        #expect(noms.contains("MainDetailView.swift"))
        #expect(noms.contains("ProjectCardPanel.swift"))
        // La section « Projets » de la barre latérale (lot 1, D17).
        #expect(noms.contains("ProjectsSidebarSection.swift"))
        #expect(noms.contains("PinnedProjectsList.swift"))
        #expect(noms.contains("RecentProjectsList.swift"))
        // Si ce test tombe, c'est qu'un dossier a bougé — et alors les deux
        // suivants ne prouveraient plus rien en passant.
        #expect(noms.contains("ActionsRail.swift"))
        #expect(noms.contains("MeetingSpacesBar.swift"))
        #expect(noms.contains("MeetingTopChromeBar.swift"))
        #expect(noms.contains("MeetingEmptyInvite.swift"))
        #expect(noms.contains("StyledMenuPopover.swift"))
        #expect(noms.count >= 30)
    }

    // MARK: - L'interdit

    @Test("Aucun style de fonte système dans le rail, les espaces et la barre du haut")
    func noSystemTextStyle() throws {
        // Les styles sémantiques d'Apple : ils suivent la taille de texte du
        // système, donc ne tiennent aucune des valeurs de §1.2.
        let interdits = [".font(.body", ".font(.largeTitle", ".font(.title",
                         ".font(.headline", ".font(.subheadline", ".font(.callout",
                         ".font(.footnote", ".font(.caption",
                         ".font(.system(.body", ".font(.system(.title",
                         ".fontWeight(", ".bold()", ".italic()"]
        for source in try sources() {
            for interdit in interdits {
                #expect(!source.texte.contains(interdit),
                        "\(source.nom) pose \(interdit) : toute fonte passe par Font.plexSans / .plexMono (§1.2)")
            }
        }
    }

    @Test("`.font(.system(size:))` ne sert qu'à dimensionner un symbole SF")
    func systemSizeOnlyForSymbols() throws {
        for source in try sources() {
            let lignes = source.texte.components(separatedBy: "\n")
            for (index, ligne) in lignes.enumerated() where ligne.contains(".font(.system(") {
                // Un symbole SF n'a pas de variante Plex ; c'est le seul usage
                // légitime, et il se reconnaît à l'`Image(` qui précède.
                let contexte = lignes[max(0, index - 3)...index].joined(separator: "\n")
                #expect(contexte.contains("Image("),
                        "\(source.nom):\(index + 1) applique une fonte système à du texte : \(ligne.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    // MARK: - Les tailles de §1.2

    @Test("La barre d'espaces tient les tailles de la spec")
    func spacesBarSizes() {
        // Titre de carte : 11,5 → 12.
        #expect(MeetingSpacesBar.spaceLabelSize >= 11.5)
        #expect(MeetingSpacesBar.spaceLabelSize <= 12)
        // `Préparer / En séance / Relire` est le mode de l'écran, pas le filtre
        // d'un panneau : même intervalle. Rendu à 10,5 px (la taille d'une
        // pilule) il se lisait comme un réglage secondaire.
        #expect(MeetingSpacesBar.modeLabelSize >= 11.5)
        #expect(MeetingSpacesBar.modeLabelSize <= 12)
        // Timecode de §1.2 : Plex Mono 10.
        #expect(MeetingSpacesBar.dateSize == 10)
    }

    @Test("La date de la barre d'espaces est en Plex Mono")
    func spacesBarDateIsMono() throws {
        let source = try #require(try sources().first { $0.nom == "MeetingSpacesBar.swift" })
        #expect(source.texte.contains(".plexMono(Self.dateSize)"))
    }

    @Test("L'invite d'état vide est au corps de la spec, pas une demi-taille en dessous")
    func emptyInviteSizes() {
        // §1.2 : corps 400 · 12 → 12,5 ; titre de carte 600 · 11,5 → 12.
        #expect(MeetingEmptyInvite.inviteSize == 12)
        #expect(MeetingEmptyInvite.titreSize == 12)
        // `ink/muted` reste permis : la spec le réserve aux textes de 11,5 px
        // et plus, ce que 12 respecte.
        #expect(MeetingEmptyInvite.inviteSize >= 11.5)
    }

    @Test("Les onglets du rail sont à la taille d'un titre de carte")
    func railTabSize() {
        #expect(ActionsRail.tabLabelSize >= 11.5)
        #expect(ActionsRail.tabLabelSize <= 12)
        // Le compteur qui suit est une pilule : 10 → 10,5.
        #expect(ActionsRail.tabCountSize >= 10)
        #expect(ActionsRail.tabCountSize <= 10.5)
    }

    @Test("Le bouton Rapport porte un libellé de corps, pas de pilule")
    func reportButtonLabelSize() {
        // Retour d'usage : `Transcrire + Rapport` et `Rapport ✓ (m:ss)` sont
        // l'action principale de la barre. À 10,5 px ils se lisaient comme une
        // pilule d'état ; la capture `1a-cockpit.png` les montre à 12 px.
        #expect(MeetingTopChromeBar.reportLabelSize == 12)
        // Les pilules-menus de la barre (`Architecture ⌄`, `Auto ⌄`) suivent la
        // même mesure : ce sont des commandes, pas des métadonnées.
        #expect(MeetingTopChromeBar.menuPillLabelSize == 12)
    }
}
