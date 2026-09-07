import SwiftUI
import SwiftData

/// Le filtre segmenté `Les deux / Moi / <Prénom>` du tableau des engagements
/// (capture 2b).
///
/// Trois cas et non un `OneOnOneSide?` nu : le segment a besoin d'être
/// `Hashable` et ordonné pour `SegmentedMode`, et « les deux » n'est pas
/// l'absence de filtre, c'est un choix qu'on peut reprendre.
enum PrepCommitmentFilter: String, CaseIterable, Hashable, Sendable {
    case both
    case mine
    case theirs

    /// Le côté correspondant, `nil` pour `Les deux`.
    var side: OneOnOneSide? {
        switch self {
        case .both:   return nil
        case .mine:   return .manager
        case .theirs: return .collaborator
        }
    }

    /// Le libellé du segment. Le troisième porte le prénom de la personne du
    /// fil : « Collaborateur » serait un rôle, pas quelqu'un.
    func label(firstName: String) -> String {
        switch self {
        case .both:   return "Les deux"
        case .mine:   return "Moi"
        case .theirs: return firstName.isEmpty ? "Elle ou lui" : firstName
        }
    }
}

/// Le tableau `Engagements réciproques` de la capture 2b, traduit en lignes.
///
/// **Ce que le tableau montre** : les engagements encore ouverts, et ceux
/// soldés depuis l'entretien précédent. Pas tout l'historique du fil : la
/// capture affiche quatre lignes pour un fil qui en compte quatorze, et le pied
/// dit « 8 tenus sur 11 » — le pied compte donc l'histoire entière là où le
/// tableau montre ce qui est en jeu maintenant. C'est la même borne que
/// `TENUS DEPUIS LE DERNIER 1:1` de la capture 2a, et elle vient du même
/// calcul (`CommitmentLedger.settledSince`).
struct CommitmentsTableModel: Equatable, Sendable {

    struct Row: Equatable, Sendable, Identifiable {
        var id: PersistentIdentifier
        var text: String
        /// `Moi` ou le prénom de la personne du fil.
        var ownerLabel: String
        var ownerTone: OneOnOneTone
        /// `Vendredi`, `11 sept.`, `En retard`, `Tenu`, `Manqué` ou `—`.
        var dueLabel: String
        /// `nil` = encre neutre.
        var dueTone: OneOnOneTone?
        /// Vrai quand l'échéance est une date lointaine, que la capture met en
        /// gras (`11 sept.`).
        var dueEmphasised: Bool
        /// `4 sept.` — la colonne `PRIS LE`.
        var promisedLabel: String
        /// Texte barré et pastille pleine.
        var isKept: Bool
        var isOverdue: Bool
        var isMissed: Bool
        var deferralLabel: String?
    }

    var rows: [Row]
    /// `1 en retard côté manager`, `nil` quand il n'y a rien à reprocher.
    var lateBadge: String?
    /// `8 tenus sur 11 · taux 73 %`, `nil` tant que rien n'est soldé.
    var rateLabel: String?
    /// Le prénom du troisième segment.
    var firstName: String

    var isEmpty: Bool { rows.isEmpty }

    // MARK: - Largeurs de colonnes (spec §3.4 : `20 | 1fr | 92 | 84 | 96`)

    static let stateColumn: CGFloat = 20
    static let ownerColumn: CGFloat = 92
    static let dueColumn: CGFloat = 84
    static let promisedColumn: CGFloat = 96

    // MARK: - Construction

    @MainActor
    static func build(_ thread: OneOnOneThread,
                      current: Meeting?,
                      filter: PrepCommitmentFilter,
                      now: Date) -> CommitmentsTableModel {
        let prenom = OneOnOneThreadStore.firstName(of: thread)
        let depuis = current.flatMap {
            OneOnOneThreadStore.previousMeeting(before: $0, in: thread)?.date
        }

        let ouverts = CommitmentLedger.open(thread, side: filter.side)
        let soldes = CommitmentLedger.settledSince(depuis, in: thread, side: filter.side)
        // Union sans doublon : un engagement est soit ouvert, soit soldé, mais
        // les deux listes viennent de deux filtres et l'ordre final est donné
        // par le tri, pas par la concaténation.
        let retenus = ouverts + soldes

        return CommitmentsTableModel(
            rows: CommitmentLedger.byLatenessDescending(retenus, now: now).map {
                row($0, firstName: prenom, now: now)
            },
            lateBadge: CommitmentLedger.lateOnManagerSideLabel(thread, now: now),
            rateLabel: CommitmentLedger.rateLabel(thread),
            firstName: prenom
        )
    }

    @MainActor
    private static func row(_ commitment: Commitment,
                            firstName: String,
                            now: Date) -> Row {
        let cote = commitment.ownerSide
        let echeance = dueLabel(commitment, now: now)
        return Row(
            id: commitment.persistentModelID,
            text: commitment.text,
            ownerLabel: cote == .manager ? "Moi" : firstName,
            ownerTone: cote == .manager ? .oneOnOne : .ok,
            dueLabel: echeance.label,
            dueTone: echeance.tone,
            dueEmphasised: echeance.emphasised,
            promisedLabel: OneOnOneDateFormat.dayMonth(commitment.promisedAt),
            isKept: commitment.state == .kept,
            isOverdue: CommitmentLedger.isOverdue(commitment, now: now),
            isMissed: commitment.state == .missed,
            deferralLabel: CommitmentLedger.deferralLabel(commitment)
        )
    }

