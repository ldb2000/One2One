import SwiftUI
import SwiftData

/// Feuille d'édition de la fiche (`⌘I`) — §6 de la spec.
///
/// L'identité était éditable au tiers de la page, avec quatre boutons d'import
/// empilés sur 200 pt de haut pour quatre variantes d'une même action. Elle
/// passe en modale, et l'import de photo devient **un contrôle et un menu**.
struct CollaboratorEditSheet: View {
    @Bindable var collaborator: Collaborator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var entities: [Entity]
    @Query private var allCollaborators: [Collaborator]
    @Query private var reglagesList: [AppSettings]

    private var reglages: AppSettings? { reglagesList.first }

    @State private var showArchiveConfirm = false
    /// Vrai pendant qu'un glisser survole le puits. Le bandeau « DÉPOSER »
    /// n'apparaît qu'à ce moment : affiché en permanence, il masquait les
    /// initiales — et une photo déjà posée.
    @State private var dropTargeted = false
    @State private var showPhotoSearch = false

    /// Reçoit ce qui tombe dans le puits : un fichier image est adopté en
    /// place, une image brute est recopiée dans le dossier de l'app.
    private func adopter(_ fournisseurs: [NSItemProvider]) -> Bool {
        guard let fournisseur = fournisseurs.first else { return false }
        if fournisseur.canLoadObject(ofClass: URL.self) {
            _ = fournisseur.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    CollaboratorPhoto.adopt(fileURL: url, for: collaborator)
                    try? context.save()
                }
            }
            return true
        }
        fournisseur.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
            guard let data else { return }
            Task { @MainActor in
                CollaboratorPhoto.store(data, for: collaborator)
                try? context.save()
            }
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider().overlay(FicheTokens.divider)
            HStack(alignment: .top, spacing: 18) {
                photoWell
                identite
            }
            .padding(16)
            Divider().overlay(FicheTokens.divider)
            suivi
            pied
        }
        .frame(width: 560)
        .background(FicheTokens.bg)
        .sheet(isPresented: $showPhotoSearch) {
            PhotoSearchSheet(initialQuery: collaborator.name,
                             googleAPIKey: reglages?.googleCseApiKey ?? "",
                             googleCSEID: reglages?.googleCseId ?? "") { data in
                CollaboratorPhoto.store(data, for: collaborator)
                try? context.save()
            }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack {
            Text("Modifier la fiche").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FicheTokens.ink)
            Spacer()
            Text("⌘⏎ enregistrer · ⎋ annuler")
                .font(.system(size: 11)).foregroundStyle(FicheTokens.ink.opacity(0.38))
        }
        .padding(16)
    }

    // MARK: - Photo — un puits, pas quatre boutons

    private var photoWell: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                contenuDuPuits
                if dropTargeted {
                    Text("DÉPOSER")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(dropTargeted ? FicheTokens.link : FicheTokens.stroke,
                        lineWidth: dropTargeted ? 2 : 1))
            .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { fournisseurs in
                adopter(fournisseurs)
            }

            HStack(spacing: 4) {
                Button("Choisir") {
                    if CollaboratorPhoto.choose(for: collaborator) { try? context.save() }
                }
                .controlSize(.small)
                Menu {
                    Button("Importer un fichier…") {
                        if CollaboratorPhoto.choose(for: collaborator) { try? context.save() }
                    }
                    .keyboardShortcut("o")
                    Button("Coller depuis le presse-papiers") {
                        if CollaboratorPhoto.paste(for: collaborator) { try? context.save() }
                    }
                    .keyboardShortcut("v")
                    Button("Rechercher sur LinkedIn") {
                        LinkedInPhotoSearch.openLinkedInSearch(name: collaborator.name)
                    }
                    Button("Rechercher sur le web") { showPhotoSearch = true }
                    Divider()
                    Button("Retirer la photo", role: .destructive) {
                        CollaboratorPhoto.remove(for: collaborator)
                        try? context.save()
                    }
                } label: { EmptyView() }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)
                    .controlSize(.small)
            }
            Text("Glisser une image,\ncoller, ou")
                .font(.system(size: 10.5)).multilineTextAlignment(.center)
                .foregroundStyle(FicheTokens.inkSecondary)
            Button("LinkedIn") {
                LinkedInPhotoSearch.openLinkedInSearch(name: collaborator.name)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5)).foregroundStyle(FicheTokens.link)
        }
        .frame(width: 120)
    }

    /// La photo si elle existe, les initiales sinon — sur la couleur d'avatar
    /// de la personne, stable d'un lancement à l'autre.
    @ViewBuilder
    private var contenuDuPuits: some View {
        if let url = collaborator.photoURL(), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            let paire = AvatarPalette.pair(for: collaborator.name)
            ZStack {
                paire.fond
                Text(AvatarPalette.initials(for: collaborator.name))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(paire.texte)
            }
        }
    }

    // MARK: - Identité

    private var identite: some View {
        VStack(alignment: .leading, spacing: 12) {
            champ("Nom complet") { TextField("", text: $collaborator.name) }
            // Le champ n'affiche pas l'adresse : 38 fiches en portent une ici,
            // remplie par un import d'annuaire. Voir `CollaboratorIdentity`.
            champ("Poste / rôle") {
                TextField("Architecte, chef de projet…", text: Binding(
                    get: { CollaboratorIdentity.displayRole(collaborator.role) },
                    set: { saisi in
                        // Taper une adresse ici la range où elle doit être.
                        let repare = CollaboratorIdentity.repaired(role: saisi,
                                                                   email: collaborator.email)
                        collaborator.role = repare.role
                        collaborator.email = repare.email
                    }
                ))
            }
            champ("Email", hint: "importé de l'annuaire") {
                HStack {
                    Text(collaborator.email.isEmpty ? "—" : collaborator.email)
                        .foregroundStyle(FicheTokens.inkSecondary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10)).foregroundStyle(FicheTokens.inkTertiary)
                }
                .padding(.horizontal, 6).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(FicheTokens.railBg))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(FicheTokens.stroke))
            }
            champ("Entité") {
                Picker("", selection: $collaborator.entity) {
                    Text("—").tag(Entity?.none)
                    ForEach(entities) { Text($0.name).tag(Entity?.some($0)) }
                }.labelsHidden()
            }
            champ("Manager") {
                Picker("", selection: $collaborator.manager) {
                    Text("Moi").tag(Collaborator?.none)
                    ForEach(autresCollaborateurs) { Text($0.name).tag(Collaborator?.some($0)) }
                }.labelsHidden()
            }
        }
    }

    private var autresCollaborateurs: [Collaborator] {
        allCollaborators
            .filter { !$0.isArchived && $0.persistentModelID != collaborator.persistentModelID }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Suivi

    /// Chaque ligne porte une phrase d'explication : un réglage dont on ne
    /// voit pas l'effet ailleurs ne sera jamais utilisé.
    private var suivi: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suivi")
                .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .textCase(.uppercase).foregroundStyle(FicheTokens.inkTertiary)

            HStack(alignment: .firstTextBaseline) {
                explication("Rythme des 1:1", "sert à calculer le retard affiché sur la fiche")
                Spacer()
                Picker("", selection: $collaborator.oneToOneCadence) {
                    ForEach(OneToOneCadence.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Divider().overlay(FicheTokens.hairline)
            interrupteur("Épinglé dans la sidebar",
                         "remonte en tête de liste et des filtres d'assignation",
                         niveau: 2)
            Divider().overlay(FicheTokens.hairline)
            interrupteur("Favori", "second niveau de tri, sous les épinglés", niveau: 1)
        }
        .padding(16)
    }

    private func explication(_ titre: String, _ sous: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titre).font(.system(size: 12.5)).foregroundStyle(FicheTokens.ink)
            Text(sous).font(.system(size: 10.5)).foregroundStyle(FicheTokens.ink.opacity(0.42))
        }
    }

    /// Les deux interrupteurs écrivent le même champ `pinLevel` : 2 épinglé,
    /// 1 favori, 0 ni l'un ni l'autre. Cocher l'un décoche donc l'autre.
    private func interrupteur(_ titre: String, _ sous: String, niveau: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            explication(titre, sous)
            Spacer()
            Toggle("", isOn: Binding(
                get: { collaborator.pinLevel == niveau },
                set: { collaborator.pinLevel = $0 ? niveau : 0 }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(FicheTokens.ok)
        }
    }

    // MARK: - Pied

    private var pied: some View {
        HStack {
            Button("Archiver le collaborateur") { showArchiveConfirm = true }
                .buttonStyle(.plain)
                .foregroundStyle(FicheTokens.late)
                .font(.system(size: 11.5))
                .confirmationDialog("Archiver \(collaborator.name) ?",
                                    isPresented: $showArchiveConfirm) {
                    Button("Archiver", role: .destructive) {
                        collaborator.isArchived = true
                        try? context.save()
                        dismiss()
                    }
                }
            Spacer()
            Button("Annuler") { dismiss() }
            Button("Enregistrer") { try? context.save(); dismiss() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(FicheTokens.ink)
        }
        .padding(16)
        .background(FicheTokens.railBg)
        .overlay(alignment: .top) { Rectangle().fill(FicheTokens.divider).frame(height: 1) }
    }

    private func champ<Content: View>(_ label: String, hint: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        // Libellé au-dessus, pas à gauche : à gauche il impose une colonne de
        // largeur arbitraire et casse l'alignement dès qu'il s'allonge.
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                    .textCase(.uppercase).foregroundStyle(FicheTokens.ink.opacity(0.4))
                if let hint {
                    Text(hint).font(.system(size: 10))
                        .foregroundStyle(FicheTokens.inkTertiary)
                }
            }
            content().textFieldStyle(.roundedBorder)
        }
    }
}
