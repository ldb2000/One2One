import SwiftUI
import SwiftData

/// Le bandeau `EN ATTENTE — n actions sans responsable` en pied de la colonne
/// de notes, et son bouton `Assigner maintenant` (capture
/// `1b-mode-seance.png`, spec §2.6).
///
/// Disparaît quand tout est assigné : un bandeau qui annonce « 0 action sans
/// responsable » occupe la place d'une note.
struct SessionPendingBand: View {

    let actions: [ActionTask]
    let onAssign: () -> Void

    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }

    var body: some View {
        if let libelle = PendingAssignment.libelle(actions.count) {
            HStack(spacing: 12) {
                Text("En attente").sectionLabel()
                Text(libelle)
                    .font(.plexSans(12))
                    .foregroundStyle(c.ink2)
                Spacer(minLength: 12)
                Button(action: onAssign) {
                    Text("Assigner maintenant")
                        .font(.plexSans(12, .semibold))
                        .foregroundStyle(One2OneToken.onFilledButton)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                             style: .continuous)
                                .fill(One2OneToken.action)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir la file d'assignation : responsable, échéance, suivante")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(c.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(c.cardBorder, lineWidth: 1)
            )
        }
    }
}

/// La file d'assignation : responsable → échéance → suivante, trois gestes par
/// action (spec §2.6).
///
/// Toute la règle est dans `AssignmentQueue`, pure et testée ; cette vue ne
/// fait que la rendre et écrire dans le modèle. Elle reprend `OwnerPickerMenu`
/// et les raccourcis d'échéance du lot 3 (`ActionCardEditing.raccourcisEcheance`)
/// plutôt que d'en redessiner : trois sélecteurs de responsable dans
/// l'application finiraient par ne plus proposer les mêmes personnes.
struct AssignmentQueueSheet: View {

    let actions: [ActionTask]
    let allCollaborators: [Collaborator]
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.one2OneTheme) private var theme
    private var c: One2OneColors { theme.colors }

    @State private var file: AssignmentQueue<PersistentIdentifier>

    init(actions: [ActionTask],
         allCollaborators: [Collaborator],
         onClose: @escaping () -> Void) {
        self.actions = actions
        self.allCollaborators = allCollaborators
        self.onClose = onClose
        _file = State(initialValue: AssignmentQueue(actions.map(\.persistentModelID)))
    }

    /// L'action courante, retrouvée par son identifiant. `nil` quand la file
    /// est close.
    private var courante: ActionTask? {
        guard let id = file.courant else { return nil }
        return actions.first { $0.persistentModelID == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            if let action = courante {
                corps(action)
            } else {
                fin
            }
        }
        .frame(width: 480)
        .background(c.base)
        .onChange(of: file.estClose) { _, close in
            if close { sauver() }
        }
        .onExitCommand { sortir() }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 10) {
            Text("Assigner").sectionLabel()
            if !file.estClose {
                Text("\(file.progression.numero) / \(file.progression.total)")
                    .font(.plexMono(10, .medium))
                    .monospacedDigit()
                    .foregroundStyle(c.ink4)
            }
            Spacer(minLength: 8)
            Button(action: sortir) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(c.ink3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fermer la file (Esc)")
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle().fill(c.hair).frame(height: 1)
        }
    }

    // MARK: - Corps

    @ViewBuilder
    private func corps(_ action: ActionTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(action.title)
                .font(.plexSans(13.5, .medium))
                .foregroundStyle(c.ink1)
                .fixedSize(horizontal: false, vertical: true)

            etape(.responsable) {
                HStack(spacing: 8) {
                    OwnerPickerMenu(label: "＋ assigner",
                                    selection: Binding(get: { action.collaborator },
                                                       set: { assigner($0, to: action) }),
                                    allCollaborators: allCollaborators,
                                    onSaved: { sauver() })
                        .fixedSize()
                    if let porteur = action.collaborator {
                        Chip(ActionCardEditing.prenom(porteur.name), ton: .ok)
                    }
                    Spacer(minLength: 0)
                }
            }

            etape(.echeance) {
                HStack(spacing: 6) {
                    ForEach(ActionCardEditing.raccourcisEcheance(depuis: Date()),
                            id: \.libelle) { raccourci in
                        Button {
                            action.dueDate = raccourci.date
                            avancer()
                        } label: {
                            Chip(raccourci.libelle, ton: .neutre)
                        }
                        .buttonStyle(.plain)
                    }
                    if action.dueDate != nil {
                        Chip(ActionCardEditing.libelleEcheance(action), ton: .action)
                    }
                    Spacer(minLength: 0)
                }
            }

            etape(.suivante) {
                Text("`⌘⏎` ou `Tab` passe à l'action suivante.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(c.ink4)
            }

            HStack(spacing: 8) {
                bouton("Passer", plein: false) { appliquer(.passer) }
                Spacer(minLength: 0)
                bouton(file.progression.numero == file.progression.total
                       ? "Terminer" : "Suivante",
                       plein: true) { appliquer(.commandReturn) }
            }
        }
        .padding(16)
        .overlay {
            // `⌘⏎` valide, `Tab` avance : la spec §2.6 demande une file
            // navigable au clavier. Les deux passent par la même transition
            // pure, donc par le même test.
            ZStack {
                Button("") { appliquer(.commandReturn) }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("") { appliquer(.tab) }
                    .keyboardShortcut(.tab, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    /// Une étape de la file. L'étape courante est mise en avant ; les autres
    /// restent lisibles — on doit voir ce qu'on vient de poser et ce qui
    /// arrive, sinon la file devient un tunnel.
    @ViewBuilder
    private func etape<Content: View>(_ laquelle: AssignmentQueue<PersistentIdentifier>.Etape,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        let active = file.etape == laquelle
        VStack(alignment: .leading, spacing: 6) {
            Text(AssignmentQueue<PersistentIdentifier>.libelle(laquelle)).sectionLabel()
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .fill(active ? c.cardActive : c.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .strokeBorder(active ? One2OneToken.action : c.hair, lineWidth: active ? 1.5 : 1)
        )
        .opacity(active ? 1 : 0.7)
    }

    private var fin: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.estSortie
                 ? "File fermée. Les actions non assignées restent dans le bandeau."
                 : "Tout est assigné.")
                .font(.plexSans(12.5))
                .foregroundStyle(c.ink2)
            HStack {
                Spacer(minLength: 0)
                bouton("Fermer", plein: true) { onClose() }
            }
        }
        .padding(16)
    }

    private func bouton(_ titre: String,
                        plein: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(12, .semibold))
                .foregroundStyle(plein ? One2OneToken.onFilledButton : c.ink2)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(plein ? One2OneToken.action : c.pill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gestes

    private func appliquer(_ evenement: AssignmentQueue<PersistentIdentifier>.Evenement) {
        file = file.apres(evenement)
    }

    private func avancer() {
        appliquer(.commandReturn)
    }

    private func sortir() {
        appliquer(.escape)
        sauver()
        onClose()
    }

    /// Poser un responsable **avance d'un cran** : c'est le premier des trois
    /// clics de la spec, pas un réglage à confirmer.
    private func assigner(_ porteur: Collaborator?, to action: ActionTask) {
        action.collaborator = porteur
        action.destinataire = porteur == nil ? .collaborateur : .collaborateur
        if porteur != nil, file.etape == .responsable { avancer() }
        sauver()
    }

    private func sauver() {
        try? context.save()
    }
}
