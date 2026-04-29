import SwiftUI
import SwiftData

/// Ingestion de mails Apple Mail comme sources RAG rattachees a un projet.
struct MailBrowserView: View {
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var context
    @State private var mailboxes: [MailboxRef] = []
    @State private var selectedMailbox: MailboxRef?
    @State private var loadedSnippets: [MailSnippet] = []
    @State private var snippets: [MailSnippet] = []
    @State private var selected: MailSnippet?
    @State private var bodyText: String = ""
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedProject: Project?
    @State private var saveStatus: String?
    @State private var isSaving = false
    @State private var availableAttachments: [MailAttachmentFile] = []
    @State private var selectedAttachmentIDs: Set<String> = []
    @State private var isLoadingAttachments = false

    private var selectedAttachments: [MailAttachmentFile] {
        availableAttachments.filter { selectedAttachmentIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            commandBar
            Divider()
            HSplitView {
                listPanel
                    .frame(minWidth: 420, idealWidth: 500)
                detailPanel
                    .frame(minWidth: 560)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Mails")
        .onAppear { Task { await loadMailboxesAndReload() } }
    }

    // MARK: - Command bar

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Boîte", selection: $selectedMailbox) {
                    Text("Choisir une inbox").tag(nil as MailboxRef?)
                    ForEach(mailboxes) { mailbox in
                        Text(mailbox.displayName).tag(mailbox as MailboxRef?)
                    }
                }
                .frame(width: 280)
                .onChange(of: selectedMailbox) { _, _ in
                    selected = nil
                    bodyText = ""
                    Task { await reload() }
                }

                Picker("Projet cible", selection: $selectedProject) {
                    Text("Aucun projet").tag(nil as Project?)
                    ForEach(projects.sorted(by: { $0.name < $1.name })) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
                .frame(width: 280)

                TextField("Rechercher sujet, expéditeur ou contenu…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, _ in
                        applyLocalSearch()
                    }

                Button(action: { Task { await reload() } }) {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .help("Actualiser les mails")
            }

            HStack(spacing: 12) {
                if isLoading {
                    ProgressView().controlSize(.small)
                    Text("Chargement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("\(snippets.count) mail(s) affiché(s) / \(loadedSnippets.count) chargé(s)", systemImage: "envelope")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let selectedProject {
                    Label("\(selectedProject.mails.count) source(s) RAG projet", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let saveStatus {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - List panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            List {
                ForEach(snippets) { snip in
                    Button(action: { select(snip) }) {
                        row(snip)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selected?.id == snip.id ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ snip: MailSnippet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snip.subject.isEmpty ? "(sans sujet)" : snip.subject)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(snip.dateReceived.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Text(snip.sender)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if !snip.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(snip.preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Label(snip.accountName, systemImage: "tray")
                Text(snip.mailbox)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Detail panel

    private var detailPanel: some View {
        Group {
            if let snip = selected {
                VStack(alignment: .leading, spacing: 8) {
                    detailHeader(snip)
                    Divider()
                    mailBodyPanel
                    attachmentsPanel
                    Divider()
                    actionBar
                    savedSourcesPanel
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: snip) { _, new in
                    bodyText = new.body ?? ""
                    if bodyText.isEmpty {
                        Task { await loadBody(for: new) }
                    }
                }
                .task {
                    if bodyText.isEmpty {
                        await loadBody(for: snip)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Aucun mail sélectionné",
                    systemImage: "envelope",
                    description: Text("Choisis un message dans la liste.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var attachmentsPanel: some View {
        if !availableAttachments.isEmpty || isLoadingAttachments {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pièces jointes à joindre")
                        .font(.headline)
                    Text("\(selectedAttachments.count)/\(availableAttachments.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if isLoadingAttachments {
                        ProgressView().controlSize(.small)
                    } else if !availableAttachments.isEmpty {
                        Button("Tout sélectionner") {
                            selectedAttachmentIDs = Set(availableAttachments.map(\.id))
                        }
                        .font(.caption)
                        Button("Tout désélectionner") {
                            selectedAttachmentIDs = []
                        }
                        .font(.caption)
                    }
                }

                ForEach(availableAttachments) { attachment in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { selectedAttachmentIDs.contains(attachment.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedAttachmentIDs.insert(attachment.id)
                                } else {
                                    selectedAttachmentIDs.remove(attachment.id)
                                }
                            }
                        )) {
                            Image(systemName: "paperclip")
                                .foregroundColor(.secondary)
                        }
                        .toggleStyle(.checkbox)
                        Text(attachment.fileName)
                            .lineLimit(1)
                        Spacer()
                        Button("Ouvrir") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: attachment.path))
                        }
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
    }

    private func detailHeader(_ snip: MailSnippet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snip.subject.isEmpty ? "(sans sujet)" : snip.subject)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(snip.sender)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(snip.dateReceived.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.monospacedDigit())
                    Text("\(snip.accountName) / \(snip.mailbox)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Label("Source RAG projet", systemImage: "sparkles.rectangle.stack")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let selectedProject {
                    Text(selectedProject.name)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(6)
                }
            }
        }
        .padding(.horizontal).padding(.top, 10)
    }

    @ViewBuilder
    private var mailBodyPanel: some View {
        if bodyText.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Chargement du corps")
            }
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(bodyText)
                    .font(.system(.body, design: .serif))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var actionBar: some View {
        HStack {
            Button(action: {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(bodyText, forType: .string)
            }) {
                Label("Copier le corps", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if let snip = selected {
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "message://%3c\(snip.messageId)%3e") ?? URL(fileURLWithPath: "/"))
                }) {
                    Label("Ouvrir dans Mail", systemImage: "envelope.open")
                }
                .buttonStyle(.bordered)
            }

            Button(action: { Task { await saveSelectedMail() } }) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Ajouter au projet", systemImage: "plus.square.on.square")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected == nil || selectedProject == nil || isSaving)

            Button(action: { Task { await loadAttachmentsForSelectedMail() } }) {
                if isLoadingAttachments {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Pièces jointes", systemImage: "paperclip")
                }
            }
            .buttonStyle(.bordered)
            .disabled(selected == nil || isLoadingAttachments)

            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder
    private var savedSourcesPanel: some View {
        if let selectedProject {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sources mail du projet")
                    .font(.headline)

                if selectedProject.mails.isEmpty {
                    Text("Aucun mail enregistré pour ce projet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedProject.mails.sorted(by: { $0.dateReceived > $1.dateReceived })) { mail in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mail.subject.isEmpty ? "(sans sujet)" : mail.subject)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                    Text(mail.sender)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Label("\(mail.chunks.count) chunk(s)", systemImage: "sparkles")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 220, alignment: .leading)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Load

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            loadedSnippets = try await MailService.listRecent(limit: 500, search: "", mailbox: selectedMailbox)
                .sorted(by: { $0.dateReceived > $1.dateReceived })
            applyLocalSearch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyLocalSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            snippets = loadedSnippets
            return
        }

        snippets = loadedSnippets.filter { snip in
            snip.subject.localizedCaseInsensitiveContains(query)
                || snip.sender.localizedCaseInsensitiveContains(query)
                || snip.preview.localizedCaseInsensitiveContains(query)
                || snip.mailbox.localizedCaseInsensitiveContains(query)
                || snip.accountName.localizedCaseInsensitiveContains(query)
        }
    }

    private func select(_ snip: MailSnippet) {
        selected = snip
        bodyText = snip.body ?? ""
        availableAttachments = []
        selectedAttachmentIDs = []
        errorMessage = nil
        if bodyText.isEmpty {
            Task { await loadBody(for: snip) }
        }
    }

    private func loadAttachmentsForSelectedMail() async {
        guard let snip = selected else { return }
        isLoadingAttachments = true
        defer { isLoadingAttachments = false }

        do {
            availableAttachments = try await MailService.saveAttachments(
                messageId: snip.messageId,
                accountName: snip.accountName,
                mailbox: snip.mailbox
            )
            selectedAttachmentIDs = Set(availableAttachments.map(\.id))
            if availableAttachments.isEmpty {
                saveStatus = "Aucune pièce jointe trouvée"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMailboxesAndReload() async {
        do {
            mailboxes = try await MailService.listMailboxes()
            if selectedMailbox == nil {
                selectedMailbox = mailboxes.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
    }

    private func loadBody(for snip: MailSnippet) async {
        do {
            let text = try await MailService.fetchBody(
                messageId: snip.messageId,
                accountName: snip.accountName,
                mailbox: snip.mailbox
            )
            bodyText = text
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSelectedMail() async {
        guard let snip = selected, let project = selectedProject else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let body = bodyText.isEmpty
                ? try await MailService.fetchBody(messageId: snip.messageId, accountName: snip.accountName, mailbox: snip.mailbox)
                : bodyText
            if availableAttachments.isEmpty {
                availableAttachments = try await MailService.saveAttachments(messageId: snip.messageId, accountName: snip.accountName, mailbox: snip.mailbox)
                selectedAttachmentIDs = Set(availableAttachments.map(\.id))
            }
            let attachments = availableAttachments.isEmpty
                ? try await MailService.saveAttachments(messageId: snip.messageId, accountName: snip.accountName, mailbox: snip.mailbox)
                : selectedAttachments
            bodyText = body
            let result = try await ProjectMailStore.save(snippet: snip, body: body, attachments: attachments, to: project, context: context)
            saveStatus = result.wasInserted
                ? "Source mail ajoutée à \(project.name)"
                : "Source mail mise à jour dans \(project.name)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
