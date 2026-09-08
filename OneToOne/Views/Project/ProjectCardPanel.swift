import SwiftUI
import SwiftData

/// La fiche projet en panneau de 430 px, glissant depuis la droite
/// (spec §4.3, capture `3b-fiche-projet.png`).
///
/// Ce n'est **pas** un remplacement de `ProjectDetailView` : celle-ci reste
/// l'écran projet complet (portfolio, mails, pièces jointes, historique). Le
/// panneau est un point d'édition contextuel, ouvert depuis le fil d'Ariane
/// pendant une réunion, et il ne montre que ce qui se met à jour en séance.
///
/// L'édition passe par un `ProjectCardDraft` : rien n'est écrit dans
/// `Project` avant `Enregistrer` (critère d'acceptation n° 4 du chantier 3).
/// L'enregistrement est optimiste — il applique tout de suite et laisse cinq
/// secondes pour revenir en arrière via `UndoBanner`.
struct ProjectCardPanel: View {

    // MARK: - Géométrie et libellés (capture 3b)

    static let width: CGFloat = One2OneToken.projectPanelWidth

    static let headerLabel = "FICHE PROJET"
    static let statusLabel = "STATUT"
    static let budgetLabel = "BUDGET CONSOMMÉ"
    static let milestonesLabel = "JALONS"
    static let scopeLabel = "PÉRIMÈTRE & CONTEXTE"
    static let risksLabel = "RISQUES"
    static let contactsLabel = "INTERLOCUTEURS"
    static let newMilestonePlaceholder = "Nouveau jalon…"
    static let newMilestoneHint = "date · statut"
    static let footerNotice = "Visible par toute l'équipe projet · reprise automatiquement "
                            + "en préparation de la prochaine réunion"

    /// Les quatre gravités de `ProjectAlert`, dans l'ordre décroissant. Elles
    /// sont écrites en clair : ce sont les valeurs brutes persistées, lues par
    /// `MeetingKPIBuilder.level(fromSeverity:)`.
    static let severities = ["Critique", "Élevé", "Modéré", "Faible"]

    // MARK: - Teintes d'état

    /// Point coloré du statut (spec §4.3 : « menu à 3 valeurs avec point
    /// coloré »).
    static func color(for status: ProjectCardStatus) -> Color {
        switch status {
        case .ok:    return One2OneToken.ok
        case .watch: return One2OneToken.warn
        case .risk:  return One2OneToken.report
        }
    }

    /// Point d'un jalon. Un jalon prévu est un **cercle vide** sur la capture :
    /// la teinte ne sert alors qu'au contour.
    static func color(for state: MilestoneState) -> Color {
        switch state {
        case .done:       return One2OneToken.ok
        case .late:       return One2OneToken.warn
        case .inProgress: return One2OneToken.action
        case .planned:    return One2OneToken.ink4
        }
    }

    /// Point d'un risque. Cette fiche avait la bonne palette avant les autres
    /// écrans ; elle est désormais la table unique
    /// `MeetingKPI.Level.teinte` (`Views/DesignSystem/RiskLevelTint.swift`),
    /// que le bandeau et le rail lisent aussi.
    static func color(for level: MeetingKPI.Level) -> Color { level.teinte }

    static func color(for tone: BudgetTone) -> Color {
        switch tone {
        case .ok:     return One2OneToken.ok
        case .warn:   return One2OneToken.warn
        case .report: return One2OneToken.report
        }
    }

    // MARK: - Entrées

    let project: Project
    let meeting: Meeting
    /// Toutes les réunions connues : sert à compter celles du projet.
    let meetings: [Meeting]
    let settings: AppSettings
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var context

    /// Bascule `Édition` de l'en-tête. Hors édition, tout est en lecture.
    @State private var isEditing = false
    /// Le brouillon en cours de saisie.
    @State private var draft = ProjectCardDraft()
    /// L'état du brouillon à l'ouverture de l'édition : sert à savoir s'il y a
    /// quelque chose à enregistrer.
    @State private var baseline = ProjectCardDraft()
    /// L'instantané d'avant enregistrement, restauré par `Annuler`.
    @State private var undoSnapshot: ProjectCardDraft?
    @State private var suggestions: [ProjectCardUpdate] = []
    @State private var showSuggestions = false
    @State private var didAskSuggestions = false
    /// Saisie de la ligne d'ajout de jalon.
    @State private var newMilestone = ""
    /// Saisie de la chip `＋` des tags.
    @State private var newTag = ""
    @State private var isAddingTag = false
    /// Confirmation de fermeture quand le brouillon porte des modifications.
    @State private var showDiscardConfirm = false

