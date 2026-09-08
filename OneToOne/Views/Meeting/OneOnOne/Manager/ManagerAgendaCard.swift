import SwiftUI
import SwiftData

/// `ORDRE DU JOUR · co-construit` (capture 2a, colonne gauche).
///
/// Chaque sujet porte l'avatar 16 px de celui qui l'a ajouté, un sujet traité
/// ou reporté est barré, un sujet reporté affiche `→ 18/09`, et le composeur du
/// pied ajoute en fin de liste (`⌘⏎`).
///
/// Le glisser-réordonner est fait à la main (`onDrag` / `onDrop`) et non avec
/// une `List` : la colonne est déjà dans une `ScrollView`, et une `List`
/// imbriquée y déclenche le `_NSDetectedLayoutRecursion` que le programme §2.4
/// demande d'éviter.
struct ManagerAgendaCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    /// Nom de l'utilisateur de l'application, pour ses initiales.
    let ownerName: String

    @Environment(\.modelContext) private var context
    @State private var brouillon = ""
    @State private var glisse: PersistentIdentifier?

    private var lignes: [ManagerAgendaModel.Row] {
        ManagerAgendaModel.rows(for: meeting, in: thread, ownerName: ownerName)
    }

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SectionLabel(ManagerAgendaModel.title)
                    Pill(ManagerAgendaModel.badge, ton: .oneOnOne)
                    Spacer(minLength: 0)
                }

                let lignes = lignes
                if lignes.isEmpty {
                    Text(ManagerAgendaModel.emptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(lignes.enumerated()), id: \.element.id) { index, ligne in
                            self.ligne(ligne)
                                .onDrag {
                                    glisse = ligne.id
                                    return NSItemProvider(object: NSString(string: "sujet"))
                                }
                                .onDrop(of: [.text], isTargeted: nil) { _ in
                                    deplacer(vers: index, dans: lignes)
                                }
                        }
                    }
                }

                composeur
            }
        }
    }

    // MARK: - Ligne

    private func ligne(_ ligne: ManagerAgendaModel.Row) -> some View {
        HStack(alignment: .top, spacing: 7) {
            AvatarSide(initials: ligne.initials,
                       identity: identite(de: ligne.item.addedBySide),
                       aide: "Ajouté par \(identite(de: ligne.item.addedBySide))")
                // Aligné sur la première ligne de texte, pas sur son centre :
                // un sujet sur deux lignes ferait descendre la pastille.
                .padding(.top, 1)
            Text(ligne.item.text)
                .font(.plexSans(12))
                .foregroundStyle(ligne.isStruck ? One2OneToken.ink4 : One2OneToken.ink2)
                .strikethrough(ligne.isStruck, color: One2OneToken.ink4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let cible = ligne.deferredLabel {
                MonoMeta(cible)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { menu(ligne) }
    }

    @ViewBuilder
    private func menu(_ ligne: ManagerAgendaModel.Row) -> some View {
        let item = ligne.item
        Button(item.state == .done ? "Rouvrir le sujet" : "Marquer traité") {
            item.state = item.state == .done ? .todo : .done
            try? context.save()
        }
        Button("Reporter au prochain") {
            // Le report passe par le service du lot 10 : c'est lui qui copie
            // le sujet sur la séance suivante, et qui reste idempotent.
            AgendaCarryover.carryOver(from: meeting,
                                      to: OneOnOneThreadStore.nextMeeting(after: meeting,
                                                                          in: thread),
                                      in: thread,
                                      in: context)
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            context.delete(item)
            try? context.save()
        }
    }

    // MARK: - Composeur

    private var composeur: some View {
        OneOnOneInlineComposer(placeholder: ManagerAgendaModel.composerPlaceholder,
                               text: $brouillon) {
            ManagerAgendaModel.add(brouillon, for: meeting, in: thread,
                                   role: thread.myRole, in: context)
            brouillon = ""
        }
    }

    // MARK: - Outils

    private func deplacer(vers destination: Int, dans lignes: [ManagerAgendaModel.Row]) -> Bool {
        guard let glisse, let origine = lignes.firstIndex(where: { $0.id == glisse }) else {
            return false
        }
        self.glisse = nil
        guard origine != destination else { return false }
        // `move(fromOffsets:toOffset:)` insère **avant** l'index donné : pour
        // un déplacement vers le bas, la destination est donc décalée d'un.
        let cible = destination > origine ? destination + 1 : destination
        ManagerAgendaModel.move(for: meeting, in: thread,
                                from: IndexSet(integer: origine), to: cible, in: context)
        return true
    }

    private func identite(de side: OneOnOneSide) -> String {
        side == thread.myRole ? (ownerName.isEmpty ? "Moi" : ownerName)
                              : PersonCardModel.name(of: thread)
    }
}

/// `RESTÉ EN SUSPENS` (capture 2a) : les sujets reportés du fil et les sujets
/// récurrents que rien n'a tranchés, chacun avec son nombre d'occurrences.
///
/// La pastille de gauche est un **demi-cercle** ambre : ni une case à cocher
/// (rien n'est à cocher ici) ni un point plein (le sujet n'est pas clos) — un
/// demi-cercle dit « à moitié traité », ce qui est exactement l'état.
struct ManagerPendingTopicsCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    var now: Date = Date()
    /// Met le sujet à l'ordre du jour de la séance.
    let onAddToAgenda: (String) -> Void

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(ManagerAgendaModel.pendingTitle)
                let entrees = ManagerAgendaModel.pendingEntries(thread, for: meeting, now: now)
                if entrees.isEmpty {
                    Text(ManagerAgendaModel.pendingEmptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(entrees, id: \.text) { entree in
                        HStack(alignment: .top, spacing: 7) {
                            demiCercle
                            Text(ManagerAgendaModel.pendingLabel(entree))
                                .font(.plexSans(12))
                                .foregroundStyle(One2OneToken.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Mettre à l'ordre du jour") { onAddToAgenda(entree.text) }
                        }
                        .help("Clic droit : mettre à l'ordre du jour")
                    }
                }
            }
        }
    }

    private var demiCercle: some View {
        Circle()
            .trim(from: 0.5, to: 1)
            .fill(One2OneToken.warn)
            .overlay(Circle().strokeBorder(One2OneToken.warn, lineWidth: 1.2))
            .frame(width: 10, height: 10)
            .padding(.top, 3)
    }
}
