import SwiftUI
import SwiftData

/// Les règles d'édition rapide d'une carte d'action, hors de la vue (spec §2.5).
///
/// Ce qui décide de l'apparence d'une pilule et du parcours clavier est une
/// règle, pas un détail de rendu : une pilule d'invite qui passerait en vert
/// sans que personne ne porte l'action ferait mentir tout le rail.
///
/// `@MainActor` comme `ActionsRailGrouping`, dont il réutilise le formateur de
/// date : ces règles lisent le graphe SwiftData de l'écran, qui vit sur le fil
/// principal.
@MainActor
enum ActionCardEditing {

    /// Les trois champs éditables d'une carte, dans l'ordre où `Tab` les
    /// parcourt (spec §2.5 : « `Tab` passe au champ suivant »).
    enum Champ: Int, CaseIterable, Hashable, Sendable {
        case responsable
        case echeance
        case charge
    }

    /// Le champ suivant, en boucle : après la charge on revient au
    /// responsable. Une tabulation qui ne fait rien au dernier champ donne
    /// l'impression d'un clavier bloqué.
    static func suivant(_ champ: Champ) -> Champ {
        let cas = Champ.allCases
        guard let index = cas.firstIndex(of: champ) else { return .responsable }
        return cas[(index + 1) % cas.count]
    }

    /// Les charges proposées par le sélecteur, de la demi-heure à la journée.
    static let chargesProposees: [Int] = [30, 60, 120, 240, 480]

    /// Une journée de travail, en minutes. Huit heures, pas vingt-quatre : la
    /// charge d'une action se compte en temps ouvré.
    static let minutesParJour = 480

    /// `30min`, `1h`, `1h30`, `2h`, `1j` (capture 1a). Rend une chaîne vide
    /// pour une charge nulle ou absurde : c'est à l'appelant d'afficher alors
    /// l'invite, pas à ce formateur d'inventer un libellé.
    static func chargeLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        if minutes >= minutesParJour, minutes % minutesParJour == 0 {
            return "\(minutes / minutesParJour)j"
        }
        if minutes >= 60 {
            let heures = minutes / 60
            let reste = minutes % 60
            return reste == 0 ? "\(heures)h" : "\(heures)h\(reste)"
        }
        return "\(minutes)min"
    }

    /// Les trois raccourcis d'échéance du sélecteur inline : `Demain`,
    /// `Vendredi`, `+1 sem.`
    ///
    /// « Vendredi » désigne toujours un vendredi **à venir** : posée un
    /// vendredi, une échéance « Vendredi » qui tombe le jour même serait déjà
    /// dépassée à l'instant où on la pose.
    static func raccourcisEcheance(depuis reference: Date,
                                   calendar: Calendar = .current) -> [(libelle: String, date: Date)] {
        let jour = calendar.startOfDay(for: reference)
        let demain = calendar.date(byAdding: .day, value: 1, to: jour) ?? jour
        let semaine = calendar.date(byAdding: .day, value: 7, to: jour) ?? jour
        // `weekday` grégorien : 1 = dimanche, 6 = vendredi.
        let courant = calendar.component(.weekday, from: jour)
        var ecart = (6 - courant + 7) % 7
        if ecart == 0 { ecart = 7 }
        let vendredi = calendar.date(byAdding: .day, value: ecart, to: jour) ?? demain
        return [("Demain", demain), ("Vendredi", vendredi), ("+1 sem.", semaine)]
    }

    /// L'état de la pilule de responsable.
    ///
    /// `neutre` pour un nom que l'extraction n'a pas su relier à une fiche
    /// (`unresolvedAssigneeName`) : quelqu'un est nommé, mais rien n'est
    /// confirmé — ce n'est ni une invite ni un engagement.
    static func etatResponsable(_ task: ActionTask) -> InvitePill.Etat {
        if task.collaborator != nil { return .renseignee }
        let nom = task.unresolvedAssigneeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (nom?.isEmpty == false) ? .neutre : .invite
    }

    /// `Yann`, `＋ Yann` (suggestion), `＋ assigner` (rien).
    ///
    /// Le prénom seul : 330 px ne tiennent pas un nom complet à côté d'une
    /// échéance et d'une charge.
    static func libelleResponsable(_ task: ActionTask, suggestion: Collaborator?) -> String {
        if let porteur = task.collaborator { return prenom(porteur.name) }
        if let nom = task.unresolvedAssigneeName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nom.isEmpty {
            return prenom(nom)
        }
        if let suggestion { return "＋ \(prenom(suggestion.name))" }
        return "＋ assigner"
    }

    /// Le premier mot d'un nom.
    static func prenom(_ nom: String) -> String {
        nom.split(separator: " ").first.map(String.init) ?? nom
    }

    /// `Demain`, `Vendredi`, `11 sept.`, ou l'invite `＋ échéance`.
    ///
    /// Une échéance de la semaine se nomme par son jour (capture 1a :
    /// « Vendredi ») — c'est ainsi qu'on en parle en séance, et « 11 sept. »
    /// oblige à compter. Au-delà de six jours, et pour toute échéance
    /// **passée**, la date reprend la main : « Mardi » pour un mardi révolu
    /// serait un piège.
    static func libelleEcheance(_ task: ActionTask,
                                reference: Date = Date(),
                                calendar: Calendar = .current) -> String {
        guard let due = task.dueDate else { return "＋ échéance" }
        let jours = calendar.dateComponents([.day],
                                            from: calendar.startOfDay(for: reference),
                                            to: calendar.startOfDay(for: due)).day ?? 0
        switch jours {
        case 0: return "Aujourd'hui"
        case 1: return "Demain"
        case 2...6:
            var style = Date.FormatStyle.dateTime.weekday(.wide)
            style.locale = Locale(identifier: "fr_FR")
            style.timeZone = calendar.timeZone
            return due.formatted(style).capitalized
        default:
            return ActionsRailGrouping.dateOrdinale(due, calendar: calendar)
        }
    }

    /// `◫ mm:ss` pour une capture, `mm:ss ↗` pour une phrase ou une note,
    /// `nil` quand il n'y a pas d'instant où retourner (spec §2.5).
    static func libelleSource(_ task: ActionTask) -> String? {
        guard let ref = task.sourceRef, let t = ref.t else { return nil }
        let timecode = TimecodeLabel.format(t)
        switch ref.kind {
        case .capture: return "◫ \(timecode)"
        case .transcript, .note: return "\(timecode) ↗"
        // Une planche n'a pas de position sur l'axe audio à afficher ici : le
        // lien y mène par la planche, pas par la tête de lecture (lot 16).
        case .board: return nil
        }
    }
}

