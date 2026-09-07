import SwiftUI
import SwiftData

/// La création d'action du composeur, hors de la vue.
///
/// Extraite pour une raison précise : le critère de la spec §2.5 est que
/// « `⌘⏎` crée et vide le champ **sans perdre le focus** ». Un service qui
/// n'a aucun accès au focus ne peut pas le prendre ; il ne reste plus à la vue
/// qu'à ne jamais remettre son `@FocusState` à `false` — ce que garde
/// `ActionsRailNoModalTests`.
@MainActor
enum ActionComposerService {

    /// Crée l'action du brouillon et la place **en tête** de son groupe.
    ///
    /// - Returns: l'action créée, ou `nil` si rien n'a été saisi ni proposé.
    ///
    /// Le titre saisi l'emporte sur celui d'un `pendingActionDraft` en
    /// attente, mais la chaîne de citation du brouillon survit : reformuler une
    /// phrase ne coupe pas le lien vers l'instant où elle a été dite.
    ///
    /// Après création, seuls le titre et l'urgence retombent. Le destinataire,
    /// l'échéance et la charge restent armés — ce sont les défauts du composeur
    /// (« Moi · Demain · 30min » de la capture), et on saisit rarement une
    /// action isolée. L'urgence, elle, retombe : un `!` oublié rendrait urgente
    /// toute la série suivante.
    @discardableResult
    static func creer(from screen: MeetingScreenModel,
                      meeting: Meeting,
                      in context: ModelContext) -> ActionTask? {
        let brouillon = screen.pendingActionDraft
        let saisi = screen.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let propose = (brouillon?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let titre = saisi.isEmpty ? propose : saisi
        guard !titre.isEmpty else {
            // Rien à créer : le brouillon éventuel reste en attente, il n'a pas
            // été consommé.
            return nil
        }

        let action = ActionTask(
            title: titre,
            dueDate: screen.showNewTaskDueDate ? (screen.newTaskDueDate ?? Date()) : nil
        )
        action.meeting = meeting
        action.project = meeting.project
        action.sortOrder = plancherSortOrder(meeting.tasks)
        action.effortMinutes = screen.newTaskEffortMinutes
        action.isImportant = screen.newTaskImportant
        action.priority = screen.newTaskUrgent ? .urgent : .normal
        action.sourceRef = brouillon?.sourceRef

        // Le responsable : celui du brouillon d'abord (il vient d'une
        // suggestion contextuelle), sinon celui du composeur.
        if let suggere = brouillon?.suggestedOwner {
            action.collaborator = suggere
            action.destinataire = .collaborateur
        } else {
            action.destinataire = screen.newTaskAudience
            action.collaborator = screen.newTaskAudience == .collaborateur
                ? screen.selectedCollaborator
                : nil
        }

        context.insert(action)
        try? context.save()

        screen.newTaskTitle = ""
        screen.newTaskUrgent = false
        screen.newTaskImportant = false
        screen.pendingActionDraft = nil
        return action
    }

    /// L'ordre manuel à donner à une action neuve pour qu'elle passe devant
    /// toutes les autres : un cran sous le minimum existant.
    ///
    /// C'est ce qui tient la promesse « l'action apparaît en tête de son
    /// groupe » (spec §2.4 et §2.5) sans lui inventer une échéance —
    /// `ActionsRailGrouping.triees` trie sur `sortOrder` en premier.
    static func plancherSortOrder(_ tasks: [ActionTask]) -> Int {
        guard let minimum = tasks.map(\.sortOrder).min() else { return 0 }
        return minimum - 1
    }
}

/// Le composeur du pied de rail (spec §2.5, capture `1a-cockpit.png`) :
/// « champ + pilules par défaut (`Moi`, `Demain`, `!`, durée). `⌘⏎` crée et
/// vide le champ sans perdre le focus. »
///
/// Toujours visible, y compris sur les onglets Risques et Historique : c'est la
/// seule surface de l'écran qui promette qu'une intention dite en séance ne se
/// perd pas, et la faire disparaître à chaque changement d'onglet en ferait
/// une surface conditionnelle.
struct ActionComposer: View {

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    /// Appelé après une création réussie, pour animer l'insertion en tête.
    let onCreated: (ActionTask) -> Void

