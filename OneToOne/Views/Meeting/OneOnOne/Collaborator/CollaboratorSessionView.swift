import SwiftUI
import SwiftData

/// L'écran de séance du 1:1 **subi** (capture `5a-1to1-collaborateur-seance.png`,
/// spec §6.2) : grille `308 | 1fr | 356`.
///
/// Le même type de réunion que la capture 2a, le rôle inversé — et ce n'est pas
/// une variante cosmétique. Dans un 1:1 mené, on cherche à comprendre la
/// personne d'en face ; ici on cherche à **ne rien oublier de ce qu'on veut
/// dire**, à **prouver ce qu'on a livré** et à **suivre ce qu'on nous a
/// promis**. D'où trois colonnes que le côté manager n'a pas :
///
/// | Colonne | Contenu |
/// | --- | --- |
/// | Gauche 308 | `CE QUE JE VEUX DIRE` (brouillon privé, ordonnable), `MES DEMANDES EN COURS`, barre assistant |
/// | Centre 1fr | `Notes de l'entretien`, `● Privé par défaut` / `Partager la ligne`, `CE QU'IL M'A DIT` / `CE QUE J'AI DIT`, composeur `/promesse /demande /preuve` |
/// | Droite 356 | `CE QUE J'AI LIVRÉ` (auto), `CE QU'IL M'A PROMIS`, `EN SORTANT` |
///
/// Comme l'écran de séance mené : ni rail d'actions, ni bandeau d'indicateurs,
/// ni présence (spec §3.1, qui vaut pour les deux types 1:1). Le fil est créé
/// paresseusement au premier affichage (D3).
struct CollaboratorSessionView: View {

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Réunions connues — pour le panneau d'assistant **et** pour
    /// `CE QUE J'AI LIVRÉ`, qui compte les réunions où j'ai eu un rôle actif.
    let historique: [Meeting]
    /// L'assistant est ouvert. Partagé avec `⌘K`.
    @Binding var isAssistantOpen: Bool
    /// Ouvre la modale de gestion des participants — le seul geste possible
    /// quand l'entretien n'a personne en face.
    let onManageParticipants: () -> Void

    @Environment(\.modelContext) private var context

    /// L'instant de référence de l'écran : la **date de la séance**, et non
    /// `Date()`. « 1 en retard », « depuis le 21 août » et le ton des demandes
    /// parlent de l'entretien qu'on tient, pas du jour où on le relit.
    private var maintenant: Date { meeting.date }

    var body: some View {
        if let fil = OneOnOneThreadStore.thread(for: meeting, in: context) {
            grille(fil)
        } else {
            MeetingEmptyInvite(titre: "Aucun manager pour cet entretien",
                               invite: "Un 1:1 se tient avec quelqu'un : ajoutez votre manager comme participant pour ouvrir le fil.",
                               libelleAction: "Gérer les participants",
                               action: onManageParticipants)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(One2OneToken.bgCanvas)
        }
    }

    // MARK: - Grille

    private func grille(_ fil: OneOnOneThread) -> some View {
        GeometryReader { geo in
            let colonnes = MeetingSpaceLayout.collaboratorColumns(totalWidth: geo.size.width)
            HStack(alignment: .top, spacing: 0) {
                if colonnes.left > 0 {
                    colonneGauche(fil)
                        .frame(width: colonnes.left)
                    filet
                }
                CollaboratorNotesColumn(meeting: meeting, thread: fil, screen: screen)
                    .frame(width: colonnes.center - marge(colonnes))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                if colonnes.rail > 0 {
                    filet
                    colonneDroite(fil)
                        .frame(width: colonnes.rail - MeetingSpaceLayout.hairlineWidth)
                }
            }
        }
        .background(One2OneToken.bgCanvas)
    }

    /// Les filets consomment de la largeur : la colonne centrale les rend, pour
    /// que la somme des trois colonnes tienne exactement la fenêtre (sinon la
    /// dernière déborde d'un ou deux pixels et le rail se décale). Même règle
    /// que `ManagerSessionView`.
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
                    MyTopicsCard(meeting: meeting, thread: fil)
                    MyRequestsCard(thread: fil, now: maintenant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // La barre d'assistant est ancrée en pied, hors du défilement : une
            // barre qui défile avec le brouillon ne serait plus là quand on la
            // cherche. Sa question est celle de la capture, datée du dernier
            // point tenu.
            MeetingAssistantDock(
                meeting: meeting,
                historique: historique,
                isOpen: $isAssistantOpen,
                contexte: MeetingAssistantDock.Contexte(
                    placeholder: CollaboratorSessionModel.assistantSuggestion(fil,
                                                                              for: meeting),
                    threadID: fil.ensuredStableID))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Colonne droite

    private func colonneDroite(_ fil: OneOnOneThread) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DeliveredCard(meeting: meeting, thread: fil,
                              historique: historique, now: maintenant)
                separateur
                PromisesCard(meeting: meeting, thread: fil, now: maintenant)
                separateur
                CollaboratorClosingCard(meeting: meeting, thread: fil, now: maintenant)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(One2OneToken.bgApp)
    }

    private var separateur: some View {
        Rectangle().fill(One2OneToken.hair).frame(height: 1)
    }
}
