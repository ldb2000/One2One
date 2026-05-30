import SwiftUI
import UniformTypeIdentifiers

/// Header d'un panel de sidebar configurable. Fournit :
/// - Icône système + titre (depuis `RightSidebarPanelID`)
/// - Caret expand/collapse cliquable
/// - Source de drag (UTType.text avec le rawValue de l'id)
/// - `dragHandle = true` rend l'ensemble draggable
struct PanelHeader: View {
    let panelID: RightSidebarPanelID
    @Binding var expanded: Bool
    var draggable: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: panelID.systemImage)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(panelID.defaultTitle.uppercased())
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .contentShape(Rectangle())
        .modifier(DragModifier(panelID: panelID, enabled: draggable))
    }
}

/// Conditionally apply `.onDrag` (macOS draggable). Wrapped in a modifier so
/// `draggable: false` désactive le drag (utile pour le rail replié plus tard).
private struct DragModifier: ViewModifier {
    let panelID: RightSidebarPanelID
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.onDrag { NSItemProvider(object: panelID.rawValue as NSString) }
        } else {
            content
        }
    }
}
