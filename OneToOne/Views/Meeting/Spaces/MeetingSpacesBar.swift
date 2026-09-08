import SwiftUI

/// La barre d'espaces de l'écran réunion (spec §2.2, capture `1a-cockpit.png`).
///
/// Hauteur 34 px. À gauche les espaces offerts par le type
/// (`MeetingSpaceRouting`), l'actif souligné 2 px `accent/report`. À droite le
/// sélecteur de mode (`Préparer` / `En séance` / `Relire`, actif en `ink/1`
/// plein) puis la date.
///
/// Remplace `MeetingTabsUnderline` et ses sept onglets. Le principe §1.1
/// « aucun onglet vide » vit dans `label(for:kind:hasReport:documentsCount:)` :
/// **toute** entrée porte un compteur ou un état, et c'est vérifié par un test
/// — pas laissé à la vigilance de la vue.
struct MeetingSpacesBar: View {

    /// Hauteur de la barre (spec §2.2).
    static let height: CGFloat = 34
    /// Épaisseur du soulignement de l'espace actif (spec §2.2).
    static let underlineHeight: CGFloat = 2
    /// Taille du libellé d'un espace (`Réunion`, `Rapport`, `Ressources`) et du
    /// sélecteur de mode : titre de carte de §1.2, 11,5 → 12 px.
    static let spaceLabelSize: CGFloat = 12
    static let modeLabelSize: CGFloat = 12
    /// La date, en Plex Mono 10 comme tout timecode de §1.2.
    static let dateSize: CGFloat = 10

    /// Titre et complément d'un espace dans la barre.
    ///
    /// Le complément n'est jamais vide **sauf** pour l'espace `Réunion`, dont
    /// le compteur n'aurait pas de sens (« 4 notes » changerait à chaque
    /// frappe) : c'est son mode qui dit où l'on en est. Les deux autres
    /// portent un état (`✓` / `à générer`) ou un compte (`n doc`).
    static func label(for space: MeetingScreenModel.Space,
                      kind: MeetingKind,
                      hasReport: Bool,
                      documentsCount: Int) -> (titre: String, complement: String) {
        switch space {
        case .meeting:
            return (MeetingSpaceRouting.meetingSpaceLabel(for: kind), "")
        case .report:
            return (space.label, hasReport ? "✓" : "à générer")
        case .resources:
            // « 0 doc », « 1 doc », « 2 docs » : en français, zéro reste au
            // singulier — et c'est ce que montre la capture (`Ressources 0 doc`).
            let unite = documentsCount > 1 ? "docs" : "doc"
            return (space.label, "\(documentsCount) \(unite)")
        }
    }

    /// La barre est-elle masquée pour ce couple espace/mode ?
    ///
    /// Le **poste de pilotage** (espace Réunion, mode Relire) remplace la barre
    /// d'espaces par sa nav latérale de 190 px : c'est la décision D0 du
    /// programme, et la capture `1c-poste-de-pilotage.png` ne montre aucune
    /// barre. Le sélecteur de mode déménage dans l'en-tête de sa colonne
    /// principale (`ReviewHeader`).
    ///
    /// Le masquage est **borné à l'espace Réunion**, et c'est le point qui
    /// compte : en mode Relire, l'espace Rapport et l'espace Ressources n'ont
    /// pas de nav latérale, et sans barre on s'y retrouverait sans rien pour en
    /// sortir.
    static func estMasquee(space: MeetingScreenModel.Space,
                           mode: MeetingScreenModel.Mode) -> Bool {
        space == .meeting && mode == .review
    }

    /// `4 sept. 2026 · 9:15` — la forme de la capture. Le point médian sépare
    /// la date de l'heure ; `locale` est un paramètre pour que le test ne
    /// dépende pas des réglages du poste.
    static func formatDate(_ date: Date, locale: Locale = .current) -> String {
        var jour = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        jour.locale = locale
        var heure = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        heure.locale = locale
        return "\(date.formatted(jour)) · \(date.formatted(heure))"
    }

