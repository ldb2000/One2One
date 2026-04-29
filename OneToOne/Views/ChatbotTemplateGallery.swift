import SwiftUI
import SwiftData

// MARK: - Model

/// Variable typée d'un template de prompt — détermine le picker affiché
/// dans la sheet de configuration.
enum TemplateVariableKind {
    case collaborator
    case project
    case period
    case freeText(placeholder: String)

    var label: String {
        switch self {
        case .collaborator: return "Collaborateur"
        case .project:      return "Projet"
        case .period:       return "Période"
        case .freeText:     return "Texte"
        }
    }
}

/// Slot de variable dans un template. `key` apparaît entre `{...}` dans
/// le `template`, ex: `{Collaborateur}`.
struct TemplateVariable: Identifiable {
    let id = UUID()
    let key: String
    let kind: TemplateVariableKind
    var defaultValue: String = ""
}

/// Template de prompt présenté dans la galerie.
struct PromptTemplate: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    /// Description avec placeholders `{Key}` qui seront colorés.
    let descriptionTemplate: String
    /// Prompt complet envoyé à l'IA, avec placeholders `{Key}`.
    let promptTemplate: String
    let variables: [TemplateVariable]
}

extension PromptTemplate {
    static let gallery: [PromptTemplate] = [
        PromptTemplate(
            icon: "doc.text.magnifyingglass",
            tint: Color(red: 0.20, green: 0.55, blue: 0.85),
            title: "Faits marquants",
            descriptionTemplate: "Donne les faits marquants de la {Période} pour mon manager.",
            promptTemplate: "Donne-moi les faits marquants de la {Période} pour mon manager. Structure pour pilotage opérationnel.",
            variables: [
                TemplateVariable(key: "Période", kind: .period, defaultValue: "semaine en cours")
            ]
        ),
        PromptTemplate(
            icon: "person.2.fill",
            tint: Color(red: 0.55, green: 0.30, blue: 0.85),
            title: "Préparer un 1:1",
            descriptionTemplate: "M'aider à préparer le 1:1 avec {Collaborateur}.",
            promptTemplate: "Aide-moi à préparer mon prochain 1:1 avec {Collaborateur}. Liste les sujets à aborder, actions ouvertes, points de tension récents.",
            variables: [
                TemplateVariable(key: "Collaborateur", kind: .collaborator)
            ]
        ),
        PromptTemplate(
            icon: "chart.pie.fill",
            tint: Color(red: 0.85, green: 0.45, blue: 0.20),
            title: "Mise à jour projet",
            descriptionTemplate: "Rapport de statut exécutif sur {Projet}.",
            promptTemplate: "Produis un rapport de statut exécutif (R/Y/G, jalons, risques, prochaines actions) sur le projet {Projet}.",
            variables: [
                TemplateVariable(key: "Projet", kind: .project)
            ]
        ),
        PromptTemplate(
            icon: "exclamationmark.triangle.fill",
            tint: Color(red: 0.85, green: 0.25, blue: 0.30),
            title: "Alertes & risques",
            descriptionTemplate: "Synthèse des alertes ouvertes sur {Projet}.",
            promptTemplate: "Liste toutes les alertes ouvertes et risques identifiés sur {Projet}, classés par criticité, avec les actions correctives suggérées.",
            variables: [
                TemplateVariable(key: "Projet", kind: .project, defaultValue: "tous")
            ]
        ),
        PromptTemplate(
            icon: "text.bubble.fill",
            tint: Color(red: 0.20, green: 0.65, blue: 0.45),
            title: "Synthèse entretien",
            descriptionTemplate: "Synthèse du dernier entretien avec {Collaborateur}.",
            promptTemplate: "Fais la synthèse du dernier entretien réalisé avec {Collaborateur} : points clés, décisions, actions à suivre.",
            variables: [
                TemplateVariable(key: "Collaborateur", kind: .collaborator)
            ]
        ),
        PromptTemplate(
            icon: "person.crop.circle.badge.checkmark",
            tint: Color(red: 0.40, green: 0.55, blue: 0.30),
            title: "Bilan collaborateur",
            descriptionTemplate: "Bilan récent et axes de développement pour {Collaborateur}.",
            promptTemplate: "Établis un bilan récent (3 derniers mois) pour {Collaborateur} : projets contribués, accomplissements, axes de développement identifiés.",
            variables: [
                TemplateVariable(key: "Collaborateur", kind: .collaborator)
            ]
        ),
    ]
}