    private var card: ProjectCardState {
        ProjectCardBuilder.build(project: project, meetings: meetings)
    }

    private var hasChanges: Bool { draft != baseline }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(One2OneToken.hair)
            ScrollView {
                VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                    statusAndBudget
                    milestonesSection
                    scopeSection
                    risksAndContacts
                    assistantNotice
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            if let undoSnapshot {
                UndoBanner(onUndo: { undo(to: undoSnapshot) },
                           onExpire: { self.undoSnapshot = nil })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            if isEditing {
                Divider().overlay(One2OneToken.hair)
                footer
            }
        }
        .frame(width: Self.width)
        .background(One2OneToken.surface)
        .shadow(color: One2OneToken.panelShadow,
                radius: One2OneToken.panelShadowRadius,
                x: One2OneToken.panelShadowOffsetX,
                y: 0)
        // `Esc` ferme le panneau (spec §4.3). `onExitCommand` et non un
        // raccourci clavier : la touche doit fonctionner même quand le focus
        // est dans un champ du panneau.
        .onExitCommand { requestClose() }
        .onAppear { loadDraft() }
        .onChange(of: project.persistentModelID) { _, _ in loadDraft() }
        .sheet(isPresented: $showSuggestions) {
            ProjectCardSuggestionsSheet(updates: suggestions,
                                        draft: $draft,
                                        onClose: { showSuggestions = false },
                                        meeting: meeting)
        }
        .confirmationDialog("Abandonner les modifications ?",
                            isPresented: $showDiscardConfirm) {
            Button("Abandonner", role: .destructive) { close() }
            Button("Continuer l'édition", role: .cancel) {}
        } message: {
            Text("La fiche n'a pas été enregistrée : les modifications seront perdues.")
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(Self.headerLabel).sectionLabel()
                Spacer(minLength: 8)
                editionToggle
                Button(action: requestClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(One2OneToken.ink3)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Fermer la fiche (Esc)")
            }
            Text(project.name.isEmpty ? "Projet sans nom" : project.name)
                .font(.plexSans(14, .semibold))
                .foregroundStyle(One2OneToken.ink1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            MonoMeta(metaLine)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// « P25_110 · 9 réunions · dernière mise à jour aujourd'hui par vous ».
    private var metaLine: String {
        let etat = card
        var morceaux: [String] = []
        if !etat.reference.isEmpty { morceaux.append(etat.reference) }
        morceaux.append(etat.meetingCount == 1 ? "1 réunion" : "\(etat.meetingCount) réunions")
        morceaux.append(etat.lastUpdateText)
        return morceaux.joined(separator: " · ")
    }

    private var editionToggle: some View {
        Button {
            if isEditing {
                // Quitter l'édition sans enregistrer revient à annuler : le
                // brouillon repart du modèle.
                if hasChanges { showDiscardConfirm = true } else { isEditing = false }
            } else {
                loadDraft()
                isEditing = true
            }
        } label: {
            Text("Édition")
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(isEditing ? One2OneToken.actionInk : One2OneToken.ink3)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(isEditing ? One2OneToken.actionBg : One2OneToken.surfaceAlt)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isEditing ? "Quitter l'édition" : "Modifier la fiche")
    }

    // MARK: - Statut et budget

    private var statusAndBudget: some View {
        HStack(alignment: .top, spacing: 10) {
            RefonteCard(padding: One2OneToken.cardPaddingMin) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(Self.statusLabel).sectionLabel()
                    statusControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            RefonteCard(padding: One2OneToken.cardPaddingMin) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(Self.budgetLabel).sectionLabel()
                    budgetControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var statusControl: some View {
        if isEditing {
            Menu {
                ForEach(ProjectCardStatus.allCases) { statut in
                    Button {
                        draft.status = statut
                    } label: {
                        Label(statut.label, systemImage: draft.status == statut
                              ? "largecircle.fill.circle" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.color(for: draft.status))
                        .frame(width: 7, height: 7)
                    Text(draft.status.label)
                        .font(.plexSans(12, .medium))
                        .foregroundStyle(One2OneToken.ink1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(One2OneToken.ink4)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(card.statusIsQualified
                          ? Self.color(for: card.status)
                          : One2OneToken.ink4)
                    .frame(width: 7, height: 7)
                Text(card.statusLabel)
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink1)
            }
        }
    }

    @ViewBuilder
    private var budgetControl: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    amountField(placeholder: "consommé", value: $draft.budgetSpent)
                    Text("/")
                        .font(.plexSans(12))
                        .foregroundStyle(One2OneToken.ink4)
                    amountField(placeholder: "total", value: $draft.budgetTotal)
                }
                if let barre = draftBudget {
                    ProgressBar(valeur: barre.ratio, teinte: Self.color(for: barre.tone))
                }
            }
        } else if let budget = card.budget {
            VStack(alignment: .leading, spacing: 6) {
                Text(budget.text)
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                ProgressBar(valeur: budget.ratio, teinte: Self.color(for: budget.tone))
            }
        } else {
            Text("Budget non renseigné")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
        }
    }

    /// La barre pendant l'édition : recalculée depuis le brouillon, pour que la
    /// teinte suive la saisie plutôt que la valeur enregistrée.
    private var draftBudget: (ratio: Double, tone: BudgetTone)? {
        guard let total = draft.budgetTotal, total > 0 else { return nil }
        let brut = (draft.budgetSpent ?? 0) / total
        return (min(max(brut, 0), 1), ProjectCardBuilder.tone(ratio: brut))
    }

    /// Champ de montant. Vide = valeur inconnue, et non zéro : un budget non
    /// renseigné n'est pas un budget à zéro.
    private func amountField(placeholder: String, value: Binding<Double?>) -> some View {
        TextField(placeholder, text: Binding(
            get: { value.wrappedValue.map { String(Int($0.rounded())) } ?? "" },
            set: { saisie in
                let propre = saisie.filter { $0.isNumber }
                value.wrappedValue = propre.isEmpty ? nil : Double(propre)
            }
        ))
        .textFieldStyle(.plain)
        .font(.plexSans(12, .medium))
        .foregroundStyle(One2OneToken.ink1)
        .frame(maxWidth: 74)
    }

    // MARK: - Jalons

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(Self.milestonesLabel).sectionLabel()
                Spacer(minLength: 8)
                if isEditing {
                    inlineAction("＋ ajouter") { addMilestone(label: newMilestonePlaceholderValue) }
                }
            }
            if isEditing {
                ForEach($draft.milestones) { $jalon in
                    milestoneEditRow($jalon)
                }
                newMilestoneRow
            } else if card.milestones.isEmpty {
                MeetingEmptyInvite(
                    titre: "Aucun jalon",
                    invite: "Passez en Édition pour poser les échéances qui comptent."
                )
            } else {
                ForEach(card.milestones) { jalon in
                    HStack(spacing: 9) {
                        milestoneDot(jalon.state)
                        Text(jalon.label)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink2)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(jalon.trailingText)
                            .font(.plexMono(10, .medium))
                            .foregroundStyle(jalon.isBlocked
                                             ? One2OneToken.report
                                             : One2OneToken.ink4)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    /// Le libellé tapé dans la ligne d'ajout, ou un libellé par défaut quand
    /// l'utilisateur clique `＋ ajouter` sans avoir rien tapé.
    private var newMilestonePlaceholderValue: String {
        newMilestone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Nouveau jalon"
            : newMilestone
    }

    private func milestoneDot(_ state: MilestoneState) -> some View {
        Group {
            if state == .planned {
                // Cercle vide, comme sur la capture pour « Bascule Jenkins ».
                Circle()
                    .strokeBorder(Self.color(for: state), lineWidth: 1.2)
            } else {
                Circle().fill(Self.color(for: state))
            }
        }
        .frame(width: 8, height: 8)
    }

    private func milestoneEditRow(_ jalon: Binding<ProjectCardDraft.MilestoneDraft>) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(MilestoneState.allCases) { etat in
                    Button(etat.label) { jalon.wrappedValue.state = etat }
                }
            } label: {
                milestoneDot(jalon.wrappedValue.state)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 14)
            .help("Changer l'état du jalon")

            TextField("Libellé du jalon", text: jalon.label)
                .textFieldStyle(.plain)
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)

            milestoneDateControl(jalon)

            Button {
                draft.milestones.removeAll { $0.id == jalon.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(One2OneToken.ink4)
            }
            .buttonStyle(.plain)
            .help("Retirer ce jalon")

            reorderButtons(for: jalon.wrappedValue.id)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func milestoneDateControl(_ jalon: Binding<ProjectCardDraft.MilestoneDraft>) -> some View {
        if jalon.wrappedValue.state == .late {
            Text("bloqué")
                .font(.plexMono(10, .medium))
                .foregroundStyle(One2OneToken.report)
        } else if let echeance = jalon.wrappedValue.dueAt {
            HStack(spacing: 3) {
                DatePicker("", selection: Binding(get: { echeance },
                                                  set: { jalon.wrappedValue.dueAt = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(.plexMono(10, .medium))
                    .frame(width: 96)
                Button {
                    jalon.wrappedValue.dueAt = nil
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(One2OneToken.ink4)
                }
                .buttonStyle(.plain)
                .help("Retirer la date")
            }
        } else {
            Button("date") { jalon.wrappedValue.dueAt = Date() }
                .buttonStyle(.plain)
                .font(.plexMono(10, .medium))
                .foregroundStyle(One2OneToken.action)
        }
    }

    /// Réordonner : deux flèches plutôt qu'un glisser-déposer. Le panneau n'est
    /// pas une `List`, et un `onMove` maison sur une `VStack` réclame un suivi
    /// de geste dont le comportement dériverait du reste de l'application.
    private func reorderButtons(for id: UUID) -> some View {
        let index = draft.milestones.firstIndex { $0.id == id }
        return HStack(spacing: 1) {
            Button {
                if let index, index > 0 { draft.milestones.swapAt(index, index - 1) }
            } label: {
                Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled((index ?? 0) == 0)
            Button {
                if let index, index < draft.milestones.count - 1 {
                    draft.milestones.swapAt(index, index + 1)
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled((index ?? 0) >= draft.milestones.count - 1)
        }
        .foregroundStyle(One2OneToken.ink4)
        .help("Déplacer le jalon")
    }

    /// La ligne d'ajout en pointillés de la capture : `Nouveau jalon…` à
    /// gauche, `date · statut` à droite.
    private var newMilestoneRow: some View {
        HStack(spacing: 8) {
            TextField(Self.newMilestonePlaceholder, text: $newMilestone)
                .textFieldStyle(.plain)
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
                .onSubmit { addMilestone(label: newMilestonePlaceholderValue) }
            Spacer(minLength: 8)
            Text(Self.newMilestoneHint)
                .font(.plexMono(10, .medium))
                .foregroundStyle(One2OneToken.ink4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(One2OneToken.strongBorder)
        )
    }

    private func addMilestone(label: String) {
        draft.milestones.append(.init(id: UUID(),
                                      label: label,
                                      dueAt: nil,
                                      state: .planned,
                                      order: draft.milestones.count))
        newMilestone = ""
    }

    // MARK: - Périmètre et contexte

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(Self.scopeLabel).sectionLabel()
                Spacer(minLength: 8)
                if !isEditing {
                    inlineAction("éditer") { loadDraft(); isEditing = true }
                }
            }
            if isEditing {
                TextEditor(text: $draft.scopeText)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 76)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                            .fill(One2OneToken.surfaceAlt)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                            .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
                    )
            } else if card.scopeText.isEmpty {
                MeetingEmptyInvite(
                    titre: "Périmètre non écrit",
                    invite: "Une phrase suffit : ce que le projet couvre, et qui le porte."
                )
            } else {
                Text(card.scopeText)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                            .fill(One2OneToken.surfaceAlt)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                            .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
                    )
            }
            tagsRow
        }
    }

    private var tagsRow: some View {
        // `WrappingHStack` n'existe pas dans le projet : un `FlowLayout` maison
        // serait une dépendance de plus. Les tags d'une fiche tiennent sur une
        // ou deux lignes, et `LazyVGrid` adaptatif suffit.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78, maximum: 200), spacing: 6)],
                  alignment: .leading,
                  spacing: 6) {
            ForEach(isEditing ? draft.tags : card.tags, id: \.self) { tag in
                if isEditing {
                    Button {
                        draft.tags.removeAll { $0 == tag }
                    } label: {
                        HStack(spacing: 3) {
                            Text(tag)
                            Image(systemName: "xmark").font(.system(size: 7, weight: .semibold))
                        }
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(One2OneToken.ink3)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(One2OneToken.surfaceAlt)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Retirer le thème")
                } else {
                    // `fixedSize` : sans lui, une colonne adaptative trop
                    // étroite coupe « PostgreSQL » en « PostgreS / QL » —
                    // constaté à la recette du lot 9. Une chip ne se replie
                    // jamais : elle déborde ou elle passe à la ligne suivante.
                    Chip(tag).fixedSize()
                }
            }
            if isEditing { addTagChip }
        }
    }

    /// La chip `＋` de la capture : un cercle pointillé qui devient un champ.
    @ViewBuilder
    private var addTagChip: some View {
        if isAddingTag {
            TextField("thème", text: $newTag)
                .textFieldStyle(.plain)
                .font(.plexSans(10.5, .medium))
                .frame(width: 72)
                .onSubmit { commitTag() }
        } else {
            Button {
                isAddingTag = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(One2OneToken.ink4)
                    .frame(width: 22, height: 20)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(One2OneToken.strongBorder)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ajouter un thème")
        }
    }

    private func commitTag() {
        let propre = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !propre.isEmpty, !draft.tags.contains(propre) { draft.tags.append(propre) }
        newTag = ""
        isAddingTag = false
    }

    // MARK: - Risques et interlocuteurs

    private var risksAndContacts: some View {
        HStack(alignment: .top, spacing: 12) {
            risksColumn.frame(maxWidth: .infinity, alignment: .leading)
            contactsColumn.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var risksColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(Self.risksLabel).sectionLabel()
                let compte = isEditing ? draft.risks.count : card.risks.count
                // « RISQUES · 5 » : le point médian est celui de la capture,
                // comme sur les cartes du bandeau d'indicateurs.
                MonoMeta("· \(compte)", emphase: compte > 0)
                Spacer(minLength: 0)
            }
            if isEditing {
                ForEach($draft.risks) { $risque in
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(Self.severities, id: \.self) { gravite in
                                Button(gravite) { $risque.wrappedValue.severity = gravite }
                            }
                        } label: {
                            Circle()
                                .fill(Self.color(for: MeetingKPIBuilder.level(fromSeverity: risque.severity)))
                                .frame(width: 8, height: 8)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 14)
                        .help("Changer la gravité")
                        TextField("Libellé du risque", text: $risque.title)
                            .textFieldStyle(.plain)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink2)
                        Button {
                            draft.risks.removeAll { $0.id == risque.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(One2OneToken.ink4)
                        }
                        .buttonStyle(.plain)
                        .help("Retirer ce risque")
                    }
                }
                inlineAction("＋ Ajouter un risque") {
                    draft.risks.append(.init(id: UUID(), title: "", severity: "Modéré", existing: nil))
                }
            } else if card.risks.isEmpty {
                MeetingEmptyInvite(titre: "Aucun risque ouvert",
                                   invite: "Ce qui menace le projet se note ici.")
            } else {
                ForEach(card.risks) { risque in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.color(for: risque.level))
                            .frame(width: 8, height: 8)
                        Text(risque.title)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink2)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var contactsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.contactsLabel).sectionLabel()
                Spacer(minLength: 0)
            }
            if isEditing {
                ForEach($draft.contacts) { $contact in
                    HStack(spacing: 6) {
                        TextField("Nom", text: $contact.name)
                            .textFieldStyle(.plain)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink2)
                        TextField("rôle", text: $contact.role)
                            .textFieldStyle(.plain)
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink3)
                        Button {
                            draft.contacts.removeAll { $0.id == contact.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(One2OneToken.ink4)
                        }
                        .buttonStyle(.plain)
                        .help("Retirer cet interlocuteur")
                    }
                }
                inlineAction("＋ Ajouter") {
                    draft.contacts.append(.init(id: UUID(), name: "", role: "",
                                                order: draft.contacts.count))
                }
            } else if card.contacts.isEmpty {
                MeetingEmptyInvite(titre: "Aucun interlocuteur",
                                   invite: "Sponsors, métiers et prestataires du dossier.")
            } else {
                ForEach(card.contacts) { contact in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·")
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink4)
                        Text(contact.text)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Encart de l'assistant

    /// L'encart n'existe **que** s'il y a quelque chose à proposer : sans
    /// endpoint IA configuré, sans matière, ou sur échec, il n'apparaît pas et
    /// aucune erreur n'est affichée (spec §4.3).
    @ViewBuilder
    private var assistantNotice: some View {
        if !suggestions.isEmpty {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(One2OneToken.action)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.actionBg)
                    )
                Text(ProjectCardSuggestions.summary(suggestions))
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Revoir") {
                    loadDraft()
                    isEditing = true
                    showSuggestions = true
                }
                .buttonStyle(.plain)
                .font(.plexSans(11, .medium))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.action)
                )
                .help("Voir les propositions champ par champ")
            }
            .padding(One2OneToken.cardPaddingMax)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(One2OneToken.actionBg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Pied

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                Text(Self.footerNotice)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Annuler") { discardDraft() }
                    .buttonStyle(.plain)
                    .font(.plexSans(11, .medium))
                    .foregroundStyle(One2OneToken.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                    )
                Button("Enregistrer") { save() }
                    .buttonStyle(.plain)
                    .font(.plexSans(11, .medium))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(One2OneToken.action)
                    )
                    .disabled(!hasChanges)
                    .opacity(hasChanges ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func inlineAction(_ titre: String, _ action: @escaping () -> Void) -> some View {
        Button(titre, action: action)
            .buttonStyle(.plain)
            .font(.plexSans(11, .medium))
            .foregroundStyle(One2OneToken.action)
    }

    // MARK: - Cycle du brouillon

    private func loadDraft() {
        draft = ProjectCardDraft.snapshot(of: project)
        baseline = draft
        askSuggestionsIfNeeded()
    }

    /// Une seule demande par ouverture de panneau : les propositions ne se
    /// régénèrent pas à chaque frappe.
    private func askSuggestionsIfNeeded() {
        guard !didAskSuggestions,
              ProjectCardSuggestions.isEndpointConfigured(settings) else { return }
        didAskSuggestions = true
        let carte = card
        Task { @MainActor in
            suggestions = await ProjectCardSuggestions.suggest(meeting: meeting,
                                                               card: carte,
                                                               settings: settings)
        }
    }

    /// `Annuler` du pied : le brouillon repart du modèle, rien n'a été écrit.
    private func discardDraft() {
        draft = ProjectCardDraft.snapshot(of: project)
        baseline = draft
        isEditing = false
    }

    /// `Enregistrer` : applique tout de suite (enregistrement optimiste) et
    /// garde l'instantané d'avant pour la bannière.
    private func save() {
        let avant = ProjectCardDraft.snapshot(of: project)
        draft.apply(to: project, in: context)
        baseline = ProjectCardDraft.snapshot(of: project)
        draft = baseline
        isEditing = false
        undoSnapshot = avant
    }

    /// `Annuler` de la bannière : réapplique l'instantané d'avant
    /// enregistrement.
    private func undo(to snapshot: ProjectCardDraft) {
        snapshot.apply(to: project, in: context)
        draft = ProjectCardDraft.snapshot(of: project)
        baseline = draft
        undoSnapshot = nil
    }

    private func requestClose() {
        if isEditing, hasChanges {
            showDiscardConfirm = true
        } else {
            close()
        }
    }

    private func close() {
        isEditing = false
        isPresented = false
    }
}