    /// La colonne `ÉCHÉANCE`, dans les cinq écritures de la capture.
    ///
    /// Un engagement soldé n'affiche plus sa date d'échéance mais son sort :
    /// `Tenu` sur la capture. La date de l'engagement tenu n'apprend plus rien,
    /// et la garder ferait lire « en retard » sur une ligne pourtant honorée.
    static func dueLabel(_ commitment: Commitment,
                         now: Date) -> (label: String, tone: OneOnOneTone?, emphasised: Bool) {
        switch commitment.state {
        case .kept:
            return ("Tenu", nil, false)
        case .missed:
            return ("Manqué", .report, false)
        case .open:
            guard let due = commitment.dueAt else { return ("—", nil, false) }
            if due < now { return ("En retard", .report, false) }
            let proche = OneOnOneDateFormat.isWithinWeekdayWindow(due, now: now)
            return (OneOnOneDateFormat.dueDate(due, now: now), nil, !proche)
        }
    }
}

/// Le tableau `Engagements réciproques` (capture 2b) : badge de retard, filtre
/// segmenté, cinq colonnes, composeur en pied et taux de tenue.
struct CommitmentsTable: View {

    let model: CommitmentsTableModel
    @Binding var filter: PrepCommitmentFilter
    /// Bascule tenu / rouvert depuis la pastille d'état.
    let onToggleState: (PersistentIdentifier) -> Void
    /// Crée un engagement depuis le composeur du pied.
    let onCreate: (String) -> Void

    @State private var draft = ""

    var body: some View {
        RefonteCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                entete
                enteteDeColonnes
                if model.isEmpty {
                    MeetingEmptyInvite(
                        titre: "Aucun engagement en cours",
                        invite: "Un engagement se prend en séance (`/engagement`) ou ici, "
                              + "dans le champ du bas. C'est ce tableau qui tient le taux."
                    )
                } else {
                    ForEach(model.rows) { ligne in
                        Rectangle().fill(One2OneToken.hair).frame(height: 1)
                        rangee(ligne)
                    }
                }
                Rectangle().fill(One2OneToken.hair).frame(height: 1)
                pied
            }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 9) {
            Text("Engagements réciproques")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            if let badge = model.lateBadge {
                Pill(badge, ton: .report)
            }
            Spacer(minLength: 12)
            SegmentedMode(selection: $filter,
                          options: PrepCommitmentFilter.allCases,
                          libelle: { $0.label(firstName: model.firstName) })
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.vertical, 11)
    }

    private var enteteDeColonnes: some View {
        HStack(spacing: 9) {
            Spacer().frame(width: CommitmentsTableModel.stateColumn)
            Text("Engagement").sectionLabel()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Porteur").sectionLabel()
                .frame(width: CommitmentsTableModel.ownerColumn, alignment: .leading)
            Text("Échéance").sectionLabel()
                .frame(width: CommitmentsTableModel.dueColumn, alignment: .leading)
            Text("Pris le").sectionLabel()
                .frame(width: CommitmentsTableModel.promisedColumn, alignment: .leading)
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.bottom, 7)
    }

    // MARK: - Lignes

    private func rangee(_ ligne: CommitmentsTableModel.Row) -> some View {
        HStack(spacing: 9) {
            Button { onToggleState(ligne.id) } label: {
                pastille(ligne)
                    .frame(width: CommitmentsTableModel.stateColumn, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ligne.isKept ? "Rouvrir cet engagement" : "Marquer comme tenu")

            HStack(spacing: 7) {
                Text(ligne.text)
                    .font(.plexSans(12.5))
                    .foregroundStyle(ligne.isKept ? One2OneToken.ink4 : One2OneToken.ink2)
                    .strikethrough(ligne.isKept, color: One2OneToken.ink4)
                    .lineLimit(1)
                if let reports = ligne.deferralLabel {
                    Chip(reports, ton: .report)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ligne.ownerLabel)
                .font(.plexSans(12, .medium))
                .foregroundStyle(ligne.ownerTone.color)
                .frame(width: CommitmentsTableModel.ownerColumn, alignment: .leading)

            Text(ligne.dueLabel)
                .font(.plexSans(12, ligne.dueEmphasised ? .semibold : .regular))
                .foregroundStyle(ligne.dueTone?.color ?? One2OneToken.ink2)
                .frame(width: CommitmentsTableModel.dueColumn, alignment: .leading)

            Text(ligne.promisedLabel)
                .font(.plexMono(11, .medium))
                .foregroundStyle(One2OneToken.ink3)
                .frame(width: CommitmentsTableModel.promisedColumn, alignment: .leading)
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.vertical, One2OneToken.tableRowPaddingV)
    }

    @ViewBuilder
    private func pastille(_ ligne: CommitmentsTableModel.Row) -> some View {
        if ligne.isKept {
            Circle().fill(One2OneToken.ok).frame(width: 9, height: 9)
        } else if ligne.isOverdue || ligne.isMissed {
            Circle().strokeBorder(One2OneToken.report, lineWidth: 1.4)
                .frame(width: 11, height: 11)
        } else {
            Circle().strokeBorder(One2OneToken.ink4, lineWidth: 1.2)
                .frame(width: 11, height: 11)
        }
    }

    // MARK: - Pied

    private var pied: some View {
        HStack(spacing: 9) {
            TextField("Nouvel engagement…", text: $draft)
                .textFieldStyle(.plain)
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
                .onSubmit(creer)
            Button(action: creer) { Text("Ajouter").font(.plexSans(11, .medium)) }
                .buttonStyle(.plain)
                .foregroundStyle(One2OneToken.oneOnOneInk)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
                .help("Ajouter l'engagement (⌘⏎) — porteur : Moi")
            Spacer(minLength: 12)
            if let taux = model.rateLabel {
                MonoMeta(taux, emphase: true)
            }
        }
        .padding(.horizontal, One2OneToken.cardPaddingMax)
        .padding(.vertical, 10)
    }

    private func creer() {
        let propre = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        onCreate(propre)
        draft = ""
    }
}
