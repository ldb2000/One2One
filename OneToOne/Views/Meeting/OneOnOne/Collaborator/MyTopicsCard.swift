import SwiftUI
import SwiftData

/// `CE QUE JE VEUX DIRE · ● privé` (capture 5a, colonne gauche) : mon brouillon
/// de séance, numéroté et ordonnable.
///
/// Ce n'est **pas** l'ordre du jour co-construit du 1:1 mené : personne d'autre
/// n'y écrit, personne d'autre ne le voit, et son ordre est le mien — c'est
/// l'ordre dans lequel je compte parler si le temps manque. D'où les numéros
/// (un ordre du jour partagé n'en a pas) et la poignée `⠿`.
///
/// Le glisser-réordonner est fait à la main (`onDrag` / `onDrop`) et non avec
/// une `List` : la colonne est déjà dans une `ScrollView`, et une `List`
/// imbriquée y déclenche le `_NSDetectedLayoutRecursion` que le programme §2.4
/// demande d'éviter. Même choix qu'au lot 11.
struct MyTopicsCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread

    @Environment(\.modelContext) private var context
    @State private var brouillon = ""
    @State private var glisse: PersistentIdentifier?

    private var sujets: [OneOnOneAgendaItem] {
        CollaboratorSessionModel.myTopics(thread, for: meeting)
    }

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 8) {
                entete
                let sujets = sujets
                if sujets.isEmpty {
                    Text(CollaboratorSessionModel.myTopicsEmptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(sujets.enumerated()), id: \.element.persistentModelID) {
                            index, sujet in
                            ligne(sujet, numero: index)
                                .onDrag {
                                    glisse = sujet.persistentModelID
                                    return NSItemProvider(object: NSString(string: "sujet"))
                                }
                                .onDrop(of: [.text], isTargeted: nil) { _ in
                                    deplacer(vers: index, dans: sujets)
                                }
                        }
                    }
                }
                composeur
                Text(CollaboratorSessionModel.myTopicsMention)
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - En-tête

    /// La pilule `● privé` est en **tête de carte** (spec §6.2) et non sur
    /// chaque ligne : toutes les lignes le sont, et la répéter trois fois
    /// ferait du décor qu'on cesse de lire.
    private var entete: some View {
        HStack(spacing: 6) {
            SectionLabel(CollaboratorSessionModel.myTopicsTitle)
            Spacer(minLength: 0)
            Pill(CollaboratorSessionModel.privacyPill, ton: .oneOnOne)
                .help("Ce brouillon n'est visible que de vous — rien n'en sort sans un geste de votre part")
        }
    }

    // MARK: - Ligne

    private func ligne(_ sujet: OneOnOneAgendaItem, numero: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(CollaboratorSessionModel.topicNumber(numero))
                .font(.plexMono(10.5, .medium))
                .foregroundStyle(One2OneToken.oneOnOneInk)
                .frame(width: 12, alignment: .trailing)
                // Aligné sur la première ligne de texte, pas sur son centre :
                // un sujet sur deux lignes ferait descendre le numéro.
                .padding(.top, 1)
            Text(sujet.text)
                .font(.plexSans(12))
                .foregroundStyle(sujet.state == .todo ? One2OneToken.ink2 : One2OneToken.ink4)
                .strikethrough(sujet.state != .todo, color: One2OneToken.ink4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(CollaboratorSessionModel.dragHandle)
                .font(.plexSans(11))
                .foregroundStyle(One2OneToken.ink4)
                .padding(.top, 1)
        }
        .padding(One2OneToken.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .fill(One2OneToken.bgCanvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .help("Glisser pour classer — clic droit pour partager ou supprimer")
        .contextMenu { menu(sujet) }
    }

    @ViewBuilder
    private func menu(_ sujet: OneOnOneAgendaItem) -> some View {
        Button(sujet.state == .done ? "Rouvrir le sujet" : "Marquer dit") {
            sujet.state = sujet.state == .done ? .todo : .done
            try? context.save()
        }
        // Le seul chemin qui rend un sujet visible du manager, et il est
        // explicite (critère chantier 5 n° 2). La bascule passe par le service
        // du lot 10 : depuis `escalated`, on redescend vers `private`.
        Button(sujet.visibility == .private ? "Partager ce sujet" : "Rendre privé") {
            sujet.visibility = OneOnOneConfidentiality.toggledPrivacy(sujet.visibility,
                                                                       role: .collaborator)
            try? context.save()
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            context.delete(sujet)
            try? context.save()
        }
    }

    // MARK: - Composeur

    private var composeur: some View {
        HStack(spacing: 8) {
            OneOnOneInlineComposer(
                placeholder: CollaboratorSessionModel.myTopicsComposerPlaceholder,
                text: $brouillon
            ) {
                ManagerAgendaModel.add(brouillon, for: meeting, in: thread,
                                       role: .collaborator, in: context)
                brouillon = ""
            }
            Text(CollaboratorSessionModel.dragHint)
                .font(.plexMono(10))
                .foregroundStyle(One2OneToken.ink4)
                .fixedSize()
        }
    }

    // MARK: - Outils

    private func deplacer(vers destination: Int, dans sujets: [OneOnOneAgendaItem]) -> Bool {
        guard let glisse,
              let origine = sujets.firstIndex(where: { $0.persistentModelID == glisse }) else {
            return false
        }
        self.glisse = nil
        guard origine != destination else { return false }
        // `move(fromOffsets:toOffset:)` insère **avant** l'index donné : pour un
        // déplacement vers le bas, la destination est décalée d'un.
        let cible = destination > origine ? destination + 1 : destination
        // Le réordonnancement **compacte** les rangs : sans compactage, deux
        // glissers de suite produisent des rangs égaux et l'ordre choisi à la
        // main est silencieusement perdu.
        CollaboratorSessionModel.moveTopics(for: meeting, in: thread,
                                            from: IndexSet(integer: origine),
                                            to: cible, in: context)
        return true
    }
}