/// La carte d'action du rail (spec §2.5, capture `1a-cockpit.png`) : « titre
/// 11,5 px sur 2 lignes max, puis pilules d'édition rapide ».
///
/// Tout s'édite **sur place** : un clic sur une pilule déplie un sélecteur
/// sous le titre, jamais une modale (critère d'acceptation n° 3 du chantier 1).
/// C'est la différence de fond avec l'ancien `ActionsPanel`, dont l'assignation
/// passait par une feuille et faisait perdre le contexte de la séance.
struct ActionCard: View {

    @Bindable var task: ActionTask
    /// Tous les collaborateurs, pour le sélecteur de responsable.
    let allCollaborators: [Collaborator]
    /// Le responsable suggéré par `OwnerSuggestion`, affiché dans l'invite.
    let suggestion: Collaborator?
    /// Replace la tête de lecture sur la source. `nil` = pas d'axe temps.
    let onSeek: ((Double) -> Void)?
    /// Coche ou décoche l'action.
    let onToggle: () -> Void
    /// Persiste après chaque édition inline.
    let onSave: () -> Void

    /// Le champ déplié, `nil` quand la carte est au repos. Un seul à la fois :
    /// deux sélecteurs ouverts dans 330 px ne laisseraient rien voir du titre.
    @State private var champ: ActionCardEditing.Champ?

    private var calendrier: Calendar { .current }

