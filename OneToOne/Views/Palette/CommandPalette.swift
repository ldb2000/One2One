import SwiftUI
import SwiftData

/// La palette `⌘K` (capture `1c-palette-cmdk.png`) : trouver un projet en
/// trois lettres, depuis n'importe quel écran.
///
/// **Un assembleur, pas un calculateur.** Tout ce qu'elle montre vient de
/// `PaletteModel` (`@Observable`, décision **D11**) et de `ProjectSearch`
/// (**D7**) : `body` ne filtre, ne trie et ne compte rien. Les deux formes de
/// ligne sont dans `PaletteRow.swift`, le surlignage dans
/// `HighlightedText.swift`.
///
/// **Une couche par-dessus la fenêtre, ni feuille ni panneau.** Une `.sheet`
/// macOS descend du haut de la fenêtre avec son propre fond et ses propres
/// marges — elle ne sait pas dessiner la carte de 560 pt bordée et ombrée que
/// la capture montre, et le tapis d'une feuille ne se peint pas. Un `NSPanel`
/// flottant le saurait, au prix d'une fenêtre à gérer (activation, ordre,
/// fermeture) pour un rendu identique. La couche pose la carte à
/// `margeHaute` du haut, sur un tapis transparent qui **avale les clics** :
/// c'est ce qui rend la palette modale sans assombrir l'écran, comme la
/// maquette la dessine.
///
/// **Le clavier.** `↑`/`↓` déplacent le curseur (`onKeyPress` sur la couche,
/// comme `OneToOneQuickPickerWindow`), `↩` active la ligne (`onSubmit` du
/// champ, le chemin qui marche quand un `TextField` a le focus), `⌘↩` bascule
/// l'épinglage **sans fermer**, `esc` referme.
struct CommandPalette: View {

    // MARK: - Mesures (handoff §1c)

    /// Largeur de la carte. Le handoff écrit « 560 px » ; la maquette rend
    /// 508, parce que ses 560 comptent les 26 px de marge du cadre de
    /// capture. Le texte du handoff gagne — c'est la mesure nommée.
    static let largeur: CGFloat = 560
    /// Hauteur du champ de saisie.
    static let hauteurChamp: CGFloat = 44
    /// Taille du texte saisi.
    static let tailleChamp: CGFloat = 15
    /// Taille de la pastille `esc` et du pied.
    static let taillePastille: CGFloat = 10
    static let taillePied: CGFloat = 10.5
    /// Décalage vertical de l'ombre (`0 18px 40px` du handoff ; le rayon et la
    /// teinte sont les jetons **D12** `paletteShadowRadius` et
    /// `paletteShadow`).
    static let ombreY: CGFloat = 18
    /// Distance entre le haut de la fenêtre et la carte : « centrée haut ».
    static let margeHaute: CGFloat = 96
    /// Marges intérieures du champ et du pied (maquette : `13px 15px` et
    /// `9px 15px`).
    static let margeChamp: CGFloat = 15
    /// Marges du bloc de résultats (maquette : `8px 8px 6px`).
    static let margeResultats: CGFloat = 8
    /// Écart entre les trois segments du pied.
    static let gapPied: CGFloat = 14

    // MARK: - Dépendances

    /// Le routeur, passé et non lu dans l'environnement : la palette est une
    /// couche posée sur la fenêtre, et l'ordre des modificateurs déciderait
    /// sinon si elle voit l'environnement de la barre latérale ou non.
    let router: MainRouter

    @Environment(\.modelContext) private var context
    @Query(sort: \Project.name) private var projets: [Project]

    @State private var model = PaletteModel()
    @State private var terme: String = ""
    @FocusState private var champFocalise: Bool

    // MARK: - Corps