    @Environment(\.modelContext) private var context
    /// Le focus du champ. **Jamais** remis à `false` par le code : c'est tout
    /// le sens du critère « sans perdre le focus ».
    @FocusState private var champActif: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            champ
            pilules
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(One2OneToken.bgCanvas)
        .overlay(alignment: .top) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    // MARK: - Champ

    private var champ: some View {
        HStack(spacing: 6) {
            TextField("Nouvelle action…", text: Binding(get: { screen.newTaskTitle },
                                                        set: { screen.newTaskTitle = $0 }))
                .textFieldStyle(.plain)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink1)
                .focused($champActif)
                .onSubmit(creer)
            Text("⌘⏎")
                .font(.plexMono(9.5, .medium))
                .foregroundStyle(One2OneToken.ink4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        // `⌘⏎` de la spec §1.4 : « Valider le composeur ». La modification est
        // vérifiée à la main plutôt que par un `keyboardShortcut`, qui serait
        // actif même le champ non focalisé.
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            creer()
            return .handled
        }
    }

    /// Crée l'action **sans toucher au focus** : `champActif` n'apparaît pas
    /// ici, et c'est volontaire.
    private func creer() {
        guard let creee = ActionComposerService.creer(from: screen,
                                                     meeting: meeting,
                                                     in: context) else { return }
        onCreated(creee)
    }

    // MARK: - Pilules

    private var pilules: some View {
        HStack(spacing: 5) {
            bascule(libelle: screen.newTaskAudience == .collaborateur
                        ? (screen.selectedCollaborator.map { ActionCardEditing.prenom($0.name) } ?? "À assigner")
                        : screen.newTaskAudience.label,
                    active: screen.newTaskAudience == .moi,
                    aide: "Destinataire") {
                // Bascule entre « pour moi » et « à assigner » : les deux
                // seuls choix qui vaillent dans un composeur de 330 px. Le
                // reste passe par la carte, où le sélecteur est complet.
                screen.newTaskAudience = screen.newTaskAudience == .moi ? .collaborateur : .moi
                if screen.newTaskAudience == .moi { screen.selectedCollaborator = nil }
            }
            bascule(libelle: libelleEcheance,
                    active: screen.showNewTaskDueDate,
                    aide: "Échéance") {
                screen.showNewTaskDueDate.toggle()
                screen.newTaskDueDate = screen.showNewTaskDueDate
                    ? Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    : nil
            }
            bascule(libelle: "!", active: screen.newTaskUrgent, aide: "Urgente") {
                screen.newTaskUrgent.toggle()
            }
            bascule(libelle: ActionCardEditing.chargeLabel(screen.newTaskEffortMinutes ?? 0).isEmpty
                        ? "＋ charge"
                        : ActionCardEditing.chargeLabel(screen.newTaskEffortMinutes ?? 0),
                    active: screen.newTaskEffortMinutes != nil,
                    aide: "Charge estimée") {
                screen.newTaskEffortMinutes = prochaineCharge(screen.newTaskEffortMinutes)
            }
            Spacer(minLength: 0)
        }
    }

    private var libelleEcheance: String {
        guard screen.showNewTaskDueDate else { return "Demain" }
        guard let date = screen.newTaskDueDate else { return "Demain" }
        return ActionsRailGrouping.dateOrdinale(date)
    }

    /// Fait tourner la charge sur les valeurs proposées, puis revient à
    /// « aucune ». Un menu pour quatre valeurs coûterait un clic de plus.
    private func prochaineCharge(_ courante: Int?) -> Int? {
        let valeurs = ActionCardEditing.chargesProposees
        guard let courante, let index = valeurs.firstIndex(of: courante) else { return valeurs.first }
        return index + 1 < valeurs.count ? valeurs[index + 1] : nil
    }

    private func bascule(libelle: String,
                         active: Bool,
                         aide: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(libelle)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(active ? One2OneToken.actionInk : One2OneToken.ink4)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(active ? One2OneToken.actionBg : One2OneToken.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(active ? One2OneToken.action.opacity(0.25) : One2OneToken.cardBorder,
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(aide)
    }
}