    /// La barre gauche de 2 px : `accent/report` tant que personne ne porte
    /// l'action, c'est le repère qui fait lire le groupe `À ASSIGNER` d'un coup
    /// d'œil.
    private var couleurBarre: Color {
        ActionsRailGrouping.aUnPorteur(task) ? One2OneToken.hair : One2OneToken.report
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(couleurBarre)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 6) {
                titre
                pilules
                if let champ {
                    selecteur(champ)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, One2OneToken.cardPaddingMin)
            .padding(.vertical, One2OneToken.cardPaddingMin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous))
    }

    // MARK: - Titre

    private var titre: some View {
        HStack(alignment: .top, spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(task.isCompleted ? One2OneToken.ok : One2OneToken.ink4)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Rouvrir l'action" : "Marquer comme faite")

            Text(task.title)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink1)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Pilules

    private var pilules: some View {
        HStack(spacing: 5) {
            pilluleResponsable
            InvitePill(ActionCardEditing.libelleEcheance(task, calendar: calendrier),
                       etat: task.dueDate == nil ? .invite : .neutre) {
                basculer(.echeance)
            }
            pilluleCharge
            pilluleUrgent
            if let source = ActionCardEditing.libelleSource(task) {
                pilluleSource(source)
            }
            Spacer(minLength: 0)
        }
    }

    /// Un clic sur une invite qui **porte une suggestion** assigne directement
    /// (spec §2.5 : « un clic assigne »). La pilule devenue verte se clique de
    /// nouveau pour choisir quelqu'un d'autre.
    @ViewBuilder
    private var pilluleResponsable: some View {
        let etat = ActionCardEditing.etatResponsable(task)
        InvitePill(ActionCardEditing.libelleResponsable(task, suggestion: suggestion),
                   etat: etat) {
            if etat == .invite, let suggestion {
                task.collaborator = suggestion
                task.destinataire = .collaborateur
                task.unresolvedAssigneeName = nil
                onSave()
            } else {
                basculer(.responsable)
            }
        }
    }

    @ViewBuilder
    private var pilluleCharge: some View {
        let minutes = task.effortMinutes ?? 0
        InvitePill(minutes > 0 ? ActionCardEditing.chargeLabel(minutes) : "＋ charge",
                   etat: minutes > 0 ? .neutre : .invite) {
            basculer(.charge)
        }
    }

    private var pilluleUrgent: some View {
        Button {
            task.isUrgent.toggle()
            task.priority = task.isUrgent ? .urgent : .normal
            onSave()
        } label: {
            Text("!")
                .font(.plexSans(10.5, .semibold))
                .foregroundStyle(task.isUrgent ? One2OneToken.reportInk : One2OneToken.ink4)
                .frame(width: 17, height: 17)
                .background(
                    Circle().fill(task.isUrgent ? One2OneToken.reportBg : One2OneToken.surfaceAlt)
                )
        }
        .buttonStyle(.plain)
        .help(task.isUrgent ? "Urgente" : "Marquer urgente")
    }

    @ViewBuilder
    private func pilluleSource(_ libelle: String) -> some View {
        let t = task.sourceRef?.t
        Button {
            if let t, let onSeek { onSeek(t) }
        } label: {
            Text(libelle)
                .font(.plexMono(10, .medium))
                .foregroundStyle(One2OneToken.actionInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(One2OneToken.actionBg))
        }
        .buttonStyle(.plain)
        .disabled(onSeek == nil)
        .help("Replacer la lecture à cet instant")
    }

    // MARK: - Sélecteurs inline

    private func basculer(_ cible: ActionCardEditing.Champ) {
        withAnimation(.easeOut(duration: 0.12)) {
            champ = (champ == cible) ? nil : cible
        }
    }

    @ViewBuilder
    private func selecteur(_ champ: ActionCardEditing.Champ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            switch champ {
            case .responsable: selecteurResponsable
            case .echeance:    selecteurEcheance
            case .charge:      selecteurCharge
            }
        }
        .padding(.top, 2)
        // `Tab` avance de champ sans refermer le panneau : c'est le parcours
        // que la spec §2.5 décrit (« Tab passe au champ suivant »).
        .onKeyPress(.tab) {
            self.champ = ActionCardEditing.suivant(champ)
            return .handled
        }
        .onKeyPress(.escape) {
            self.champ = nil
            return .handled
        }
    }

    private var selecteurResponsable: some View {
        HStack(spacing: 6) {
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
                champ = nil
            }
            .buttonStyle(.plain)
            .font(.plexSans(10.5, .medium))
            .foregroundStyle(One2OneToken.actionInk)
            Spacer(minLength: 0)
        }
    }

    private var selecteurEcheance: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ForEach(ActionCardEditing.raccourcisEcheance(depuis: Date(), calendar: calendrier),
                        id: \.libelle) { raccourci in
                    Button(raccourci.libelle) {
                        task.dueDate = raccourci.date
                        onSave()
                        champ = nil
                    }
                    .buttonStyle(.plain)
                    .font(.plexSans(10.5, .medium))
                    .foregroundStyle(One2OneToken.actionInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(One2OneToken.actionBg))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
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
                        champ = nil
                    }
                    .buttonStyle(.plain)
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.ink4)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var selecteurCharge: some View {
        HStack(spacing: 5) {
            ForEach(ActionCardEditing.chargesProposees, id: \.self) { minutes in
                Button(ActionCardEditing.chargeLabel(minutes)) {
                    task.effortMinutes = minutes
                    onSave()
                    champ = nil
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
                    champ = nil
                }
                .buttonStyle(.plain)
                .font(.plexSans(10.5))
                .foregroundStyle(One2OneToken.ink4)
            }
            Spacer(minLength: 0)
        }
    }
}

/// La ligne compacte des groupes `REPORTÉES DU <date>` (spec §2.5 : « compact,
/// une ligne par action ») : puce ronde, titre sur une ligne, rien d'autre.
///
/// Une dette de la séance précédente se lit, elle ne s'édite pas au vol : le
/// clic sur la puce la solde, tout le reste passe par la carte du groupe
/// d'origine.
struct ActionCompactRow: View {
    let task: ActionTask
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(task.isCompleted ? One2OneToken.ok : One2OneToken.ink4)
            }
            .buttonStyle(.plain)
            .help("Marquer comme faite")
            Text(task.title)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink2)
                .lineLimit(1)
            Spacer(minLength: 4)
            if task.deferralCount > 1 {
                MonoMeta("\(task.deferralCount)×")
            }
        }
        .padding(.vertical, 3)
    }
}
