import SwiftUI
import SwiftData

/// La carte d'un engagement dans le rail (capture 2a) : le texte, puis les
/// pilules — échéance, criticité, confidentialité, charge.
///
/// Tous les libellés viennent de `CommitmentsRailModel`, qui est pur et testé.
/// Partagée (`Shared/`) : la capture 5a montre les mêmes cartes, côté
/// collaborateur (lot 13).
struct CommitmentRow: View {

    let commitment: Commitment
    var now: Date = Date()

    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commitment.text)
                .font(.plexSans(12))
                .foregroundStyle(One2OneToken.ink2)
                .fixedSize(horizontal: false, vertical: true)
            let pilules = pilulesDeLaCarte
            if !pilules.isEmpty {
                HStack(spacing: 5) {
                    ForEach(pilules, id: \.texte) { pilule in
                        Pill(pilule.texte, ton: pilule.ton)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(One2OneToken.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .contextMenu { menu }
    }

    /// Les pilules dans l'ordre de la capture : échéance, charge, criticité,
    /// confidentialité. L'échéance d'abord — c'est la seule qu'on cherche du
    /// regard.
    private var pilulesDeLaCarte: [(texte: String, ton: ChipTon)] {
        var pilules: [(String, ChipTon)] = []
        if let echeance = CommitmentsRailModel.duePill(commitment, now: now) {
            pilules.append((echeance, tonDEcheance))
        }
        if let charge = CommitmentsRailModel.effortPill(commitment) {
            pilules.append((charge, .neutre))
        }
        if let criticite = CommitmentsRailModel.criticalityPill(commitment) {
            pilules.append((criticite, .report))
        }
        if let confidentialite = CommitmentsRailModel.privacyPill(commitment) {
            pilules.append((confidentialite, .oneOnOne))
        }
        return pilules.map { (texte: $0.0, ton: $0.1) }
    }

    /// Une échéance dépassée est en `accent/report` : c'est le seul cas où la
    /// date elle-même est une alerte. Sinon `ok` — la capture montre `11 sept.`
    /// en vert : une date prise est une bonne nouvelle.
    private var tonDEcheance: ChipTon {
        CommitmentLedger.isOverdue(commitment, now: now) ? .report : .ok
    }

    @ViewBuilder
    private var menu: some View {
        Button("Marquer tenu") { CommitmentLedger.markKept(commitment); save() }
        Button("Marquer manqué") { CommitmentLedger.markMissed(commitment); save() }
        Button("Reporter") {
            // `postpone` ne solde pas : l'engagement reste ouvert et le
            // compteur monte — c'est ce compteur que la spec veut voir affiché
            // « y compris pour le manager, sans exception ».
            CommitmentLedger.postpone(commitment)
            save()
        }
        Divider()
        Button(commitment.blocksOther ? "Ne bloque plus l'autre" : "Marquer bloquant") {
            commitment.blocksOther.toggle()
            save()
        }
        Button(commitment.visibility == .private ? "Rendre partagé" : "Rendre privé") {
            commitment.visibility = OneOnOneConfidentiality
                .toggledPrivacy(commitment.visibility, role: commitment.ownerSide)
            save()
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            context.delete(commitment)
            save()
        }
    }

    private func save() { try? context.save() }
}
