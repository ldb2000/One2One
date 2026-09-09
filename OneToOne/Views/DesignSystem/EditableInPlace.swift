import AppKit
import SwiftUI

/// L'édition **in-place** de la refonte des projets : on lit d'abord, on
/// édite au clic sur la valeur (décision **D9**, ADR
/// `docs/adr/2026-09-09-edition-in-place-fiche-projet.md`).
///
/// **Pourquoi ce composant existe.** `ProjectDetailView` lie ses champs
/// directement à `@Bindable project` : chaque frappe écrit dans le store, et
/// « annuler » n'a plus rien à restaurer. `ProjectCardPanel`, lui, a le bon
/// mécanisme — un `ProjectCardDraft` détaché, un enregistrement optimiste et
/// une bannière d'annulation — mais derrière une **bascule globale**
/// `Édition` : tout le panneau bascule, ou rien. L'écran projet veut le
/// brouillon **sans** la bascule : un champ à la fois, et l'écran reste en
/// lecture.
///
/// **Le contrat, et il tient en trois lignes.**
/// - clic sur la valeur → champ actif, présélectionné sur la valeur courante ;
/// - `⏎` (une ligne) ou `⌘⏎` (un paragraphe) → `onValider(saisie)` ;
/// - `esc` → le champ se referme et **rien** n'est écrit ; l'écran, lui, ne
///   bouge pas — c'est `EditableTextField.onCancel` qui consomme la touche.
///
/// **La fonte est imposée en `NSFont`**, jamais par un `.font()` SwiftUI :
/// `EditableTextField` et `EditableTextEditor` sont des `NSViewRepresentable`,
/// qui ignorent l'environnement de fonte (constat §2.14 — c'est ce qui a fait
/// sortir le titre de réunion en fonte système pendant quatre lots).
struct EditableInPlace<Lecture: View>: View {

    /// Une valeur d'une ligne, ou un paragraphe.
    enum Mode: Sendable {
        case ligne
        case paragraphe
    }

    /// L'infobulle de la zone cliquable, et le début du pied de la carte
    /// « PÉRIMÈTRE & CONTEXTE ».
    static var aide: String { "Cliquer pour éditer" }
    /// L'indication affichée sous le champ actif, par mode.
    static var indiceLigne: String { "⏎ pour valider · esc pour annuler" }
    static var indiceParagraphe: String { "⌘⏎ pour valider · esc pour annuler" }
    /// Taille de l'indication — au-dessus du plancher de 11,5 pt d'`inkMuted`.
    static var tailleIndice: CGFloat { 11.5 }
    /// Hauteur du champ d'une ligne, et hauteur minimale d'un paragraphe.
    static var hauteurLigne: CGFloat { 22 }
    static var hauteurParagraphe: CGFloat { 96 }

    // MARK: - Règles

