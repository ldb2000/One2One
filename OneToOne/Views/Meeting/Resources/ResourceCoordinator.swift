import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import os

private let resourceLog = Logger(subsystem: "com.onetoone.app", category: "resources")

/// Le câblage du tiroir Ressources : ce que font `＋ Importer`, un dépôt,
/// `⌘⇧V`, `Présenter`, `Citer`, `Envoyer`, `Ouvrir`, `Relier` et `Retirer`.
///
/// Une **valeur**, reconstruite à chaque rendu depuis la réunion, le contexte
/// et l'état d'écran : rien à retenir, donc rien à désynchroniser. Elle
/// remplace les quatre chemins d'import qui vivaient dans `MeetingView`
/// (`onDrop`, `handleFileDrop`, `importDocuments`, `fileImporter`) — le
/// programme §2.4 point 1 interdit d'y ajouter quoi que ce soit, et ces
/// fonctions n'avaient rien à y faire : elles ne parlent que de ressources.
@MainActor
struct ResourceCoordinator {
    let meeting: Meeting
    let context: ModelContext
    let state: ResourcesState
    /// La tête de lecture, pour horodater un épinglage ou une citation.
    let playhead: MeetingPlayhead

    // MARK: - Import de fichiers

    /// Importe une liste d'URL : copie, extraction de texte, indexation RAG.
    ///
    /// Chaque fichier est traité indépendamment : un PDF illisible au milieu
    /// d'une sélection de cinq n'empêche pas les quatre autres d'entrer. Le
    /// message d'erreur est celui du dernier échec, effacé au début de la
    /// tentative suivante.
    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        state.importError = nil
        state.isImporting = true
        defer { state.isImporting = false }

