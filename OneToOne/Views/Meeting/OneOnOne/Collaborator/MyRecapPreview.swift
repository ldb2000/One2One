import SwiftUI
import SwiftData

/// L'aperçu du bouton `Mon récap` de la barre du haut (capture 5a).
///
/// Montre **exactement** ce qui partira : le récap filtré pour l'audience
/// `.manager`, produit par `OneOnOneRecapBuilder`. Aucun texte n'est recomposé
/// ici — un aperçu qui ne serait pas le texte envoyé serait pire qu'aucun
/// aperçu, puisqu'il rassurerait à tort.
///
/// C'est la contrepartie du défaut `private` : je peux vérifier, avant
/// d'envoyer, que ce que j'ai gardé pour moi est bien resté pour moi.
struct MyRecapPreview: View {

    let meeting: Meeting

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Le fil, retrouvé sans en créer : un aperçu ne doit rien écrire.
    private var thread: OneOnOneThread? {
        guard let personne = meeting.participants.first else { return nil }
        return OneOnOneThreadStore.existingThread(for: personne, role: .collaborator,
                                                  in: context)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete
            Divider()
            corps
            Spacer(minLength: 0)
            pied
        }
        .padding(16)
        .frame(width: 520, height: 560)
        .background(One2OneToken.bgCanvas)
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mon récap")
                .font(.plexSans(14, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("Ce que verra votre manager, et rien de plus.")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
        }
    }

    @ViewBuilder
    private var corps: some View {
        if let thread {
            ScrollView {
                Text(OneOnOneRecapBuilder.markdown(
                        for: meeting, thread: thread,
                        audience: OneOnOneConfidentiality.recapAudience(for: thread.myRole),
                        now: meeting.date))
                    .font(.plexMono(11))
                    .foregroundStyle(One2OneToken.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                    .fill(One2OneToken.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                    .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
            )
        } else {
            // Pas encore de fil : l'entretien n'a pas de participant, donc
            // aucun récap n'a de destinataire.
            Text("Ajoutez votre manager comme participant pour voir votre récap.")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pied: some View {
        HStack(spacing: 8) {
            if let thread,
               let compte = CollaboratorSessionModel.excludedLinesLabel(for: meeting,
                                                                         in: thread) {
                Text(compte)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.oneOnOneInk)
            }
            Spacer(minLength: 8)
            Button("Fermer") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
