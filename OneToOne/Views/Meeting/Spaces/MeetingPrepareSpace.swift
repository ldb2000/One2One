import SwiftUI
import SwiftData

/// Le mode Préparer de l'espace Réunion (spec §2.2) : « Actions ouvertes
/// reportées + derniers points + alertes en colonne principale ; rail réduit »,
/// focus clavier sur le composeur de sujet.
///
/// Pour les types 1:1 et Atelier, ce même contenu s'affiche pour l'instant :
/// leurs écrans dédiés arrivent aux lots 12, 14 et 18. Le composeur de sujet
/// réutilise `MeetingPrepTab` — c'est déjà l'éditeur markdown du brouillon de
/// préparation, et le programme interdit de le réécrire ici.
struct MeetingPrepareSpace: View {
    @Bindable var meeting: Meeting
    let contexte: MeetingPrepareContext
    /// Ouvre la réunion citée dans « DERNIERS POINTS ».
    let onOpenMeeting: (PersistentIdentifier) -> Void
    /// Coche ou décoche une action reportée.
    let onToggleAction: (PersistentIdentifier) -> Void

    /// La colonne principale seule : le rail de 330 px est monté par
    /// `MeetingSpaceView`, pour **tous** les modes (spec §2.5 : il est
    /// permanent). Le lot 1 l'avait esquissé ici, faute de rail à installer ;
    /// le garder produirait deux rails côte à côte.
    var body: some View {
        colonnePrincipale
    }

    // MARK: - Colonne principale

    private var colonnePrincipale: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                actionsReportees
                derniersPoints
                alertes
                composeurDeSujet
            }
            .padding(14)
        }
    }

    private var actionsReportees: some View {
        section("ACTIONS REPORTÉES", compte: contexte.carriedActions.count) {
            if contexte.carriedActions.isEmpty {
                MeetingEmptyInvite(
                    titre: "Rien de reporté",
                    invite: "Les actions ouvertes de la réunion précédente du projet apparaîtront ici."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(contexte.carriedActions) { action in
                        HStack(spacing: 8) {
                            Button { onToggleAction(action.id) } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(One2OneToken.ink4)
                            }
                            .buttonStyle(.plain)
                            .help("Marquer comme faite")
                            Text(action.title)
                                .font(.plexSans(12))
                                .foregroundStyle(One2OneToken.ink2)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if action.deferralCount > 0 {
                                Chip("\(action.deferralCount)× reporté", ton: .report)
                            }
                            if !action.fromTitle.isEmpty {
                                MonoMeta(action.fromTitle)
                            }
                        }
                        .padding(.vertical, One2OneToken.tableRowPaddingV)
                        if action.id != contexte.carriedActions.last?.id {
                            Rectangle().fill(One2OneToken.hair).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var derniersPoints: some View {
        section("DERNIERS POINTS", compte: contexte.lastPoints.count) {
            if contexte.lastPoints.isEmpty {
                MeetingEmptyInvite(
                    titre: "Première réunion de ce dossier",
                    invite: "Les trois dernières réunions du projet, avec leur résumé, apparaîtront ici."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(contexte.lastPoints) { point in
                        Button { onOpenMeeting(point.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(point.title.isEmpty ? "Sans titre" : point.title)
                                        .font(.plexSans(12, .medium))
                                        .foregroundStyle(One2OneToken.ink1)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    MonoMeta(MeetingAssistantDock.dateCourte(point.date))
                                }
                                Text(point.shortSummary.isEmpty
                                     ? "Pas de résumé — le rapport n'a pas été généré."
                                     : point.shortSummary)
                                    .font(.plexSans(11.5))
                                    .foregroundStyle(point.shortSummary.isEmpty
                                                     ? One2OneToken.inkMuted
                                                     : One2OneToken.ink3)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, One2OneToken.tableRowPaddingV)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if point.id != contexte.lastPoints.last?.id {
                            Rectangle().fill(One2OneToken.hair).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var alertes: some View {
        section("ALERTES PROJET", compte: contexte.alertTitles.count) {
            if contexte.alertTitles.isEmpty {
                MeetingEmptyInvite(
                    titre: "Aucune alerte ouverte",
                    invite: "Les risques non résolus du projet apparaîtront ici, du plus grave au plus faible."
                )
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(contexte.alertTitles, id: \.self) { titre in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(One2OneToken.warn)
                                .frame(width: MeetingKPIBand.riskDot, height: MeetingKPIBand.riskDot)
                            Text(titre)
                                .font(.plexSans(12))
                                .foregroundStyle(One2OneToken.ink2)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    /// Le focus clavier du mode Préparer, d'après la spec §2.2. Réutilise
    /// `MeetingPrepTab` : c'est déjà l'éditeur markdown de `prepNotes`, avec
    /// son panneau de contexte et sa génération IA.
    private var composeurDeSujet: some View {
        section("SUJETS À METTRE À L'ORDRE DU JOUR", compte: nil) {
            MeetingPrepTab(meeting: meeting)
                .frame(minHeight: 320)
        }
    }

    // MARK: - Fabrique de section

    @ViewBuilder
    private func section<Content: View>(_ libelle: String,
                                        compte: Int?,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(libelle).sectionLabel()
                if let compte { MonoMeta("\(compte)", emphase: compte > 0) }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(One2OneToken.cardPaddingMax)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }
}