    var body: some View {
        ZStack(alignment: .top) {
            // Le tapis : transparent, mais il prend les clics — rien de la
            // fenêtre ne réagit tant que la palette est ouverte.
            //
            // **Il ne referme pas.** Il l'a fait, et c'était un piège : un
            // clic n'importe où dans la fenêtre suffisait alors à faire
            // disparaître la palette, y compris un clic destiné à autre chose
            // ou l'activation d'un élément par l'accessibilité. La recette
            // `p1c` du 2026-09-09 l'a photographiée absente sans qu'on puisse
            // dire si elle ne s'était pas ouverte ou si elle venait de se
            // refermer. `esc` referme, activer une ligne referme ; un clic à
            // côté ne fait rien. Une ligne à remettre si l'usage la réclame.
            Color.clear
                .contentShape(Rectangle())

            carte
                .padding(.top, Self.margeHaute)
        }
        .onAppear {
            terme = router.paletteTerme ?? ""
            model.recharger(projects: projets, terme: terme)
            champFocalise = true
        }
        .onChange(of: terme) { model.recharger(projects: projets, terme: terme) }
        // Le store peut arriver après la première image (les `@Query` se
        // remplissent hors de `body`) : sans cela, la palette ouverte au
        // lancement par la recette `p1c` resterait vide.
        .onChange(of: projets) { model.recharger(projects: projets, terme: terme) }
        .onKeyPress(.escape) { fermer(); return .handled }
        .onKeyPress(.downArrow) { model.suivant(); return .handled }
        .onKeyPress(.upArrow) { model.precedent(); return .handled }
        // `⌘↩` : vérifié à la main plutôt que par un `keyboardShortcut`, qui
        // resterait actif la palette fermée (même raison qu'`ActionComposer`).
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            epingler()
            return .handled
        }
    }

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            champ
            Divider().overlay(One2OneToken.hair)
            if !model.estVide {
                resultats
                Divider().overlay(One2OneToken.hair)
            }
            pied
        }
        .frame(width: Self.largeur)
        .background(One2OneToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPanel,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPanel, style: .continuous)
                .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
        )
        .shadow(color: One2OneToken.paletteShadow,
                radius: One2OneToken.paletteShadowRadius,
                x: 0,
                y: Self.ombreY)
    }

    // MARK: - Le champ

    private var champ: some View {
        HStack(spacing: PaletteRowMetrics.gap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(One2OneToken.inkMuted)

            TextField(PaletteModel.invite, text: $terme)
                .textFieldStyle(.plain)
                .font(.plexSans(Self.tailleChamp))
                .foregroundStyle(One2OneToken.ink1)
                .focused($champFocalise)
                .onSubmit { activer() }

            Text(PaletteModel.pastilleEsc)
                .font(.plexMono(Self.taillePastille))
                .foregroundStyle(One2OneToken.ink4)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                     style: .continuous)
                        .fill(One2OneToken.hair)
                )
        }
        .padding(.horizontal, Self.margeChamp)
        .frame(height: Self.hauteurChamp)
    }

    // MARK: - Les résultats

    private var resultats: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupe(PaletteModel.titreProjets, premier: true)

            if model.aucunProjet {
                Text(PaletteModel.libelleAucunProjet)
                    .font(.plexSans(PaletteRowMetrics.tailleLibelle))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .padding(.vertical, PaletteRowMetrics.paddingV)
                    .padding(.horizontal, PaletteRowMetrics.paddingH)
            }

            ForEach(Array(model.projets.enumerated()), id: \.element.persistentModelID) { rang, projet in
                PaletteProjectRow(projet: projet,
                                  terme: model.terme,
                                  selectionnee: model.estSelectionne(.projet(rang)))
                    .onTapGesture { ouvrir(projet) }
            }

            groupe(PaletteModel.titreActions, premier: false)

            ForEach(model.actions, id: \.self) { action in
                PaletteActionRow(action: action,
                                 terme: model.terme,
                                 selectionnee: model.estSelectionne(.action(action)))
                    .onTapGesture { lancer(action) }
            }
        }
        .padding(.horizontal, Self.margeResultats)
        .padding(.top, Self.margeResultats)
        .padding(.bottom, 6)
    }

    /// Un libellé de groupe. Le premier colle au champ (`4px` de haut), le
    /// second respire davantage (`10px`) — c'est la maquette.
    private func groupe(_ titre: String, premier: Bool) -> some View {
        Text(titre)
            .sectionLabel()
            .padding(.horizontal, Self.margeResultats)
            .padding(.top, premier ? 4 : 10)
            .padding(.bottom, 6)
    }

    // MARK: - Le pied

    private var pied: some View {
        HStack(spacing: Self.gapPied) {
            ForEach(PaletteModel.piedSegments, id: \.self) { segment in
                Text(segment)
                    .font(.plexMono(Self.taillePied))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.margeChamp)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(One2OneToken.bgCanvas)
    }

    // MARK: - Activation

    /// `↩` : ce que la ligne sélectionnée fait.
    private func activer() {
        switch model.selection {
        case .projet(let rang):
            ouvrir(model.projets[rang])
        case .action(let action):
            lancer(action)
        case nil:
            // Rien de sélectionné (terme vide) : `↩` ne referme pas. La
            // palette attend qu'on tape.
            break
        }
    }

    private func ouvrir(_ projet: Project) {
        router.openProject(projet)
        fermer()
    }

    private func lancer(_ action: PaletteModel.Action) {
        switch action {
        case .creer:
            // Le terme devient le nom du projet : c'est ce que le libellé
            // promet (« Créer un projet « ged » »).
            let cree = ProjectCreation.creer(among: projets,
                                             nom: model.terme,
                                             in: context)
            router.openProject(cree)
        case .chercher:
            router.open(.searchReports(model.terme))
        }
        fermer()
    }

    /// `⌘↩` : épingle ou désépingle, **sans fermer** — on en épingle souvent
    /// plusieurs d'affilée.
    private func epingler() {
        guard model.basculerEpinglage() != nil else { return }
        try? context.save()
    }

    private func fermer() {
        router.fermerPalette()
    }
}
