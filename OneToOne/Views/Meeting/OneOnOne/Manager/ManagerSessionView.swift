import SwiftUI
import SwiftData

/// L'écran de séance du 1:1 **mené** (capture `2a-1to1-manager-seance.png`,
/// spec §3.3) : grille `300 | 1fr | 320`.
///
/// Ce que cet écran **n'a pas**, et c'est le point de la spec §3.1 : ni rail
/// d'actions, ni bandeau d'indicateurs, ni présence, ni quorum, ni projets
/// affectés. Un entretien se tient en regardant la personne ; tout ce qui
/// regarde ailleurs a été retiré. La capture d'écran reste accessible depuis le
/// menu `⋯` de la barre du haut.
///
/// Le fil est créé **paresseusement** au premier affichage
/// (`OneOnOneThreadStore.thread(for:in:)`, D3) : ouvrir un entretien est le
/// premier moment où l'on sait qu'un fil existe. Sans participant, il n'y a
/// personne avec qui tenir un fil — l'écran le dit et propose d'en ajouter un
/// plutôt que de rendre une colonne vide.
struct ManagerSessionView: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Réunions connues, pour le panneau d'assistant.
    let historique: [Meeting]
    /// L'assistant est ouvert. Partagé avec `⌘K`.
    @Binding var isAssistantOpen: Bool
    /// Ouvre la modale de gestion des participants — le seul geste possible
    /// quand l'entretien n'a personne en face.
    let onManageParticipants: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]

    /// Le nom de l'utilisateur de l'application, pour les initiales de « Moi ».
    private var ownerName: String { settings.first?.ownerName ?? "" }

    /// L'instant de référence de l'écran : la **date de la séance**, et non
    /// `Date()`. Les métriques (« il y a 2 sem. », « Vendredi », « tenus depuis
    /// le dernier 1:1 ») parlent de l'entretien qu'on tient, pas du jour où on
    /// le relit trois mois plus tard.
    private var maintenant: Date { meeting.date }

    var body: some View {
        if let fil = OneOnOneThreadStore.thread(for: meeting, in: context) {
            grille(fil)
        } else {
            MeetingEmptyInvite(titre: "Aucune personne pour cet entretien",
                               invite: "Un 1:1 se tient avec quelqu'un : ajoutez le participant pour ouvrir son fil.",
                               libelleAction: "Gérer les participants",
                               action: onManageParticipants)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(One2OneToken.bgCanvas)
        }
    }

    // MARK: - Grille

    private func grille(_ fil: OneOnOneThread) -> some View {
        GeometryReader { geo in
            let colonnes = MeetingSpaceLayout.oneOnOneColumns(totalWidth: geo.size.width)
            HStack(alignment: .top, spacing: 0) {
                if colonnes.left > 0 {
                    colonneGauche(fil)
                        .frame(width: colonnes.left)
                    filet
                }
                ManagerNotesColumn(meeting: meeting, thread: fil, screen: screen)
                    .frame(width: colonnes.center - marge(colonnes))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                if colonnes.rail > 0 {
                    filet
                    CommitmentsRail(meeting: meeting, thread: fil,
                                    ownerName: ownerName, now: maintenant)
                        .frame(width: colonnes.rail - MeetingSpaceLayout.hairlineWidth)
                }
            }
        }
        .background(One2OneToken.bgCanvas)
    }

    /// Les filets consomment de la largeur : la colonne centrale les rend, pour
    /// que la somme des trois colonnes tienne exactement la fenêtre (sinon la
    /// dernière déborde d'un ou deux pixels et le rail se décale).
    private func marge(_ colonnes: (left: CGFloat, center: CGFloat, rail: CGFloat)) -> CGFloat {
        var largeur: CGFloat = 0
        if colonnes.left > 0 { largeur += MeetingSpaceLayout.hairlineWidth }
        if colonnes.rail > 0 { largeur += MeetingSpaceLayout.hairlineWidth }
        return largeur
    }

    private var filet: some View {
        Rectangle()
            .fill(One2OneToken.hair)
            .frame(width: MeetingSpaceLayout.hairlineWidth)
            .frame(maxHeight: .infinity)
    }

    // MARK: - Colonne gauche

    private func colonneGauche(_ fil: OneOnOneThread) -> some View {
        VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
            ScrollView {
                VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                    PersonCard(thread: fil, now: maintenant)
                    ManagerAgendaCard(meeting: meeting, thread: fil, ownerName: ownerName)
                    ManagerPendingTopicsCard(meeting: meeting, thread: fil, now: maintenant) { sujet in
                        ManagerAgendaModel.add(sujet, for: meeting, in: fil,
                                               role: fil.myRole, in: context)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // La barre d'assistant est ancrée en pied, hors du défilement : la
            // spec §3.3 la place « en pied de colonne », et une barre qui
            // défile avec l'ordre du jour ne serait plus là quand on la
            // cherche.
            MeetingAssistantDock(meeting: meeting,
                                 historique: historique,
                                 isOpen: $isAssistantOpen,
                                 contexte: .fil(of: fil))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
