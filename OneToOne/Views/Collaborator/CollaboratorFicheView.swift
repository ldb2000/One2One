import SwiftUI
import SwiftData
import AppKit

/// Fiche collaborateur v3 — `SPEC-Fiche-Collaborateur.md`, tour 5.
///
/// **Le point structurant : la colonne d'état est hors du `ScrollView`.**
/// Quelle que soit la position dans l'historique, l'état courant reste visible.
/// La version précédente servait quatre listes empilées dans une seule colonne
/// de quatre écrans, et ne répondait jamais à « où en est cette personne ».
struct CollaboratorFicheView: View {
    @Bindable var collaborator: Collaborator
    @Environment(\.modelContext) private var context

    @State private var segment: TimelineKind?   // nil = « Tout »
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    /// Année affichée par le fil. `nil` = toutes.
    @State private var annee: Int?

    private var items: [TimelineItem] { CollaboratorTimeline.build(for: collaborator) }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider().overlay(FicheTokens.divider)
                segments
                CollaboratorTimelineList(items: filtered, meetingFor: meeting(of:))
            }
            .frame(minWidth: 560)
            .background(FicheTokens.bg)

            CollaboratorStateRail(collaborator: collaborator)
                .frame(width: FicheTokens.railWidth)
        }
        .confirmationDialog("Supprimer \(collaborator.name) ?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                context.delete(collaborator)
                try? context.save()
            }
        } message: {
            Text("Ses réunions et ses actions ne sont pas supprimées ; elles perdent ce participant.")
        }
        .sheet(isPresented: $showEditSheet) {
            CollaboratorEditSheet(collaborator: collaborator)
        }
    }

    /// Une décision n'a pas d'écran : cliquer l'une ou l'autre ouvre la
    /// réunion où elle a été actée.
    private func meeting(of item: TimelineItem) -> Meeting? {
        collaborator.meetings.first { $0.persistentModelID == item.meetingID }
    }

    private var filtered: [TimelineItem] {
        var lignes = items
        if let segment { lignes = lignes.filter { $0.kind == segment } }
        if let annee {
            lignes = lignes.filter { Calendar.current.component(.year, from: $0.date) == annee }
        }
        return lignes
    }

    /// Années où il s'est passé quelque chose, de la plus récente à la plus
    /// ancienne. Rien à choisir s'il n'y en a qu'une.
    private var anneesDisponibles: [Int] {
        Array(Set(items.map { Calendar.current.component(.year, from: $0.date) }))
            .sorted(by: >)
    }

    /// Exporte le fil affiché en markdown, dans le presse-papiers — le même
    /// filtre que ce qui est à l'écran.
    private func exporterLeFil() {
        let lignes = filtered.map { item in
            "- \(item.date.formatted(date: .numeric, time: .omitted)) · \(item.kind.pill) · \(item.title)"
        }
        let texte = "# \(collaborator.name)\n\n" + lignes.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(collaborator.name)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.17)
                        .foregroundStyle(FicheTokens.ink)
                    if OneToOneRhythm.isLate(for: collaborator, now: .now) {
                        capsule("1:1 EN RETARD", FicheTokens.warn)
                    }
                    if overdueCount > 0 {
                        capsule("\(overdueCount) ACTION\(overdueCount > 1 ? "S" : "") EN RETARD",
                                FicheTokens.late)
                    }
                }
                // Jamais l'email : ce n'est pas une information de pilotage, et
                // il n'y a pas la place. Il vit dans la feuille d'édition.
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(FicheTokens.ink.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            counters
            Button(FicheHeader.isFollowed(collaborator) ? "Préparer le 1:1"
                                                          : "Planifier le premier 1:1",
                   action: ouvrirPreparation)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Menu {
                Button("Modifier la fiche") { showEditSheet = true }
                    .keyboardShortcut("i")
                Button(collaborator.isArchived ? "Désarchiver" : "Archiver") {
                    collaborator.isArchived.toggle()
                    try? context.save()
                }
                Button("Exporter le fil…") { exporterLeFil() }
                Divider()
                Button("Supprimer définitivement", role: .destructive) {
                    showDeleteConfirm = true
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: FicheTokens.headerHeight)
        .background(FicheTokens.bg)
    }

    /// Ouvre la fenêtre de préparation du 1:1, par le mécanisme que le
    /// menubar utilise déjà — un jeton et une notification. Le bouton
    /// principal de l'écran ne faisait rien jusqu'ici, ce qui est pire qu'un
    /// bouton absent.
    private func ouvrirPreparation() {
        let token = PrepWindowToken(collabID: collaborator.ensuredStableID, projectID: nil)
        NotificationCenter.default.post(name: .openPrepWindow, object: nil,
                                        userInfo: ["token": token])
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = collaborator.photoURL(), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 42, height: 42).clipShape(Circle())
        } else {
            let paire = AvatarPalette.pair(for: collaborator.name)
            Text(AvatarPalette.initials(for: collaborator.name))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(paire.texte)
                .frame(width: 42, height: 42)
                .background(Circle().fill(paire.fond))
        }
    }

    private var subtitle: String {
        CollaboratorIdentity.subtitle(role: collaborator.role,
                                      entity: collaborator.entity?.name,
                                      projects: projectCount)
    }

    // MARK: - Compteurs

    /// Quatre compteurs, dont deux de natures différentes : `ouvertes` mesure
    /// une charge, `engagements` une confiance. D'où des seuils de couleur
    /// sans rapport — voir `EngagementLedger`.
    private var counters: some View {
        HStack(spacing: 18) {
            ForEach(FicheHeader.counters(for: collaborator, now: .now), id: \.label) { compteur in
                counter(compteur.value, compteur.label, teinte(compteur.level))
            }
        }
        .fixedSize()
    }

    private func teinte(_ level: FicheCounter.Level) -> Color {
        switch level {
        case .neutre:    return FicheTokens.ink
        case .attention: return FicheTokens.warn
        case .alerte:    return FicheTokens.late
        }
    }

    private func counter(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(FicheTokens.ink.opacity(0.45))
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var openActions: [ActionTask] { collaborator.assignedTasks.filter { !$0.isCompleted } }
    private var overdueCount: Int {
        openActions.filter { ($0.dueDate ?? .distantFuture) < .now }.count
    }
    private var projectCount: Int {
        CollaboratorProjects.involved(in: collaborator).count
    }

    // MARK: - Segments

    private var segments: some View {
        let counts = CollaboratorTimeline.counts(of: items)
        return HStack(spacing: 8) {
            segmentChip(nil, "Tout", items.count).keyboardShortcut("1", modifiers: .command)
            // Ordre de la spec : 1:1 · Notes · Décisions · Réunions.
            ForEach(Array([TimelineKind.oneToOne, .note, .decision, .meeting].enumerated()),
                    id: \.element) { rang, kind in
                segmentChip(kind, kind.pill, counts[kind] ?? 0)
                    .keyboardShortcut(KeyEquivalent(Character("\(rang + 2)")), modifiers: .command)
            }
            Spacer()
            if anneesDisponibles.count > 1 {
                Picker("", selection: $annee) {
                    Text("Toutes").tag(Int?.none)
                    ForEach(anneesDisponibles, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                .labelsHidden().fixedSize().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func segmentChip(_ kind: TimelineKind?, _ label: String, _ count: Int) -> some View {
        let actif = segment == kind
        return Button { segment = kind } label: {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 11.5, weight: actif ? .semibold : .regular))
                Text("\(count)").font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(actif ? Color.white.opacity(0.7) : FicheTokens.inkTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            // Sélection noire pleine, pas le bleu système : la sélection d'un
            // filtre n'est pas un verbe.
            .background(Capsule().fill(actif ? FicheTokens.ink : Color.clear))
            .overlay(Capsule().stroke(actif ? Color.clear : FicheTokens.stroke))
            .foregroundStyle(actif ? Color.white : FicheTokens.ink)
        }
        .buttonStyle(.plain)
    }

    private func capsule(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.4)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
    }
}
