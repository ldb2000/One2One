import SwiftUI
import SwiftData

/// Le tableau d'actions dense du poste de pilotage (spec §2.7 : « colonnes
/// `20px | 1fr | 108 | 92 | 62 | 76 | 30` : état, intitulé, responsable,
/// échéance, charge, source (`mm:ss ↗`), menu. Édition inline sur chaque
/// cellule ; `↑↓` navigue, `Espace` coche, `⌥↑↓` réordonne. Pied : composeur +
/// `n autres · tout afficher` »).
///
/// C'est la **même** liste d'actions que le rail de 330 px, dans une autre
/// densité : les règles de tri (`ActionsRailGrouping.triees`), de libellé
/// (`ActionCardEditing`) et de suggestion (`OwnerSuggestion`) sont celles du
/// lot 3, réemployées sans copie. Ce qui change, c'est la disposition — et
/// c'est tout ce que ce fichier ajoute.
///
/// Aucune modale : un clic sur une cellule déplie son sélecteur **sous la
/// ligne** (critère d'acceptation n° 3 du chantier 1, gardé par
/// `ReviewCardsInviteTests`).
struct ActionsTable: View {

    /// Les largeurs fixes de la spec §2.7. L'intitulé est la colonne fluide
    /// (`1fr`) et n'en a donc pas.
    ///
    /// Extraites en constantes pour être vérifiables : une colonne rognée de
    /// 20 px ne se voit dans aucun test de rendu, et c'est exactement le genre
    /// d'écart qui s'installe au fil des retouches.
    static let colonnes: (etat: CGFloat, responsable: CGFloat, echeance: CGFloat,
                          charge: CGFloat, source: CGFloat, menu: CGFloat) =
        (etat: 20, responsable: 108, echeance: 92, charge: 62, source: 76, menu: 30)

    /// Le tableau montre cinq lignes puis annonce le reste (capture 1c :
    /// `7 autres · tout afficher` sous cinq lignes, pour douze actions).
    static let lignesRepliees = 5

    /// Les trois vues du mode Relire. `liste` s'y nomme **Tableau** : dans la
    /// colonne principale, ce n'est plus une liste de cartes.
    static func libelleVue(_ vue: ActionsViewMode) -> String {
        vue == .liste ? "Tableau" : vue.label
    }

    /// L'ordre du sélecteur, celui de la capture : `Tableau · Eisenhower ·
    /// Calendrier`.
    static let vues: [ActionsViewMode] = [.liste, .eisenhower, .calendar]

    /// Le libellé de la colonne `ÉCHÉANCE`.
    ///
    /// Quatre états dans un seul emplacement de 92 px, dans cet ordre : une
    /// date réelle d'abord, puis le nombre de reports (une dette datée se lit
    /// mieux par son compteur : `Reporté ×2` dit ce qu'une date ne dit pas),
    /// puis l'urgence sans date, puis l'invite. La capture montre les quatre.
    @MainActor
    static func libelleEcheance(_ task: ActionTask,
                                reference: Date = Date(),
                                calendar: Calendar = .current) -> (texte: String, etat: InvitePill.Etat) {
        if task.dueDate != nil {
            return (ActionCardEditing.libelleEcheance(task, reference: reference, calendar: calendar),
                    .neutre)
        }
        if task.deferralCount > 1 {
            return ("Reporté ×\(task.deferralCount)", .neutre)
        }
        if task.isUrgent {
            return ("Urgent", .neutre)
        }
        return ("＋ date", .invite)
    }

    /// Le libellé de la colonne `SOURCE` : `mm:ss ↗` pour une phrase, une note
    /// ou une capture ; à défaut la **date de la réunion d'origine** pour une
    /// action reportée (capture 1c : `1 sept.`). `nil` quand il n'y a nulle
    /// part où aller.
    @MainActor
    static func libelleSource(_ task: ActionTask, calendar: Calendar = .current) -> String? {
        if let source = ActionCardEditing.libelleSource(task) { return source }
        guard let origine = task.carriedFromMeeting else { return nil }
        return ActionsRailGrouping.dateOrdinale(origine.date, calendar: calendar)
    }

    // MARK: - Entrées

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let allCollaborators: [Collaborator]
    /// Replace la tête de lecture sur la source d'une action.
    let onSeek: ((Double) -> Void)?
    let onToggle: (ActionTask) -> Void
    let onSave: () -> Void

    @Environment(\.modelContext) private var context

