import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// La section **`PIÈCES & CAPTURES`** du dock (spec §7.2, capture
/// `6a-atelier-planche.png`) : les pièces de la séance et les captures, avec
/// `Sur la planche` / `Insérer`, et la zone
/// `Glissez un fichier — il est copié dans la réunion`.
///
/// `Insérer` **copie** l'image dans la réunion et la pose verrouillée sur la
/// planche (spec §8, critère n° 3) : c'est `WorkshopState.insertImage` qui le
/// fait, cette vue ne décide de rien.
struct WorkshopAttachmentsSection: View {

    let meeting: Meeting
    let state: WorkshopState
    /// Titre de la section.
    var title: String = "Pièces & captures"
    /// Ne montrer qu'une nature — les onglets `Captures` et `Pièces` du dock.
    /// `nil` = les deux, comme la section de l'onglet `Planches`.
    var only: ResourceItem.Nature?
    /// Invite affichée quand la liste est vide.
    var emptyInvite = "Aucune pièce dans cette séance. Glissez un fichier ci-dessous : il est copié dans la réunion."

    @Environment(\.modelContext) private var context
    @State private var isTargeted = false

    private var lignes: [ResourceItem] {
        let toutes = ResourceItem.workshopRows(for: meeting)
        guard let only else { return toutes }
        return toutes.filter { $0.nature == only }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).sectionLabel()

            if lignes.isEmpty {
                Text(emptyInvite)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(lignes) { ligne in
                    self.ligne(ligne)
                }
            }

            // Une capture ne se dépose pas : elle se prend (chantier 4). La
            // zone de dépôt n'a donc pas sa place dans l'onglet `Captures`.
            if only != .capture {
                zoneDeDepot
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Lignes

    private func ligne(_ item: ResourceItem) -> some View {
        HStack(alignment: .center, spacing: 9) {
            vignette(item)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.workshopTitle())
                    .font(.plexSans(11.5, .semibold))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.workshopSubtitle(in: meeting))
                    .font(.plexSans(10.5))
                    .foregroundStyle(One2OneToken.ink4)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            bouton(item)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface))
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1))
    }

    /// L'icône 34 × 40 du lot 6, telle quelle : le dock de l'atelier et le
    /// tiroir Ressources montrent les mêmes pièces, ils doivent les montrer de
    /// la même façon.
    private func vignette(_ item: ResourceItem) -> some View {
        ResourceTypeIcon(badge: item.workshopBadge(in: meeting),
                         tone: item.badgeTone,
                         isOrphan: item.isOrphan)
    }

    /// `Sur la planche` quand la pièce y est déjà — elle se contente alors de
    /// sélectionner l'objet ; `Insérer` sinon.
    @ViewBuilder
    private func bouton(_ item: ResourceItem) -> some View {
        let dejaPosee = state.insertedFileNames.contains(item.name)
        Button {
            Task {
                if dejaPosee {
                    await state.revealImage(named: item.name, meeting: meeting)
                } else if let url = item.fileURL {
                    await state.insertImage(from: url, meeting: meeting, context: context)
                }
            }
        } label: {
            Text(dejaPosee ? "Sur la planche" : "Insérer")
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(dejaPosee ? One2OneToken.ink3 : One2OneToken.ink2)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(dejaPosee ? One2OneToken.surfaceAlt : One2OneToken.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(dejaPosee ? One2OneToken.hair : One2OneToken.strongBorder,
                                      lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!item.isBoardInsertable)
        .help(dejaPosee
              ? "Sélectionner cette image sur la planche"
              : "Copier l'image dans la réunion et la poser, verrouillée, sur la planche")
    }

    // MARK: - Dépôt

    /// « Glissez un fichier — il est copié dans la réunion » (capture 6a). Le
    /// libellé **dit la politique** : copie, jamais référence (spec §8, D5).
    private var zoneDeDepot: some View {
        Text(isTargeted
             ? "Relâchez : le fichier est copié dans la réunion"
             : "Glissez un fichier — il est copié dans la réunion")
            .font(.plexSans(11))
            .foregroundStyle(isTargeted ? One2OneToken.actionInk : One2OneToken.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(isTargeted ? One2OneToken.actionBg : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(isTargeted ? One2OneToken.action : One2OneToken.strongBorder,
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { fournisseurs in
                accepter(fournisseurs)
            }
            .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }

    /// Un fichier déposé est **copié dans la réunion**
    /// (`AttachmentImporter.Bucket.meetingDocuments`) puis inséré sur la
    /// planche. Deux gestes en un, comme le promet la capture.
    private func accepter(_ fournisseurs: [NSItemProvider]) -> Bool {
        guard let fournisseur = fournisseurs.first else { return false }
        _ = fournisseur.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                await deposer(url)
            }
        }
        return true
    }

    @MainActor
    private func deposer(_ url: URL) async {
        let reunion = meeting.ensuredStableID
        do {
            let copie = try AttachmentImporter.copyIntoAppSupport(
                source: url,
                bucket: .meetingDocuments(meetingStableID: reunion))
            let piece = MeetingAttachment(
                url: copie,
                kind: AttachmentCopyPolicy.kind(forExtension: copie.pathExtension))
            piece.scope = .meeting
            piece.byteCount = (try? FileManager.default
                .attributesOfItem(atPath: copie.path)[.size] as? Int) ?? 0
            context.insert(piece)
            piece.meeting = meeting
            try? context.save()
            await state.insertImage(from: copie, meeting: meeting, context: context)
        } catch {
            state.errorMessage = "Dépôt impossible : \(error.localizedDescription)"
        }
    }
}
