import SwiftUI
import SwiftData
import AppKit

/// La zone « À l'écran » en haut de la colonne principale (spec §4.2, capture
/// `3a-tiroir-ressources.png`).
///
/// En-tête `À l'écran <nom> · p. 2` puis `Annoter` / `Épingler à mm:ss` /
/// `Arrêter le partage` ; scène de prévisualisation avec le document centré et
/// la légende **sous** lui ; bande `ÉPINGLÉ DANS LA SÉANCE` en pied.
///
/// La carte n'existe que **pendant un partage** : sans document à l'écran, elle
/// disparaît complètement de la colonne au lieu de laisser un cadre vide — même
/// règle que la pilule de la barre du haut (spec §4.2 : « pas d'état grisé »).
struct OnScreenCard: View {
    let meeting: Meeting
    let screen: MeetingScreenModel
    /// La ressource présentée.
    let item: ResourceItem

    @Environment(\.modelContext) private var context
    @State private var annotation = AnnotationOverlayModel()
    @State private var erreur: String?

    private var coordinateur: ResourceCoordinator {
        ResourceCoordinator(meeting: meeting, context: context,
                            state: screen.resources, playhead: screen.playhead)
    }

    private var pageCount: Int { DocumentPreview.pageCount(for: item.fileURL) }
    private var page: Int { screen.resources.presentedPage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            if screen.resources.isAnnotating { barreOutils }
            scene
            if let erreur {
                Text(erreur)
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.reportInk)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            PinnedInSessionStrip(meeting: meeting, screen: screen)
        }
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous))
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 8) {
            Text("À l'écran")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text(sousTitre)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
            if pageCount > 1 { pagination }
            Spacer(minLength: 8)
            bouton("Annoter",
                   teinte: screen.resources.isAnnotating ? .plein : .doux,
                   action: basculerAnnotation)
            bouton(libelleEpinglage, teinte: .neutre, action: epingler)
                .disabled(!item.isPinnable)
            bouton("Arrêter le partage", teinte: .danger) {
                screen.resources.stopPresenting()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// `Chiffrage_Marine_v3.xlsx · p. 2` — la page n'est mentionnée que si le
    /// document en a plusieurs.
    private var sousTitre: String {
        pageCount > 1 ? "\(item.name) · p. \(page)" : item.name
    }

    /// `Épingler à 12:08` : le timecode est celui de la tête de lecture, écrit
    /// dans le bouton. Un bouton qui dirait seulement « Épingler » laisserait
    /// deviner à quel instant l'épingle va tomber.
    private var libelleEpinglage: String {
        "Épingler à \(MeetingPlayhead.mmss(screen.playhead.t))"
    }

    private var pagination: some View {
        HStack(spacing: 3) {
            fleche("chevron.left", actif: page > 1) {
                screen.resources.goToPage(page - 1, pageCount: pageCount)
            }
            Text("\(page)/\(pageCount)")
                .font(.plexMono(10))
                .foregroundStyle(One2OneToken.ink4)
                .frame(minWidth: 30)
            fleche("chevron.right", actif: page < pageCount) {
                screen.resources.goToPage(page + 1, pageCount: pageCount)
            }
        }
    }

    private func fleche(_ symbole: String,
                        actif: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(actif ? One2OneToken.ink2 : One2OneToken.ink4.opacity(0.4))
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actif)
    }

    // MARK: - Boutons

    private enum Teinte { case plein, doux, neutre, danger }

    private func bouton(_ titre: String,
                        teinte: Teinte,
                        action: @escaping () -> Void) -> some View {
        let encre: Color = switch teinte {
        case .plein:  One2OneToken.onFilledButton
        case .doux:   One2OneToken.actionInk
        case .neutre: One2OneToken.ink2
        case .danger: One2OneToken.reportInk
        }
        let fond: Color = switch teinte {
        case .plein:  One2OneToken.action
        case .doux:   One2OneToken.actionBg
        case .neutre: One2OneToken.surface
        case .danger: One2OneToken.surface
        }
        let bordure: Color? = switch teinte {
        case .plein, .doux: nil
        case .neutre:       One2OneToken.strongBorder
        case .danger:       One2OneToken.report.opacity(0.45)
        }
        return Button(action: action) {
            Text(titre)
                .font(.plexSans(10.5, .medium))
                .foregroundStyle(encre)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(fond)
                )
                .overlay {
                    if let bordure {
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .strokeBorder(bordure, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scène

    /// Le document, la légende, et le calque d'annotation quand il est actif.
    private var scene: some View {
        DocumentPreviewScene(url: item.fileURL,
                             page: page,
                             fileName: item.name,
                             badge: item.badge,
                             tone: item.badgeTone,
                             annotation: screen.resources.isAnnotating ? annotation : nil)
            .frame(minHeight: 240, maxHeight: 420)
            .contentShape(Rectangle())
            // Mesure en `background` : un `GeometryReader` **autour** de la
            // scène ferait dépendre la mise en page d'elle-même, ce que le
            // programme §2.4 point 4 interdit (`_NSDetectedLayoutRecursion`).
            .background(
                GeometryReader { geo in
                    Color.clear.task(id: geo.size) { sceneSize = geo.size }
                }
            )
            .gesture(screen.resources.isAnnotating ? traceur : nil)
    }

    /// Le tracé : coordonnées **normalisées** par la taille de la scène, pour
    /// qu'un redimensionnement de fenêtre ne décale pas les annotations.
    private var traceur: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { valeur in
                let taille = sceneSize
                guard taille.width > 0, taille.height > 0 else { return }
                let point = CGPoint(x: valeur.location.x / taille.width,
                                    y: valeur.location.y / taille.height)
                if annotation.draft == nil { annotation.beginDraft(at: point) }
                else { annotation.updateDraft(to: point) }
            }
            .onEnded { _ in annotation.endDraft() }
    }

    /// Taille de la scène, mesurée au rendu. `@State` plutôt qu'un
    /// `GeometryReader` autour du geste : imbriquer un lecteur de géométrie
    /// dans la scène rendrait la mise en page dépendante d'elle-même, ce que
    /// le programme §2.4 point 4 interdit explicitement.
    @State private var sceneSize: CGSize = .zero

    // MARK: - Barre d'outils d'annotation

    private var barreOutils: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationOverlayModel.Tool.allCases) { outil in
                Button { annotation.tool = outil } label: {
                    HStack(spacing: 4) {
                        Image(systemName: outil.symbol).font(.system(size: 9, weight: .semibold))
                        Text(outil.label).font(.plexSans(10.5, .medium))
                    }
                    .foregroundStyle(annotation.tool == outil
                                     ? One2OneToken.actionInk : One2OneToken.ink3)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                            .fill(annotation.tool == outil
                                  ? One2OneToken.actionBg : One2OneToken.surfaceAlt)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button("Annuler le dernier") { annotation.undo() }
                .font(.plexSans(10.5))
                .buttonStyle(.plain)
                .foregroundStyle(One2OneToken.ink3)
                .disabled(annotation.isEmpty)
            bouton("Enregistrer la capture", teinte: .plein, action: enregistrerAnnotation)
                .disabled(annotation.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(One2OneToken.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func basculerAnnotation() {
        if screen.resources.isAnnotating {
            screen.resources.isAnnotating = false
            annotation.clear()
        } else {
            screen.resources.isAnnotating = true
        }
    }

    private func epingler() {
        AttachmentPinning.pin(item,
                              in: meeting,
                              at: screen.playhead.t,
                              page: pageCount > 1 ? page : nil,
                              context: context)
        screen.playhead.markers = MeetingTimelineMarkers.allMarkers(for: meeting)
    }

    /// Rend la page courante, y peint le calque, écrit un PNG neuf. Le fichier
    /// source n'est **jamais** modifié (spec §4.2).
    private func enregistrerAnnotation() {
        erreur = nil
        guard let url = item.fileURL, let fond = pageImage(url) else {
            erreur = "Cette pièce n'a pas d'aperçu : l'annotation ne peut pas être rendue."
            return
        }
        do {
            try AnnotationSaver.save(annotation: annotation,
                                     over: fond,
                                     of: item,
                                     in: meeting,
                                     at: screen.playhead.t,
                                     context: context)
            annotation.clear()
            screen.resources.isAnnotating = false
            screen.playhead.markers = MeetingTimelineMarkers.allMarkers(for: meeting)
        } catch {
            erreur = error.localizedDescription
        }
    }

    /// L'image de fond de l'annotation : la page rendue pour un PDF, le fichier
    /// lui-même pour une image.
    private func pageImage(_ url: URL) -> NSImage? {
        switch DocumentPreview.kind(for: url) {
        case .pdf:   return DocumentPreview.render(pdf: url, page: page, width: 1_400)
        case .image: return NSImage(contentsOf: url)
        case .unavailable: return nil
        }
    }
}
