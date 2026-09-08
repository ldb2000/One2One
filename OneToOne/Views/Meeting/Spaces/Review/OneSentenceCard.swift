import SwiftUI

/// La carte `EN UNE PHRASE` du poste de pilotage (spec §2.7 : « carte
/// `EN UNE PHRASE` (résumé généré + tags de sujets) », capture
/// `1c-poste-de-pilotage.png`).
///
/// Le résumé est `Meeting.shortSummary`, généré par **la seule** fonction de
/// l'application qui le fasse (`MeetingSummaryService.generate`) : deux
/// définitions du « texte de la réunion » finiraient par produire deux résumés
/// différents pour la même séance.
///
/// Vide, la carte n'affiche pas un cadre blanc mais une invite qui dit quoi
/// faire (critère d'acceptation n° 1 du chantier 1).
struct OneSentenceCard: View {

    let meeting: Meeting
    let settings: AppSettings
    /// Vrai pendant la génération.
    let isSummarizing: Bool
    /// Lance la génération du résumé court.
    let onSummarize: () -> Void

    /// Le résumé rendu avec son gras (`**AP**`, `**Décision**` de la capture).
    ///
    /// `AttributedString(markdown:)` plutôt que `MarkdownText` : celle-ci
    /// impose ses propres fontes, et le corps de cette carte doit rester en
    /// Plex Sans 12,5 (spec §1.2). Le markdown illisible retombe sur le texte
    /// brut — un résumé mal formé se lit encore, une carte vide non.
    static func texteRiche(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }

    var body: some View {
        ReviewCard {
            HStack(spacing: 7) {
                SectionLabel("en une phrase")
                if !meeting.shortSummary.isEmpty {
                    Chip("généré", ton: .action)
                }
                Spacer(minLength: 0)
                if isSummarizing {
                    ProgressView().controlSize(.small)
                }
            }
            if meeting.shortSummary.isEmpty {
                MeetingEmptyInvite(
                    titre: "Pas encore de synthèse",
                    invite: "Une phrase suffit à retrouver cette réunion dans six mois — générez-la depuis la transcription.",
                    libelleAction: isSummarizing ? nil : "Générer la synthèse",
                    action: isSummarizing ? nil : onSummarize
                )
            } else {
                Text(Self.texteRiche(meeting.shortSummary))
                    .font(.plexSans(12.5))
                    .foregroundStyle(One2OneToken.ink2)
                    .lineSpacing(12.5 * 0.55)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                tags
            }
        }
    }

    /// Les thèmes de la réunion (`MeetingTag`), en chips carrées.
    ///
    /// Une réunion sans thème n'affiche pas une rangée vide : le rapport en
    /// propose (`MeetingView.suggestTags`), et c'est là qu'on les accepte.
    @ViewBuilder
    private var tags: some View {
        if !meeting.tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(meeting.tags) { tag in
                    Chip(tag.name, ton: .neutre)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }
}

/// La carte du poste de pilotage : fond `surface`, contour `border/card`,
/// rayon 7–8, padding 9–13 (spec §1.2).
///
/// Une seule fabrique pour les trois cartes du mode : `MeetingReviewSpace` en
/// avait une locale, chaque nouvelle carte en aurait redéfini une, et les
/// paddings auraient divergé d'un pixel à chaque fois.
struct ReviewCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(One2OneToken.cardPaddingMax)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }
}