    let screen: MeetingScreenModel
    let kind: MeetingKind
    let hasReport: Bool
    let documentsCount: Int
    let date: Date

    @Namespace private var underlineNS

    var body: some View {
        if Self.estMasquee(space: screen.space, mode: screen.mode) {
            EmptyView()
        } else {
            barre
        }
    }

    private var barre: some View {
        HStack(spacing: 22) {
            ForEach(MeetingSpaceRouting.spaces(for: kind), id: \.self) { space in
                spaceTab(space)
            }
            Spacer(minLength: 12)
            let modes = MeetingSpaceRouting.modes(for: kind)
            if !modes.isEmpty {
                SegmentedMode(
                    selection: Binding(get: { screen.mode }, set: { screen.mode = $0 }),
                    options: modes,
                    // §1.2 : 12 px / 500. Le mode de l'écran se lit comme un
                    // titre de carte, pas comme le filtre d'un panneau
                    // (retour d'usage du 2026-09-08).
                    taille: Self.modeLabelSize,
                    libelle: \.label
                )
            }
            // La date est une **métadonnée horaire** : Plex Mono 10, comme les
            // timecodes de §1.2. En sans 10,5 elle rivalisait avec le libellé
            // du mode juste à sa gauche.
            Text(Self.formatDate(date))
                .font(.plexMono(Self.dateSize))
                .foregroundStyle(One2OneToken.ink4)
        }
        .padding(.horizontal, MeetingTopChromeBar.paddingHorizontal)
        .frame(height: Self.height)
        .background(One2OneToken.bgApp)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.cardBorder).frame(height: 1)
        }
    }

    @ViewBuilder
    private func spaceTab(_ space: MeetingScreenModel.Space) -> some View {
        let actif = screen.space == space
        let libelle = Self.label(for: space, kind: kind,
                                 hasReport: hasReport, documentsCount: documentsCount)
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { screen.space = space }
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text(libelle.titre)
                        .font(.plexSans(Self.spaceLabelSize, actif ? .semibold : .regular))
                        .foregroundStyle(actif ? One2OneToken.ink1 : One2OneToken.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !libelle.complement.isEmpty {
                        Text(libelle.complement)
                            .font(.plexSans(10.5))
                            .foregroundStyle(complementColor(for: space, actif: actif))
                    }
                }
                Spacer(minLength: 0)
                // Le soulignement occupe la même place, actif ou non : sans
                // cela le libellé sauterait de 2 px au changement d'espace.
                if actif {
                    Rectangle()
                        .fill(One2OneToken.report)
                        .frame(height: Self.underlineHeight)
                        .matchedGeometryEffect(id: "soulignement", in: underlineNS)
                } else {
                    Color.clear.frame(height: Self.underlineHeight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }

    /// Le `✓` du rapport est en `accent/report` — c'est la teinte du rapport
    /// dans toute la refonte ; les compteurs restent en `ink/muted`.
    private func complementColor(for space: MeetingScreenModel.Space, actif: Bool) -> Color {
        if space == .report && hasReport { return One2OneToken.report }
        // Le complément (`0 doc`, `à générer`, `✓`) est en 10,5 px :
        // `ink/muted` n'y atteint pas 4,5:1 (spec §1.2). `ink/4` actif,
        // `ink/4` inactif — la distinction se fait par la graisse et le
        // soulignement de l'onglet, pas par un contraste hors barème.
        return One2OneToken.ink4
    }
}

#Preview("Barre d'espaces") {
    struct Apercu: View {
        @State private var screen = MeetingScreenModel()
        var body: some View {
            VStack(spacing: 0) {
                MeetingSpacesBar(screen: screen, kind: .project,
                                 hasReport: true, documentsCount: 0,
                                 date: .now)
                MeetingSpacesBar(screen: screen, kind: .note,
                                 hasReport: false, documentsCount: 3,
                                 date: .now)
                Spacer()
            }
            .frame(width: 900, height: 140)
            .background(One2OneToken.bgCanvas)
        }
    }
    return Apercu()
}