// MARK: - Gallery view

enum GalleryTab: String, CaseIterable, Identifiable {
    case discover  = "Découvrir"
    case history   = "Historique"
    case saved     = "Enregistré"
    var id: String { rawValue }
}

struct ChatbotTemplateGallery: View {
    let history: [String]
    let onSelect: (PromptTemplate) -> Void
    let onPickHistory: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPrompt.createdAt, order: .reverse) private var saved: [SavedPrompt]
    @State private var tab: GalleryTab = .discover

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 18) {
            tabBar

            switch tab {
            case .discover: discoverGrid
            case .history:  historyList
            case .saved:    savedPlaceholder
            }
        }
    }

    // MARK: tabs

    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(GalleryTab.allCases) { t in
                Button { withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
                    Text(t.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(tab == t ? .accentColor : .black.opacity(0.6))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(
                            Capsule().fill(tab == t ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(tab == t ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: discover

    private var discoverGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(PromptTemplate.gallery) { tpl in
                    Button { onSelect(tpl) } label: {
                        TemplateCard(template: tpl)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: history

    @ViewBuilder
    private var historyList: some View {
        if history.isEmpty {
            placeholderText("Aucune question récente. Tape une question ou choisis un template.")
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, q in
                        Button { onPickHistory(q) } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").foregroundColor(.secondary)
                                Text(q).lineLimit(2).foregroundColor(.black.opacity(0.85))
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.7))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: saved

    @ViewBuilder
    private var savedPlaceholder: some View {
        if saved.isEmpty {
            placeholderText("Aucun prompt enregistré. Utilise le bouton 💾 à côté du champ texte pour en ajouter.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(saved) { sp in
                        Button { onSelect(sp.asTemplate) } label: {
                            TemplateCard(template: sp.asTemplate)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(sp)
                                try? context.save()
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func placeholderText(_ s: String) -> some View {
        VStack {
            Spacer(minLength: 30)
            Text(s)
                .font(.callout)
                .foregroundColor(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
    }
}

// MARK: - Card

struct TemplateCard: View {
    let template: PromptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(template.tint.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: template.icon)
                        .foregroundColor(template.tint)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                Spacer()
            }

            highlightedDescription
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.78))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Rend la description en colorant les `{Key}` en accent.
    private var highlightedDescription: Text {
        let parts = splitByPlaceholders(template.descriptionTemplate)
        return parts.reduce(Text("")) { acc, part in
            switch part {
            case .literal(let s):    return acc + Text(s)
            case .placeholder(let k): return acc + Text(k).foregroundColor(.accentColor).fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Configure sheet

struct TemplateConfigSheet: View {
    let template: PromptTemplate
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }, sort: \Collaborator.name) private var collaborators: [Collaborator]
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.name) private var projects: [Project]

    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: template.icon)
                    .foregroundColor(template.tint)
                    .font(.title2)
                Text(template.title).font(.title3.weight(.semibold))
                Spacer()
            }

            Text(renderedPrompt)
                .font(.callout)
                .foregroundColor(.black.opacity(0.7))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)

            ForEach(template.variables) { v in
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.key).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    fieldFor(v)
                }
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Envoyer") {
                    onSubmit(renderedPrompt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            for v in template.variables where values[v.key] == nil {
                values[v.key] = v.defaultValue
            }
        }
    }

    @ViewBuilder
    private func fieldFor(_ v: TemplateVariable) -> some View {
        switch v.kind {
        case .collaborator:
            Picker("", selection: bindingFor(v.key)) {
                Text("Choisir…").tag("")
                ForEach(collaborators) { c in Text(c.name).tag(c.name) }
            }
            .labelsHidden()
        case .project:
            Picker("", selection: bindingFor(v.key)) {
                Text("Choisir…").tag("")
                ForEach(projects) { p in Text(p.name).tag(p.name) }
            }
            .labelsHidden()
        case .period:
            Picker("", selection: bindingFor(v.key)) {
                ForEach(["semaine en cours", "semaine dernière", "mois en cours", "mois dernier", "trimestre"], id: \.self) { p in
                    Text(p).tag(p)
                }
            }
            .labelsHidden()
        case .freeText(let placeholder):
            TextField(placeholder, text: bindingFor(v.key))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func bindingFor(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private var renderedPrompt: String {
        var out = template.promptTemplate
        for v in template.variables {
            let val = values[v.key] ?? ""
            out = out.replacingOccurrences(of: "{\(v.key)}", with: val.isEmpty ? "{\(v.key)}" : val)
        }
        return out
    }

    private var isComplete: Bool {
        template.variables.allSatisfy { !(values[$0.key] ?? "").isEmpty }
    }
}

// MARK: - SavedPrompt bridge

extension SavedPrompt {
    /// Construit un `PromptTemplate` à la volée. Variables détectées via
    /// les `{Key}` présents dans `promptText`. Description = aperçu du
    /// promptText (les `{Key}` seront colorés par `TemplateCard`).
    var asTemplate: PromptTemplate {
        let keys: [String] = splitByPlaceholders(promptText).compactMap {
            if case .placeholder(let k) = $0 { return k } else { return nil }
        }
        var seen = Set<String>()
        let vars: [TemplateVariable] = keys.compactMap { k in
            guard !seen.contains(k) else { return nil }
            seen.insert(k)
            return TemplateVariable(key: k, kind: kindForKey(k))
        }
        return PromptTemplate(
            icon: iconName,
            tint: .accentColor,
            title: title,
            descriptionTemplate: promptText,
            promptTemplate: promptText,
            variables: vars
        )
    }

    private func kindForKey(_ key: String) -> TemplateVariableKind {
        let k = key.lowercased()
        if k.contains("collab") { return .collaborator }
        if k.contains("projet") || k.contains("project") { return .project }
        if k.contains("période") || k.contains("periode") { return .period }
        return .freeText(placeholder: key)
    }
}

// MARK: - Save sheet

struct SavePromptSheet: View {
    let initialPrompt: String
    let onSaved: (SavedPrompt) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title: String = ""
    @State private var promptText: String = ""
    @State private var iconName: String = "bookmark.fill"

    private let iconChoices = [
        "bookmark.fill", "star.fill", "sparkles", "doc.text.fill",
        "person.2.fill", "chart.pie.fill", "checklist", "calendar"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enregistrer ce prompt").font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Titre").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                TextField("Ex: Préparer 1:1", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    Spacer()
                    Text("Variables: \(detectedVariables.isEmpty ? "—" : detectedVariables.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                TextEditor(text: $promptText)
                    .font(.callout)
                    .padding(6)
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                Text("Encadre une variable avec des accolades : {Collaborateur}, {Projet}, {Période}.")
                    .font(.caption2).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Icône").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(iconChoices, id: \.self) { name in
                        Button { iconName = name } label: {
                            Image(systemName: name)
                                .frame(width: 28, height: 28)
                                .background(iconName == name ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .foregroundColor(iconName == name ? .accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Enregistrer") {
                    let sp = SavedPrompt(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        promptText: promptText,
                        iconName: iconName
                    )
                    context.insert(sp)
                    try? context.save()
                    onSaved(sp)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 360)
        .onAppear { promptText = initialPrompt }
    }

    private var detectedVariables: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in splitByPlaceholders(promptText) {
            if case .placeholder(let k) = p, !seen.contains(k) {
                seen.insert(k); out.append(k)
            }
        }
        return out
    }
}

// MARK: - Helpers

enum TemplatePart {
    case literal(String)
    case placeholder(String)
}

/// Split "Foo {Bar} baz {Qux}" into [.literal("Foo "), .placeholder("Bar"), .literal(" baz "), .placeholder("Qux")].
func splitByPlaceholders(_ s: String) -> [TemplatePart] {
    var parts: [TemplatePart] = []
    var current = ""
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "{" {
            if !current.isEmpty { parts.append(.literal(current)); current = "" }
            if let close = s[i...].firstIndex(of: "}") {
                let key = String(s[s.index(after: i)..<close])
                parts.append(.placeholder(key))
                i = s.index(after: close)
                continue
            }
        }
        current.append(s[i])
        i = s.index(after: i)
    }
    if !current.isEmpty { parts.append(.literal(current)) }
    return parts
}
