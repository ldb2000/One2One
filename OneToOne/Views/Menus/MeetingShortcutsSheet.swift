import SwiftUI

/// La feuille « Raccourcis », ouverte depuis le menu `⋯` de la barre du haut.
///
/// Rend la table `AppShortcut` : il n'y a donc pas de seconde liste à tenir
/// en phase avec les déclarations, et un raccourci ajouté à la table apparaît
/// ici sans qu'on y touche. `Tests/AppShortcutsTests.swift` vérifie que
/// cette vue ne réécrit aucun jeton en dur.
///
/// Le nom de la vue est resté : c'est la feuille du menu `⋯` d'une **réunion**,
/// et la renommer aurait fait deux changements dans un lot qui n'en veut qu'un.
struct MeetingShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// La palette de commandes de note, dernière ligne de la table §1.4 : ce
    /// n'est pas un raccourci clavier, donc elle n'est pas dans
    /// `AppShortcut`, mais elle appartient à l'aide.
    private static let paletteTitre = "/ en début de ligne"
    private static let paletteDetail =
        "Palette de commandes de note : /action /décision /risque /citer /privé "
        + "/engagement /feedback /promesse /demande /preuve"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider().overlay(One2OneToken.hair)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AppShortcut.allCases, id: \.self) { raccourci in
                        ligne(jeton: raccourci.jeton,
                              libelle: raccourci.libelle,
                              note: raccourci.note)
                    }
                    Divider().overlay(One2OneToken.hair).padding(.vertical, 2)
                    ligne(jeton: Self.paletteTitre, libelle: Self.paletteDetail, note: nil)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            Divider().overlay(One2OneToken.hair)
            pied
        }
        .frame(width: 470, height: 440)
        .background(One2OneToken.surface)
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Raccourcis clavier")
                .font(.plexSans(15, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("Actifs sur la réunion qui a le focus ; la palette l'est partout.")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var pied: some View {
        HStack {
            Spacer()
            Button("Fermer") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func ligne(jeton: String, libelle: String, note: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(jeton)
                .font(.plexMono(11, .semibold))
                .foregroundStyle(One2OneToken.ink1)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .fill(One2OneToken.bgApp)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                        .strokeBorder(One2OneToken.hair, lineWidth: 1)
                )
                .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(libelle)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(.plexSans(11))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Raccourcis") {
    MeetingShortcutsSheet()
}