    /// La cellule dépliée, `nil` quand rien n'est en édition. Une seule à la
    /// fois : deux sélecteurs ouverts dans le même tableau ne laisseraient plus
    /// lire les lignes.
    @State private var cellule: Cellule?
    /// L'intitulé en cours d'édition (double-clic) et son brouillon.
    @State private var titreEnEdition: PersistentIdentifier?
    @State private var brouillonTitre = ""

    private struct Cellule: Equatable {
        var ligne: PersistentIdentifier
        var champ: ActionCardEditing.Champ
    }

    /// Les actions ouvertes de la réunion, dans l'ordre du rail. Les closes et
    /// les abandonnées quittent le tableau comme elles quittent l'onglet
    /// Actions : elles vivent dans l'Historique.
    private var toutes: [ActionTask] {
        ActionsRailGrouping.triees(meeting.tasks.filter { $0.status == .open })
    }

    private var visible: (visibles: [ActionTask], restantes: Int) {
        ActionsTableCommands.repli(toutes,
                                   limite: Self.lignesRepliees,
                                   tout: screen.review.toutAfficher)
    }

    private var sansResponsable: Int {
        toutes.filter { !ActionsRailGrouping.aUnPorteur($0) }.count
    }

    /// Les actions du projet, pour la règle du préfixe de `OwnerSuggestion`.
    private var actionsDuProjet: [ActionTask] {
        meeting.project?.tasks ?? meeting.tasks
    }

    var body: some View {
        ReviewCard {
            entete
            switch screen.review.vue {
            case .eisenhower:
                EisenhowerBoard(tasks: toutes, onToggle: onToggle, compact: true)
                    .padding(.top, 4)
            case .calendar:
                CalendarBoard(tasks: toutes, onToggle: onToggle, compact: true)
                    .padding(.top, 4)
            default:
                tableau
            }
            pied
        }
        .animation(.easeOut(duration: 0.15), value: meeting.tasks.count)
    }

    // MARK: - En-tête de carte

