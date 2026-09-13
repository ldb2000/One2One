import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// L'onglet « Documents » de l'écran projet : les pièces jointes du projet,
/// leur import, leur dépôt par glisser-déposer, leur commentaire et leur
/// suppression.
///
/// **Le bloc est repris de `ProjectDetailView`** (lignes 214–313 avant ce
/// lot), aux jetons `One2OneToken` et en Plex : c'est la même mécanique — une
/// copie dans Application Support par `AttachmentImporter`, un
/// `ProjectAttachment` qui pointe la copie, et `hasDAT` / `hasDIT` posés selon
/// la catégorie. Rien n'a été ajouté ; c'est explicitement hors périmètre
/// (spec §6).
struct ProjectDocumentsTab: View {

    static let titre = "PIÈCES JOINTES"
    static let ajouter = "Ajouter une pièce jointe"
    static let invite = "Glissez-déposez un fichier (PDF, PPTX, …) ici pour l'ajouter au projet."
    static let vide = "Aucune pièce jointe projet"
    static let placeholderCommentaire = "Commentaire / intérêt du document…"
    static let categories = ["DAT", "DIT", "Document"]

    static let tailleNom: CGFloat = 13
    static let tailleMeta: CGFloat = 11.5
    static let tailleCategorie: CGFloat = 11

    let project: Project
    @Environment(\.modelContext) private var context

    @State private var categorie = "Document"
    @State private var importeur = false

    private var pieces: [ProjectAttachment] {
        project.attachments.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PilotageMetrics.ecartCartes) {
                barre
                if pieces.isEmpty {
                    zoneVide
                } else {
                    PilotageCard(marges: nil) {
                        PilotageCardHeader(titre: Self.titre)
                        ForEach(Array(pieces.enumerated()), id: \.element.persistentModelID) { rang, piece in
                            row(piece).pilotageRowSeparator(rang < pieces.count - 1)
                        }
                    }
                }
                Text(Self.invite)
                    .font(.plexSans(Self.tailleMeta))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
            .padding(.horizontal, PilotageTab.margeH)
            .padding(.top, PilotageTab.margeHaute)
            .padding(.bottom, PilotageTab.margeBasse)
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: deposer)
        .fileImporter(isPresented: $importeur,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true,
                      onCompletion: importer)
    }

    // MARK: - Barre d'ajout

    private var barre: some View {
        HStack(spacing: 8) {
            Picker("", selection: $categorie) {
                ForEach(Self.categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)
            Spacer(minLength: 0)
            Button { importeur = true } label: {
                Text(Self.ajouter)
                    .font(.plexSans(12.5, .medium))
                    .foregroundStyle(One2OneToken.onFilledButton)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                         style: .continuous)
                            .fill(One2OneToken.action)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var zoneVide: some View {
        Text(Self.vide)
            .font(.plexSans(12.5))
            .foregroundStyle(One2OneToken.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .strokeBorder(One2OneToken.dashedBorder,
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }

    // MARK: - Une pièce

    private func row(_ piece: ProjectAttachment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(piece.category)
                    .font(.plexMono(Self.tailleCategorie, .medium))
                    .foregroundStyle(One2OneToken.actionInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                         style: .continuous)
                            .fill(One2OneToken.actionBg)
                    )
                Text(piece.fileName)
                    .font(.plexSans(Self.tailleNom, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    AttachmentImporter.openWithDefaultApp(piece.resolvedURL())
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(One2OneToken.ink3)
                }
                .buttonStyle(.plain)
                .help("Ouvrir dans l'application par défaut")
                Button {
                    supprimer(piece)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(One2OneToken.report)
                }
                .buttonStyle(.plain)
                .help("Supprimer la pièce jointe")
            }
            EditableInPlace(valeur: piece.comment,
                            placeholder: Self.placeholderCommentaire,
                            fonte: .plexSans(Self.tailleMeta),
                            onValider: { commenter(piece, $0) }) {
                Text(piece.comment.isEmpty ? Self.placeholderCommentaire : piece.comment)
                    .font(.plexSans(Self.tailleMeta))
                    .foregroundStyle(piece.comment.isEmpty ? One2OneToken.inkMuted
                                                           : One2OneToken.ink3)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, PilotageMetrics.margeH)
        .padding(.vertical, 10)
    }

    // MARK: - Gestes

    private func importer(_ resultat: Result<[URL], Error>) {
        switch resultat {
        case .success(let urls):
            for url in urls { ajouter(url) }
            enregistrer()
        case .failure(let erreur):
            print("[ProjectDocuments] import échoué : \(erreur)")
        }
    }

    private func deposer(_ providers: [NSItemProvider]) -> Bool {
        var pris = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    ajouter(url)
                    enregistrer()
                }
            }
            pris = true
        }
        return pris
    }

    private func ajouter(_ source: URL) {
        do {
            let copie = try AttachmentImporter.copyIntoAppSupport(
                source: source,
                bucket: .project(code: project.code)
            )
            let piece = ProjectAttachment(url: copie, category: categorie)
            piece.project = project
            context.insert(piece)
            if categorie == "DAT" { project.hasDAT = true }
            if categorie == "DIT" { project.hasDIT = true }
        } catch {
            print("[ProjectDocuments] copie échouée : \(error)")
        }
    }

    private func supprimer(_ piece: ProjectAttachment) {
        AttachmentImporter.deleteFromDisk(piece.resolvedURL())
        context.delete(piece)
        enregistrer()
    }

    private func commenter(_ piece: ProjectAttachment, _ texte: String) {
        piece.comment = texte
        enregistrer()
    }

    private func enregistrer() {
        do {
            try context.save()
            SpotlightIndexService.shared.index(project: project)
        } catch {
            print("[ProjectDocuments] enregistrement échoué : \(error)")
        }
    }
}
