import SwiftUI
import SwiftData

/// Feuille d'édition de la fiche (`⌘I`).
///
/// L'identité était éditable au tiers de la page, avec quatre boutons d'import
/// empilés qui repoussaient tout le contenu utile hors de l'écran — pour une
/// action faite une fois dans la vie du collaborateur. Elle passe en modale.
///
/// ⚠️ Squelette : le puits photo, ses quatre sources et le bloc « Suivi »
/// restent à écrire. Ce qui est là est fonctionnel.
struct CollaboratorEditSheet: View {
    @Bindable var collaborator: Collaborator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var entities: [Entity]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Modifier la fiche").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("⌘⏎ enregistrer · ⎋ annuler")
                    .font(.system(size: 11)).foregroundStyle(FicheTokens.ink.opacity(0.38))
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 12) {
                field("Nom complet") { TextField("", text: $collaborator.name) }
                // Pas l'email : le défaut de la version précédente affichait
                // l'adresse dans ce champ.
                field("Poste / rôle") { TextField("", text: $collaborator.role) }
                field("Email") {
                    TextField("", text: .constant(collaborator.email))
                        .disabled(true)
                        .foregroundStyle(FicheTokens.inkSecondary)
                }
                field("Entité") {
                    Picker("", selection: $collaborator.entity) {
                        Text("—").tag(Entity?.none)
                        ForEach(entities) { Text($0.name).tag(Entity?.some($0)) }
                    }
                    .labelsHidden()
                }
                field("Rythme des 1:1") {
                    Picker("", selection: $collaborator.oneToOneCadence) {
                        ForEach(OneToOneCadence.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Enregistrer") { try? context.save(); dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(FicheTokens.railBg)
        }
        .frame(width: 560)
    }

    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        // Libellé au-dessus, pas à gauche : un libellé à gauche impose une
        // colonne de largeur arbitraire et casse l'alignement dès qu'il
        // s'allonge.
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5).textCase(.uppercase)
                .foregroundStyle(FicheTokens.ink.opacity(0.4))
            content().textFieldStyle(.roundedBorder)
        }
    }
}