        for url in urls {
            // Les URL issues du sélecteur de fichiers ou d'un glisser sont à
            // portée de sécurité : sans cette demande d'accès, la lecture
            // échoue et l'import « ne fait rien ».
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                try await MeetingAttachmentService.importDocument(
                    url: url, into: meeting, context: context)
            } catch {
                state.importError = error.localizedDescription
                resourceLog.error("import: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Traite le résultat du `fileImporter`.
    func importPicked(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            state.acceptDrop(itemCount: urls.count)
            await importFiles(urls)
        case .failure(let error):
            state.importError = error.localizedDescription
        }
    }

    // MARK: - Dépôt

    /// Traite un dépôt venu de n'importe où dans la fenêtre (spec §4.1).
    ///
    /// Rend `true` dès qu'un fournisseur peut porter un fichier : SwiftUI
    /// attend la réponse **avant** que l'extraction asynchrone des URL soit
    /// terminée, et répondre `false` ferait rejouer l'animation de rejet du
    /// glisser alors que l'import va bien avoir lieu.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        state.acceptDrop(itemCount: providers.count)
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let data = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            await importFiles(urls)
        }
        return true
    }

    // MARK: - Collage (⌘⇧V)

    /// `⌘⇧V` : colle un lien, à défaut une image, du presse-papiers.
    ///
    /// L'ordre compte : une adresse copiée depuis un navigateur arrive souvent
    /// **avec** un aperçu d'image dans le presse-papiers. Chercher l'image
    /// d'abord transformerait chaque lien collé en capture.
    @discardableResult
    func pasteFromClipboard() -> Bool {
        if let lien = AttachmentLinkImporter.fromPasteboard() {
            state.acceptPaste(.lien)
            AttachmentLinkImporter.attach(lien, to: meeting, in: context)
            return true
        }
        if MediaStore.clipboardHasImage, let fichier = MediaStore.saveClipboardImage() {
            state.acceptPaste(.fichier)
            Task { await importFiles([fichier]) }
            return true
        }
        state.open(filter: .seance)
        state.importError = "Le presse-papiers ne contient ni lien ni image."
        return false
    }

    // MARK: - Migration paresseuse

    /// Migre les pièces référencées de la réunion (D5). Appelée à l'ouverture
    /// de l'espace et du tiroir ; idempotente.
    func migrateIfNeeded() {
        AttachmentMigration.migrate(meeting: meeting, in: context)
    }

    // MARK: - Actions des vignettes

    /// Les closures que le tiroir passe à ses vignettes.
    func tileActions() -> ResourceTileActions {
        ResourceTileActions(
            present: { present($0) },
            cite: { cite($0) },
            send: { send($0) },
            open: { open($0) },
            relink: { chooseAndRelink($0) },
            delete: { delete($0) }
        )
    }

    /// `À l'écran` / `Présenter`.
    func present(_ item: ResourceItem) {
        guard item.isPresentable else { return }
        state.present(item.id)
        resourceLog.info("present: \(item.name, privacy: .public)")
    }

    /// `Citer` : la puce `◫ <nom> · p.n` dans la note courante, sans épingler
    /// (l'épinglage est le bouton de la carte « À l'écran »).
    func cite(_ item: ResourceItem) {
        AttachmentPinning.cite(item,
                               in: meeting,
                               at: playhead.t,
                               page: state.presentedResourceID == item.id ? state.presentedPage : nil,
                               context: context)
    }

    /// `Envoyer` : le partage macOS. Un lien partage son URL, un fichier son
    /// fichier — et une pièce orpheline n'a rien à partager.
    func send(_ item: ResourceItem) {
        let sujets: [Any]
        if let url = item.linkURL { sujets = [url] }
        else if let url = item.fileURL, !item.isOrphan { sujets = [url] }
        else { return }
        guard let fenetre = NSApp.keyWindow, let vue = fenetre.contentView else { return }
        let selecteur = NSSharingServicePicker(items: sujets)
        selecteur.show(relativeTo: .zero, of: vue, preferredEdge: .maxY)
    }

    /// `Ouvrir` : le navigateur pour un lien, l'application par défaut pour un
    /// fichier.
    func open(_ item: ResourceItem) {
        if let url = item.linkURL {
            NSWorkspace.shared.open(url)
        } else if let url = item.fileURL, !item.isOrphan {
            AttachmentImporter.openWithDefaultApp(url)
        } else if let url = item.fileURL {
            // Orpheline : on montre au moins l'endroit où le fichier était.
            NSWorkspace.shared.selectFile(nil,
                                          inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    /// `Relier` : demande le fichier, puis le relie.
    ///
    /// Un `NSOpenPanel` et non un second `.fileImporter` : macOS ne présente
    /// pas fiablement deux `.fileImporter` dans la même hiérarchie de vues —
    /// l'un masque l'autre, d'où le « impossible d'importer » que
    /// `MeetingView.FileImportTarget` documente déjà. Le panneau, lui, est
    /// indépendant de la hiérarchie.
    func chooseAndRelink(_ item: ResourceItem) {
        state.relinkTargetID = item.id
        let panneau = NSOpenPanel()
        panneau.allowsMultipleSelection = false
        panneau.canChooseDirectories = false
        panneau.message = "Choisissez le fichier de « \(item.name) » ; il sera copié dans la séance."
        panneau.prompt = "Relier"
        guard panneau.runModal() == .OK, let url = panneau.url else {
            state.relinkTargetID = nil
            return
        }
        relink(item, to: url)
    }

    /// Relie une pièce orpheline au fichier désigné : celui-ci est **copié**,
    /// comme n'importe quel import.
    func relink(_ item: ResourceItem, to url: URL) {
        guard let piece = attachment(for: item) else { return }
        do {
            try AttachmentMigration.relink(piece, to: url, in: context)
            state.relinkTargetID = nil
        } catch {
            state.importError = error.localizedDescription
        }
    }

    /// Retire la pièce de la séance. Le fichier copié part avec elle : le
    /// garder produirait exactement l'orpheline inverse — un fichier que plus
    /// aucune ligne ne réclame, invisible et pourtant compté au stockage.
    func delete(_ item: ResourceItem) {
        switch item.origin {
        case .pieceDeSeance:
            guard let piece = attachment(for: item) else { return }
            if piece.isCopiedIntoApp, let url = piece.fileURL {
                AttachmentImporter.deleteFromDisk(url)
            }
            if state.presentedResourceID == item.id { state.stopPresenting() }
            context.delete(piece)
            try? context.save()
        case .captureDeSeance(let id):
            // Le tiroir est devenu la galerie des captures : le bouton
            // `Capture` de la barre du haut y mène, et l'ancien popover n'a
            // plus d'appelant. Retirer une capture doit donc être possible
            // ici, sinon la capacité disparaît en attendant le lot 7.
            guard let capture = meeting.attachments.flatMap(\.slides).first(where: { $0.id == id })
            else { return }
            AttachmentImporter.deleteFromDisk(URL(fileURLWithPath: capture.imagePath))
            if state.presentedResourceID == item.id { state.stopPresenting() }
            context.delete(capture)
            try? context.save()
        case .pieceDeProjet:
            // Les pièces du projet se suppriment depuis la fiche projet : le
            // tiroir les montre en lecture (spec §4.1).
            break
        }
    }

    /// La ligne SwiftData derrière une valeur `ResourceItem`.
    func attachment(for item: ResourceItem) -> MeetingAttachment? {
        guard case .pieceDeSeance(let id) = item.origin else { return nil }
        return meeting.attachments.first { $0.stableID == id }
    }
}