    /// La saisie retenue : les espaces de bord sont retirés, comme partout
    /// ailleurs dans le dépôt.
    static func normalise(_ saisie: String) -> String {
        saisie.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Faut-il écrire ? Non si la saisie normalisée est celle qu'on lisait
    /// déjà : un `⏎` sur un champ qu'on n'a pas touché ne doit ni sauver, ni
    /// faire apparaître une bannière d'annulation qui n'annulerait rien.
    static func doitValider(saisie: String, valeur: String) -> Bool {
        normalise(saisie) != normalise(valeur)
    }

    /// Faut-il ouvrir le champ sur une **demande extérieure** ?
    ///
    /// Non s'il est déjà ouvert : « Compléter » de la vue « À risque » peut
    /// arriver sur un champ que l'utilisateur venait de cliquer, et rouvrir
    /// perdrait sa saisie en cours.
    static func doitOuvrir(demande: Bool, enEdition: Bool) -> Bool {
        demande && !enEdition
    }

    // MARK: - Entrées

    /// La valeur brute éditée. C'est elle que le champ reçoit à l'ouverture,
    /// et elle qui sert de témoin à `doitValider`.
    let valeur: String
    let placeholder: String
    let mode: Mode
    /// Fonte du **champ** — celle de la lecture est portée par `lecture`.
    let fonte: NSFont
    /// Appelé avec la saisie normalisée, seulement si elle change.
    let onValider: (String) -> Void
    /// Le rendu en lecture, tel que la carte le dessine.
    let lecture: Lecture
    /// Ouverture **externe** : quand ce drapeau passe à `true`, le champ
    /// s'ouvre comme si on avait cliqué la valeur, puis le remet à `false`.
    ///
    /// C'est le chemin de « Compléter » de la vue « À risque » (lot 5) : le
    /// clic reste le geste ordinaire, celui-ci est la consigne venue d'un
    /// autre écran, consommée une fois.
    @Binding var ouvrir: Bool

    init(valeur: String,
         placeholder: String = "",
         mode: Mode = .ligne,
         fonte: NSFont = .plexSans(13),
         ouvrir: Binding<Bool> = .constant(false),
         onValider: @escaping (String) -> Void,
         @ViewBuilder lecture: () -> Lecture) {
        self.valeur = valeur
        self.placeholder = placeholder
        self.mode = mode
        self.fonte = fonte
        self._ouvrir = ouvrir
        self.onValider = onValider
        self.lecture = lecture()
    }

    @State private var enEdition = false
    @State private var saisie = ""

    var body: some View {
        Group {
            if enEdition {
                champ
            } else {
                lecture
                    .contentShape(Rectangle())
                    .onTapGesture { commencer() }
                    .help(Self.aide)
            }
        }
        .onAppear { ouvrirSiDemande() }
        .onChange(of: ouvrir) { _, _ in ouvrirSiDemande() }
    }

    /// Honore la demande extérieure et la consomme — sinon le champ se
    /// rouvrirait à chaque reconstruction de la carte.
    private func ouvrirSiDemande() {
        guard Self.doitOuvrir(demande: ouvrir, enEdition: enEdition) else { return }
        ouvrir = false
        commencer()
    }

    // MARK: - Le champ actif

    @ViewBuilder
    private var champ: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch mode {
            case .ligne:
                EditableTextField(placeholder: placeholder,
                                  text: $saisie,
                                  style: .plain,
                                  font: fonte,
                                  onSubmit: valider,
                                  onCancel: annuler)
                    .frame(height: Self.hauteurLigne)
            case .paragraphe:
                EditableTextEditor(text: $saisie,
                                   font: fonte,
                                   transparent: true,
                                   onSubmit: valider,
                                   onCancel: annuler)
                    .frame(minHeight: Self.hauteurParagraphe)
            }
            Text(mode == .ligne ? Self.indiceLigne : Self.indiceParagraphe)
                .font(.plexSans(Self.tailleIndice))
                .foregroundStyle(One2OneToken.inkMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .fill(One2OneToken.surfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .strokeBorder(One2OneToken.action, lineWidth: 1)
        )
    }

    // MARK: - Gestes

    private func commencer() {
        saisie = valeur
        enEdition = true
    }

    private func valider() {
        if Self.doitValider(saisie: saisie, valeur: valeur) {
            onValider(Self.normalise(saisie))
        }
        enEdition = false
    }

    /// `esc` : le champ se referme, **rien** n'est écrit — et surtout pas
    /// l'écran, qui n'a pas à se fermer parce qu'on a renoncé à une saisie.
    private func annuler() {
        saisie = valeur
        enEdition = false
    }
}

#Preview("EditableInPlace") {
    VStack(alignment: .leading, spacing: 16) {
        EditableInPlace(valeur: "AE – Gestion des services IO",
                        placeholder: "Nom du projet",
                        fonte: .plexSans(13),
                        onValider: { _ in }) {
            Text("AE – Gestion des services IO")
                .font(.plexSans(13))
                .foregroundStyle(One2OneToken.ink1)
        }
        EditableInPlace(valeur: "Reprise des services IO…",
                        placeholder: "Périmètre et contexte",
                        mode: .paragraphe,
                        onValider: { _ in }) {
            Text("Reprise des services IO…")
                .font(.plexSans(13))
                .foregroundStyle(One2OneToken.ink2)
        }
    }
    .frame(width: 420)
    .padding(20)
    .background(One2OneToken.surface)
}
