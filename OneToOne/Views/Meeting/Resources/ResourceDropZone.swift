import SwiftUI

/// La zone de dépôt **permanente** en fin de liste (spec §4.1 : « Glissez un
/// fichier, collez un lien, ou capturez l'écran — `⌘⇧V` »).
///
/// Permanente et non révélée par le survol : c'est elle qui rend le dépôt
/// découvrable, et le §1.1 la veut « active » même quand la liste est pleine.
/// Le raccourci y est écrit — un raccourci qu'aucun écran n'énonce n'existe
/// pas.
struct ResourceDropZone: View {
    /// Un glisser survole la fenêtre.
    let isTargeted: Bool
    /// Ouvre le sélecteur de fichiers.
    let onImport: () -> Void
    /// Colle ce que contient le presse-papiers (`⌘⇧V`).
    let onPaste: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text(isTargeted ? "Relâchez pour importer dans cette séance"
                            : "Glissez un fichier ici, collez un lien,")
                .font(.plexSans(11.5))
                .foregroundStyle(isTargeted ? One2OneToken.actionInk : One2OneToken.inkMuted)
            if !isTargeted {
                HStack(spacing: 0) {
                    Text("ou ")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                    Button(action: onPaste) {
                        Text("capturez l'écran")
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.actionInk)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    Text(" — ")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                    Text("⌘⇧V")
                        .font(.plexMono(10.5))
                        // 10,5 px : `ink/4` (spec §1.2).
                        .foregroundStyle(One2OneToken.ink4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(isTargeted ? One2OneToken.actionBg : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(isTargeted ? One2OneToken.action : One2OneToken.strongBorder,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onImport)
        .animation(.easeInOut(duration: 0.12), value: isTargeted)
        .help("Glisser un fichier, coller un lien (⌘⇧V), ou cliquer pour choisir")
    }
}

#Preview("Zone de dépôt") {
    VStack(spacing: 12) {
        ResourceDropZone(isTargeted: false, onImport: {}, onPaste: {})
        ResourceDropZone(isTargeted: true, onImport: {}, onPaste: {})
    }
    .padding(12)
    .frame(width: One2OneToken.resourcesDrawerWidth)
    .background(One2OneToken.surface)
}
