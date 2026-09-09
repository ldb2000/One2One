import SwiftUI

/// Le menu de vues enregistrées de la barre de filtres — « Vue enregistrée :
/// Mes projets ASP ⌄ » de la capture `1a-portfolio.png`.
///
/// Une **vue enregistrée** est un jeu de facettes et un tri, nommés
/// (`PortfolioSavedView`), persistés dans `AppSettings.portfolioSavedViews`
/// (décision **D4** : aucun nouveau `@Model`). Le handoff en fait la
/// contrepartie des chips : « la combinaison peut être enregistrée comme
/// "vue" ».
struct SavedViewMenu: View {

    /// Le préfixe, tel que la capture l'écrit.
    static let prefixe = "Vue enregistrée :"
    /// Ce qu'affiche le menu quand aucune vue n'est active.
    static let aucune = "Aucune"
    /// L'entrée qui crée une vue depuis les filtres en place.
    static let enregistrerLibelle = "Enregistrer la vue actuelle…"
    /// L'entrée qui retire la vue active.
    static let supprimerLibelle = "Supprimer cette vue"

    /// Corps du menu : la mesure « méta » du handoff.
    static let taille: CGFloat = 12

    let vues: [PortfolioSavedView]
    let active: UUID?
    let choisir: (PortfolioSavedView) -> Void
    let enregistrer: () -> Void
    let supprimer: (PortfolioSavedView) -> Void

    private var vueActive: PortfolioSavedView? {
        vues.first { $0.id == active }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(Self.prefixe)
                .font(.plexSans(Self.taille))
                .foregroundStyle(One2OneToken.ink4)

            Menu {
                ForEach(vues) { vue in
                    Button {
                        choisir(vue)
                    } label: {
                        Text(vue.id == active ? "✓ \(vue.name)" : vue.name)
                    }
                }
                if !vues.isEmpty { Divider() }
                Button(Self.enregistrerLibelle, action: enregistrer)
                if let vueActive {
                    Button(Self.supprimerLibelle) { supprimer(vueActive) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(vueActive?.name ?? Self.aucune)
                        .font(.plexSans(Self.taille, .medium))
                        .foregroundStyle(One2OneToken.action)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(One2OneToken.action)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// La feuille qui demande le nom d'une vue à enregistrer.
///
/// Une feuille et non une saisie en place : le nom est une donnée nouvelle, pas
/// la correction d'une valeur affichée, et la barre de filtres n'a pas la place
/// d'un champ de plus.
struct SavedViewNameSheet: View {

    static let titre = "Enregistrer la vue actuelle"
    static let invite = "Nom de la vue"
    static let valider = "Enregistrer"
    static let annuler = "Annuler"

    @Binding var nom: String
    let valider: () -> Void
    let annuler: () -> Void

    private var nomValide: Bool {
        !nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.titre)
                .font(.plexSans(13, .semibold))
                .foregroundStyle(One2OneToken.ink1)

            TextField(Self.invite, text: $nom)
                .textFieldStyle(.roundedBorder)
                .font(.plexSans(13))
                .frame(width: 260)
                .onSubmit { if nomValide { valider() } }

            HStack(spacing: 8) {
                Spacer()
                Button(Self.annuler, action: annuler)
                    .keyboardShortcut(.cancelAction)
                Button(Self.valider, action: valider)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nomValide)
            }
        }
        .padding(20)
        .background(One2OneToken.surface)
    }
}
