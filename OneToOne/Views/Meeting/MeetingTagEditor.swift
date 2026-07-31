import SwiftUI
import SwiftData

/// Rangée de thèmes (`MeetingTag`) d'une réunion, éditable en place :
/// chips colorées liées, chips « fantômes » proposées par l'IA (contour
/// pointillé, à accepter ou ignorer) et bouton `+` ouvrant un popover de
/// recherche / création.
///
/// Les suggestions sont éphémères (state du parent, non persistées).
struct MeetingTagEditor: View {
    @Bindable var meeting: Meeting

    /// Thèmes proposés par l'IA, non encore acceptés. Vidé au fur et à mesure.
    @Binding var suggestions: [String]
    /// Une suggestion IA est en cours (spinner dans le popover).
    let isSuggesting: Bool
    /// Relance une suggestion IA manuellement.
    let onRequestSuggestions: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTag.name) private var allTags: [MeetingTag]

    @State private var showPopover = false
    @State private var search = ""
    @State private var newTagHex: String?

    /// Thèmes liés à la réunion, triés par nom.
    private var linked: [MeetingTag] {
        meeting.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Suggestions restant à traiter : celles déjà liées ne sont pas re-proposées.
    private var pendingSuggestions: [String] {
        let linkedKeys = Set(meeting.tags.map { MeetingTag.normalizedKey($0.name) })
        return suggestions.filter { !linkedKeys.contains(MeetingTag.normalizedKey($0)) }
    }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(linked) { tag in
                linkedChip(tag)
            }
            ForEach(pendingSuggestions, id: \.self) { name in
                ghostChip(name)
            }
            addButton
        }
    }

    // MARK: - Chips

    private func linkedChip(_ tag: MeetingTag) -> some View {
        let color = Color(hex: tag.colorHex) ?? .secondary
        return HStack(spacing: 3) {
            Text(tag.name).font(.caption2)
            Button {
                unlink(tag)
            } label: {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Retirer ce thème de la réunion")
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.22)))
        .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 0.5))
    }

    /// Chip « fantôme » : proposition IA non appliquée. Clic = accepter,
    /// croix = ignorer.
    private func ghostChip(_ name: String) -> some View {
        HStack(spacing: 3) {
            Button {
                accept(name)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles").font(.system(size: 7))
                    Text(name).font(.caption2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ajouter ce thème suggéré")
            Button {
                ignore(name)
            } label: {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Ignorer cette suggestion")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .overlay(
            Capsule().strokeBorder(
                Color.secondary.opacity(0.6),
                style: StrokeStyle(lineWidth: 0.7, dash: [3, 2])
            )
        )
    }

    private var addButton: some View {
        Button {
            search = ""
            newTagHex = nil
            showPopover = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Ajouter un thème")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    // MARK: - Popover

    /// Thèmes sélectionnables : non archivés, pas déjà liés, filtrés par la
    /// recherche (casse/accents ignorés).
    private var candidates: [MeetingTag] {
        let linkedIDs = Set(meeting.tags.map(\.persistentModelID))
        let key = MeetingTag.normalizedKey(search)
        return allTags.filter { tag in
            guard !tag.isArchived, !linkedIDs.contains(tag.persistentModelID) else { return false }
            guard !key.isEmpty else { return true }
            return MeetingTag.normalizedKey(tag.name).contains(key)
        }
    }

    /// Le texte saisi ne correspond à aucun thème existant → on propose la création.
    private var canCreate: Bool {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let key = MeetingTag.normalizedKey(trimmed)
        return !allTags.contains { MeetingTag.normalizedKey($0.name) == key }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Rechercher ou créer un thème…", text: $search)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canCreate { createAndLink() } }

            if !candidates.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(candidates) { tag in
                            Button {
                                link(tag)
                                showPopover = false
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: tag.colorHex) ?? .secondary)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name).font(.caption)
                                    Spacer(minLength: 8)
                                    Text("\(tag.meetings.count)")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 4).padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            if canCreate {
                Divider()
                colorSwatches
                Button {
                    createAndLink()
                } label: {
                    Label("Créer « \(search.trimmingCharacters(in: .whitespacesAndNewlines)) »",
                          systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()
            Button {
                onRequestSuggestions()
            } label: {
                HStack(spacing: 6) {
                    if isSuggesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("Suggérer des thèmes").font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSuggesting || (meeting.summary.isEmpty && meeting.mergedTranscript.isEmpty))
            .help("Propose des thèmes à partir du compte-rendu (ou de la transcription)")
        }
        .padding(10)
        .frame(width: 280)
    }

    /// Palette de couleurs pour un nouveau thème ; la teinte déterministe du
    /// nom saisi est pré-sélectionnée.
    private var colorSwatches: some View {
        let defaultHex = TagColorPalette.hex(for: search)
        let selected = newTagHex ?? defaultHex
        return HStack(spacing: 4) {
            ForEach(TagColorPalette.hexes, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .secondary)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(selected == hex ? 0.8 : 0), lineWidth: 1.5)
                    )
                    .onTapGesture { newTagHex = hex }
            }
        }
    }

    // MARK: - Actions

    private func link(_ tag: MeetingTag) {
        guard !meeting.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) else { return }
        meeting.tags.append(tag)
        try? context.save()
    }

    private func unlink(_ tag: MeetingTag) {
        meeting.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        try? context.save()
    }

    private func createAndLink() {
        let name = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tag = MeetingTag(name: name, colorHex: newTagHex ?? TagColorPalette.hex(for: name))
        context.insert(tag)
        meeting.tags.append(tag)
        try? context.save()
        search = ""
        newTagHex = nil
        showPopover = false
    }

    /// Accepte une suggestion : find-or-create puis lien à la réunion.
    private func accept(_ name: String) {
        guard let tag = MeetingTag.findOrCreate(name: name, in: context) else { return }
        link(tag)
        ignore(name)
    }

    private func ignore(_ name: String) {
        suggestions.removeAll { MeetingTag.normalizedKey($0) == MeetingTag.normalizedKey(name) }
    }
}