    private var entete: some View {
        HStack(spacing: 8) {
            Text("Actions")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            if sansResponsable > 0 {
                Text("\(sansResponsable) sans responsable")
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.reportInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(One2OneToken.reportBg))
            }
            Spacer(minLength: 8)
            SegmentedMode(selection: Binding(get: { screen.review.vue },
                                             set: { screen.review.vue = $0 }),
                          options: Self.vues,
                          libelle: Self.libelleVue)
            boutonAjouter
        }
    }

    /// `＋ Action` : crée la ligne saisie dans le composeur si le champ porte
    /// déjà un texte — c'est le même chemin que `⌘⏎` — et sinon amène le
    /// composeur sous les yeux en dépliant le tableau.
    ///
    /// Il ne **prend pas** le clavier : `ActionComposer` (lot 3) possède son
    /// `@FocusState` et n'expose aucun jeton, et le rail n'est pas modifiable
    /// depuis ce lot. Le curseur se pose d'un clic dans le champ, à un pixel
    /// du bouton.
    private var boutonAjouter: some View {
        Button {
            if screen.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                screen.review.toutAfficher = true
                screen.review.section = .actions
            } else {
                ActionComposerService.creer(from: screen, meeting: meeting, in: context)
            }
        } label: {
            Text("＋ Action")
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton)
                        .fill(One2OneToken.action)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Créer une action — ou taper directement dans le champ ci-dessous (⌘⏎)")
    }

    // MARK: - Tableau

    @ViewBuilder
    private var tableau: some View {
        if toutes.isEmpty {
            MeetingEmptyInvite(
                titre: "Aucune action ouverte",
                invite: "Tapez l'action dans le champ en pied de tableau (⌘⏎), ou créez-la depuis une phrase de la transcription."
            )
        } else {
            VStack(spacing: 0) {
                enteteDeColonnes
                ForEach(Array(visible.visibles.enumerated()), id: \.element.persistentModelID) { index, task in
                    ligne(task, index: index)
                }
            }
            .padding(.top, 4)
            // Le tableau prend le clavier : `↑↓` navigue, `Espace` coche,
            // `⌥↑↓` réordonne (spec §2.7).
            .focusable()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                clavier(vertical: press.key == .downArrow ? 1 : -1,
                        option: press.modifiers.contains(.option))
            }
            .onKeyPress(.space) {
                guard let task = ligneCourante() else { return .ignored }
                onToggle(task)
                return .handled
            }
            .onChange(of: screen.review.focusRequest) { _, demande in
                guard let demande else { return }
                servir(demande)
            }
            .onAppear {
                if let demande = screen.review.focusRequest { servir(demande) }
            }
        }
    }

    private var enteteDeColonnes: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.colonnes.etat)
            SectionLabel("intitulé")
                .frame(maxWidth: .infinity, alignment: .leading)
            SectionLabel("responsable")
                .frame(width: Self.colonnes.responsable, alignment: .leading)
            SectionLabel("échéance")
                .frame(width: Self.colonnes.echeance, alignment: .leading)
            SectionLabel("charge")
                .frame(width: Self.colonnes.charge, alignment: .leading)
            SectionLabel("source")
                .frame(width: Self.colonnes.source, alignment: .leading)
            Color.clear.frame(width: Self.colonnes.menu)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    // MARK: - Ligne

    @ViewBuilder
    private func ligne(_ task: ActionTask, index: Int) -> some View {
        let selectionnee = screen.review.ligneSelectionnee == task.persistentModelID
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                celluleEtat(task)
                celluleIntitule(task)
                celluleResponsable(task)
                celluleEcheance(task)
                celluleCharge(task)
                celluleSource(task)
                celluleMenu(task)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, One2OneToken.tableRowPaddingV)
            if let cellule, cellule.ligne == task.persistentModelID {
                selecteur(cellule.champ, task: task)
                    .padding(.leading, Self.colonnes.etat + 4)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(fond(index: index, selectionnee: selectionnee))
        .contentShape(Rectangle())
        .onTapGesture { screen.review.ligneSelectionnee = task.persistentModelID }
    }

    /// Lignes alternées `surface` / `surface/alt` (spec §1.2), la sélection en
    /// `accent/action bg2` — le fond le plus pâle de la charte, pour qu'une
    /// ligne sélectionnée reste lisible.
    private func fond(index: Int, selectionnee: Bool) -> Color {
        if selectionnee { return One2OneToken.actionBg2 }
        return index.isMultiple(of: 2) ? One2OneToken.surface : One2OneToken.surfaceAlt
    }

    private func celluleEtat(_ task: ActionTask) -> some View {
        Button { onToggle(task) } label: {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(task.isCompleted ? One2OneToken.ok : One2OneToken.ink4)
        }
        .buttonStyle(.plain)
        .frame(width: Self.colonnes.etat, alignment: .leading)
        .help(task.isCompleted ? "Rouvrir l'action" : "Marquer comme faite")
    }

    @ViewBuilder
    private func celluleIntitule(_ task: ActionTask) -> some View {
        if titreEnEdition == task.persistentModelID {
            HStack(spacing: 6) {
                EditableTextField(placeholder: "Intitulé de l'action",
                                  text: Binding(get: { brouillonTitre },
                                                set: { brouillonTitre = $0 }))
                    .frame(height: 22)
                Button("OK") { validerTitre(task) }
                    .buttonStyle(.plain)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.actionInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        } else {
            Text(task.title)
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .onTapGesture(count: 2) {
                    brouillonTitre = task.title
                    titreEnEdition = task.persistentModelID
                }
                .help("Double-cliquez pour renommer")
        }
    }

    /// Un clic sur une invite qui **porte une suggestion** assigne directement
    /// (spec §2.5, même règle que la carte du rail). Sinon le sélecteur se
    /// déplie sous la ligne.
    @ViewBuilder
    private func celluleResponsable(_ task: ActionTask) -> some View {
        let suggestion = OwnerSuggestion.suggestion(for: task,
                                                     in: meeting,
                                                     projectTasks: actionsDuProjet)
        let etat = ActionCardEditing.etatResponsable(task)
        HStack(spacing: 0) {
            InvitePill(ActionCardEditing.libelleResponsable(task, suggestion: suggestion),
                       etat: etat) {
                if etat == .invite, let suggestion {
                    task.collaborator = suggestion
                    task.destinataire = .collaborateur
                    task.unresolvedAssigneeName = nil
                    onSave()
                } else {
                    basculer(.responsable, sur: task)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.colonnes.responsable, alignment: .leading)
    }

    @ViewBuilder
    private func celluleEcheance(_ task: ActionTask) -> some View {
        let libelle = Self.libelleEcheance(task)
        HStack(spacing: 0) {
            if task.dueDate == nil, task.deferralCount <= 1, task.isUrgent {
                // `Urgent` est un état, pas une valeur : il porte l'encre du
                // rapport et non la neutralité d'une pilule renseignée.
                Button { basculer(.echeance, sur: task) } label: {
                    Text(libelle.texte)
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(One2OneToken.report)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Poser une échéance")
            } else {
                InvitePill(libelle.texte, etat: libelle.etat) {
                    basculer(.echeance, sur: task)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.colonnes.echeance, alignment: .leading)
    }

    @ViewBuilder
    private func celluleCharge(_ task: ActionTask) -> some View {
        let minutes = task.effortMinutes ?? 0
        HStack(spacing: 0) {
            Button { basculer(.charge, sur: task) } label: {
                Text(minutes > 0 ? ActionCardEditing.chargeLabel(minutes) : "—")
                    .font(.plexSans(11.5, minutes > 0 ? .medium : .regular))
                    .foregroundStyle(minutes > 0 ? One2OneToken.ink2 : One2OneToken.ink4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(minutes > 0 ? "Changer la charge estimée" : "Estimer la charge")
            Spacer(minLength: 0)
        }
        .frame(width: Self.colonnes.charge, alignment: .leading)
    }

    @ViewBuilder
    private func celluleSource(_ task: ActionTask) -> some View {
        HStack(spacing: 0) {
            if let libelle = Self.libelleSource(task) {
                Button {
                    if let t = task.sourceRef?.t, let onSeek { onSeek(t) }
                } label: {
                    Text(libelle)
                        .font(.plexMono(10, .medium))
                        .foregroundStyle(task.sourceRef?.t == nil
                                         ? One2OneToken.ink4
                                         : One2OneToken.actionInk)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(task.sourceRef?.t == nil || onSeek == nil)
                .help(task.sourceRef?.t == nil
                      ? "Reportée de cette réunion"
                      : "Replacer la lecture à cet instant")
            } else {
                Text("—")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink4)
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.colonnes.source, alignment: .leading)
    }

    private func celluleMenu(_ task: ActionTask) -> some View {
        Menu {
            Button(task.isCompleted ? "Rouvrir" : "Marquer comme faite") { onToggle(task) }
            Button("Abandonner") {
                task.status = .dropped
                onSave()
            }
            Divider()
            Button("Monter") { deplacer(task, de: -1) }
            Button("Descendre") { deplacer(task, de: 1) }
            Divider()
            Button("Supprimer", role: .destructive) {
                context.delete(task)
                onSave()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(One2OneToken.ink4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Self.colonnes.menu)
    }

    // MARK: - Sélecteurs inline

    private func basculer(_ champ: ActionCardEditing.Champ, sur task: ActionTask) {
        screen.review.ligneSelectionnee = task.persistentModelID
        let cible = Cellule(ligne: task.persistentModelID, champ: champ)
        withAnimation(.easeOut(duration: 0.12)) {
            cellule = (cellule == cible) ? nil : cible
        }
    }

    @ViewBuilder
    private func selecteur(_ champ: ActionCardEditing.Champ, task: ActionTask) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            switch champ {
            case .responsable: selecteurResponsable(task)
            case .echeance:    selecteurEcheance(task)
            case .charge:      selecteurCharge(task)
            }
        }
        // `Tab` avance de champ sans refermer, `Esc` referme (spec §2.5).
        .onKeyPress(.tab) {
            cellule = Cellule(ligne: task.persistentModelID,
                              champ: ActionCardEditing.suivant(champ))
            return .handled
        }
        .onKeyPress(.escape) {
            cellule = nil
            return .handled
        }
    }

    private func selecteurResponsable(_ task: ActionTask) -> some View {
        HStack(spacing: 8) {
            OwnerPickerMenu(label: "Non assigné",
                            selection: Binding(get: { task.collaborator },
                                               set: { nouveau in
                                                   task.collaborator = nouveau
                                                   if nouveau != nil {
                                                       task.destinataire = .collaborateur
                                                       task.unresolvedAssigneeName = nil
                                                   }
                                               }),
                            allCollaborators: allCollaborators,
                            onSaved: onSave)
            Button("Moi") {
                task.collaborator = nil
                task.destinataire = .moi
                task.unresolvedAssigneeName = nil
                onSave()
                cellule = nil
            }
            .buttonStyle(.plain)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(One2OneToken.actionInk)
            Spacer(minLength: 0)
        }
    }

    private func selecteurEcheance(_ task: ActionTask) -> some View {
        HStack(spacing: 6) {
            ForEach(ActionCardEditing.raccourcisEcheance(depuis: Date()), id: \.libelle) { raccourci in
                Button(raccourci.libelle) {
                    task.dueDate = raccourci.date
                    onSave()
                    cellule = nil
                }
                .buttonStyle(.plain)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.actionInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(One2OneToken.actionBg))
            }
            DatePicker("",
                       selection: Binding(get: { task.dueDate ?? Date() },
                                          set: { task.dueDate = $0; onSave() }),
                       displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .controlSize(.mini)
            if task.dueDate != nil {
                Button("Aucune") {
                    task.dueDate = nil
                    onSave()
                    cellule = nil
                }
                .buttonStyle(.plain)
                .font(.plexSans(10.5))
                .foregroundStyle(One2OneToken.ink4)
            }
            Spacer(minLength: 0)
        }
    }

    private func selecteurCharge(_ task: ActionTask) -> some View {
        HStack(spacing: 5) {
            ForEach(ActionCardEditing.chargesProposees, id: \.self) { minutes in
                Button(ActionCardEditing.chargeLabel(minutes)) {
                    task.effortMinutes = minutes
                    onSave()
                    cellule = nil
                }
                .buttonStyle(.plain)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(One2OneToken.ink3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(One2OneToken.surfaceAlt))
            }
            if task.effortMinutes != nil {
                Button("—") {
                    task.effortMinutes = nil
                    onSave()
                    cellule = nil
                }
                .buttonStyle(.plain)
                .font(.plexSans(10.5))
                .foregroundStyle(One2OneToken.ink4)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Clavier

    private func ligneCourante() -> ActionTask? {
        guard let id = screen.review.ligneSelectionnee else { return nil }
        return visible.visibles.first { $0.persistentModelID == id }
    }

    private func clavier(vertical delta: Int, option: Bool) -> KeyPress.Result {
        let lignes = visible.visibles
        guard !lignes.isEmpty else { return .ignored }
        let courant = lignes.firstIndex { $0.persistentModelID == screen.review.ligneSelectionnee }

        if option {
            guard let courant,
                  let permutation = ActionsTableCommands.permutation(nombre: lignes.count,
                                                                     index: courant,
                                                                     delta: delta) else {
                return .ignored
            }
            ActionsTableCommands.appliquerOrdre(permutation.map { lignes[$0] })
            onSave()
            return .handled
        }

        guard let suivant = ActionsTableCommands.indexSuivant(courant: courant,
                                                               nombre: lignes.count,
                                                               delta: delta) else {
            return .ignored
        }
        screen.review.ligneSelectionnee = lignes[suivant].persistentModelID
        return .handled
    }

    private func deplacer(_ task: ActionTask, de delta: Int) {
        let lignes = toutes
        guard let index = lignes.firstIndex(where: { $0.persistentModelID == task.persistentModelID }),
              let permutation = ActionsTableCommands.permutation(nombre: lignes.count,
                                                                  index: index,
                                                                  delta: delta) else { return }
        ActionsTableCommands.appliquerOrdre(permutation.map { lignes[$0] })
        onSave()
    }

    /// Sert une demande de focus posée par l'écran — après génération du
    /// rapport, la spec §2.2 veut le curseur sur « le champ d'assignation de la
    /// première action non assignée ».
    private func servir(_ demande: ReviewState.DemandeDeFocus) {
        switch demande.cible {
        case .responsablePremiereActionNonAssignee:
            guard let index = ActionsTableCommands.premiereSansResponsable(toutes) else {
                screen.review.focusServi()
                return
            }
            // La ligne visée peut être au-delà du repli : le tableau se déplie,
            // sinon le focus se poserait sur une ligne qu'on ne voit pas.
            if index >= Self.lignesRepliees { screen.review.toutAfficher = true }
            let task = toutes[index]
            screen.review.ligneSelectionnee = task.persistentModelID
            cellule = Cellule(ligne: task.persistentModelID, champ: .responsable)
        }
        screen.review.focusServi()
    }

    private func validerTitre(_ task: ActionTask) {
        let propre = brouillonTitre.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un intitulé vidé ne supprime pas l'action : c'est le menu `⋯` qui le
        // fait, et une frappe malheureuse ne doit pas effacer une ligne.
        if !propre.isEmpty { task.title = propre }
        titreEnEdition = nil
        onSave()
    }

    // MARK: - Pied

    private var pied: some View {
        VStack(spacing: 0) {
            ActionComposer(meeting: meeting, screen: screen) { creee in
                screen.review.ligneSelectionnee = creee.persistentModelID
            }
            if visible.restantes > 0 || screen.review.toutAfficher {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            screen.review.toutAfficher.toggle()
                        }
                    } label: {
                        Text(screen.review.toutAfficher
                             ? "replier · \(Self.lignesRepliees) lignes"
                             : "\(visible.restantes) autres · tout afficher")
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 2)
    }
}
