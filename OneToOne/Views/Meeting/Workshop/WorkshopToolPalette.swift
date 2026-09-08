import SwiftUI

/// La palette verticale de l'écran 6a : **52 px** de large
/// (`One2OneToken.toolPaletteWidth`), outils 32 × 32 de rayon 7, l'outil actif
/// en `ink/1` plein, `↺ ↻` en pied (spec §7.2).
struct WorkshopToolPalette: View {

    static let itemSize: CGFloat = 32

    let meeting: Meeting
    let state: WorkshopState

    /// Le mode de la planche affichée décide de la palette (spec §7.1). Pas de
    /// planche = Croquis, le mode d'une planche neuve.
    private var mode: BoardMode { state.activeBoard(of: meeting)?.mode ?? .sketch }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(WorkshopPalette.tools(for: mode)) { outil in
                bouton(symbole: outil.symbol,
                       aide: outil.label,
                       actif: outil == state.tool) {
                    Task { await state.apply(tool: outil, meeting: meeting) }
                }
            }

            // Les formes de la bibliothèque, sous un filet — mode Schéma
            // seulement. Un clic **dépose** la forme au centre de la planche :
            // ce n'est pas un outil qu'on arme, c'est un objet qu'on pose.
            let formes = WorkshopPalette.shapes(for: mode)
            if !formes.isEmpty {
                Rectangle()
                    .fill(One2OneToken.hair)
                    .frame(width: Self.itemSize - 8, height: 1)
                    .padding(.vertical, 2)
                ForEach(formes) { forme in
                    bouton(symbole: forme.symbol, aide: forme.label, actif: false) {
                        Task { await state.insert(shape: forme, meeting: meeting) }
                    }
                }
            }

            Spacer(minLength: 12)

            // Annulation et rétablissement (profondeur 100 côté moteur).
            bouton(symbole: "arrow.counterclockwise", aide: "Annuler", actif: false) {
                Task { await state.undo(meeting: meeting) }
            }
            bouton(symbole: "arrow.clockwise", aide: "Rétablir", actif: false) {
                Task { await state.redo(meeting: meeting) }
            }
        }
        .padding(.vertical, 10)
        .frame(width: One2OneToken.toolPaletteWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(One2OneToken.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(One2OneToken.hair).frame(width: 1)
        }
    }

    @ViewBuilder
    private func bouton(symbole: String,
                        aide: String,
                        actif: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(actif ? One2OneToken.onFilledButton : One2OneToken.ink3)
                .frame(width: Self.itemSize, height: Self.itemSize)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(actif ? One2OneToken.ink1 : One2OneToken.surfaceAlt))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(actif ? Color.clear : One2OneToken.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(aide)
        .accessibilityLabel(aide)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }
}
