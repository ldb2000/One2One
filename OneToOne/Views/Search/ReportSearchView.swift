import SwiftUI
import SwiftData

/// L'écran de résultats de « Chercher « x » dans les CR », le second bras de
/// la palette `⌘K` (décision **D8**).
///
/// **Un assembleur.** Le filtrage, le groupement, l'ordre et le découpage des
/// extraits sont dans `ReportSearch`, testés avant cette vue (**D11**) ; le
/// surlignage est celui de la palette (`HighlightedText`, donc
/// `ProjectSearch.highlightRanges`) — l'extrait et le nom de projet se
/// surlignent avec la règle qui a décidé de la correspondance.
///
/// **Un clic ouvre la réunion**, par le mécanisme existant :
/// `QuickLaunchRouter.pendingToken`, celui que la barre du menu système, les
/// intents et le semis de recette emploient déjà. La fenêtre de réunion
/// s'ouvre alors sur son propre `WindowGroup` ; l'écran de résultats reste
/// derrière, ce qui permet d'en ouvrir plusieurs à la suite.
struct ReportSearchView: View {

    /// Titre d'écran, même mesure que le Portfolio (handoff §Typographie).
    static let tailleTitre: CGFloat = 17
    static let tailleSousTitre: CGFloat = 12
    /// Le nom du projet en tête de groupe.
    static let tailleGroupe: CGFloat = 12
    /// Titre de réunion, et son extrait.
    static let tailleTitreReunion: CGFloat = 13
    static let tailleExtrait: CGFloat = 12
    /// La colonne de date et l'étiquette de champ, en mono.
    static let tailleMeta: CGFloat = 11
    /// Largeur de la colonne de date — la mesure de la liste des dernières
    /// réunions de l'écran projet (handoff §1d).
    static let colonneDate: CGFloat = 44
    static let marge: CGFloat = 22

    /// Le terme cherché, porté par la route `MainRoute.searchReports(_:)`.
    let terme: String

    @Query private var reunions: [Meeting]

    /// Les résultats, calculés **hors** de `body` (décision **D11**) : la
    /// recherche traverse `Meeting.textualContent` de toutes les réunions du
    /// store, transcriptions comprises, et `body` peut être rejoué à chaque
    /// image.
    @State private var groupes: [ReportSearchGroup] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider().overlay(One2OneToken.hair)

            if groupes.isEmpty {
                Text(ReportSearch.libelleAucunResultat)
                    .font(.plexSans(Self.tailleSousTitre))
                    .foregroundStyle(One2OneToken.ink4)
                    .padding(Self.marge)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupes) { groupe in
                            section(groupe)
                        }
                    }
                    .padding(.horizontal, Self.marge)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(One2OneToken.bgApp)
        .onAppear { recharger() }
        // Le terme vient de la route : réactiver « Chercher » depuis la
        // palette remonte le même écran avec un autre terme.
        .onChange(of: terme) { recharger() }
        .onChange(of: reunions) { recharger() }
    }

    private func recharger() {
        groupes = ReportSearch.groupes(in: reunions, query: terme)
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ReportSearch.titre)
                .font(.plexSans(Self.tailleTitre, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text(ReportSearch.sousTitre(reunions: ReportSearch.nombreDeReunions(groupes),
                                        terme: terme))
                .font(.plexSans(Self.tailleSousTitre))
                .foregroundStyle(One2OneToken.inkMuted)
        }
        .padding(.horizontal, Self.marge)
        .padding(.vertical, 14)
    }

    // MARK: - Un projet

    private func section(_ groupe: ReportSearchGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HighlightedText(texte: groupe.projet,
                            terme: terme,
                            fonte: .plexSans(Self.tailleGroupe, .semibold),
                            encre: One2OneToken.ink2)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groupe.resultats.enumerated()), id: \.element.id) { rang, hit in
                    if rang > 0 { Divider().overlay(One2OneToken.hair) }
                    ligne(hit)
                }
            }
            .background(One2OneToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusCard,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Une réunion

    private func ligne(_ hit: ReportSearchHit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Self.dateFormatter.string(from: hit.date))
                .font(.plexMono(Self.tailleMeta))
                .foregroundStyle(One2OneToken.inkMuted)
                .frame(width: Self.colonneDate, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    HighlightedText(texte: hit.titre,
                                    terme: terme,
                                    fonte: .plexSans(Self.tailleTitreReunion, .medium))
                        .lineLimit(1)
                    Text(hit.etiquette)
                        .font(.plexMono(Self.tailleMeta))
                        .foregroundStyle(One2OneToken.ink4)
                }
                HighlightedText(texte: hit.extrait,
                                terme: terme,
                                fonte: .plexSans(Self.tailleExtrait),
                                encre: One2OneToken.ink3)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { ouvrir(hit) }
    }

    // MARK: - Ouverture

    /// Ouvre la réunion dans sa fenêtre, par le jeton de lancement existant.
    ///
    /// `hit.stableID` est optionnel — un constructeur pur ne peut pas
    /// backfiller —, donc la réunion est retrouvée dans la requête de cet
    /// écran pour appeler `ensuredStableID`, la seule voie qui garantisse un
    /// identifiant.
    private func ouvrir(_ hit: ReportSearchHit) {
        guard let reunion = reunions.first(where: { $0.persistentModelID == hit.meetingID })
        else { return }
        QuickLaunchRouter.shared.pendingToken =
            OneToOneLaunchToken(meetingID: reunion.ensuredStableID,
                                autoStartRecording: false)
    }
}
