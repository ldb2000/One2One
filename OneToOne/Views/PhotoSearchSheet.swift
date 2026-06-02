import SwiftUI
import AppKit

/// Sheet that searches for "<name> LinkedIn" via DuckDuckGo (default) or
/// Google Custom Search Engine (when API key + CX are configured).
/// Clicking a thumbnail downloads the full image and returns the data
/// via `onPick`.
struct PhotoSearchSheet: View {

    /// Requête initiale pré-remplie ; déclenche une recherche automatique si non vide.
    let initialQuery: String
    /// Clé API Google ; si vide (ou CX absent) la recherche bascule sur DuckDuckGo.
    let googleAPIKey: String
    /// Identifiant du Custom Search Engine Google associé à `googleAPIKey`.
    let googleCSEID: String
    /// Appelé avec les données binaires brutes de l'image choisie (sans nom de
    /// fichier ni URL d'origine) ; le sheet se ferme juste après l'appel.
    let onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isLoading: Bool = false
    @State private var results: [LinkedInPhotoSearch.ImageResult] = []
    @State private var errorMessage: String?
    @State private var providerLabel: String = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Rechercher une photo")
                    .font(.headline)
                if !providerLabel.isEmpty {
                    Text("via \(providerLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Fermer") { dismiss() }
            }

            HStack {
                TextField("Nom à rechercher…", text: $query, onCommit: search)
                    .textFieldStyle(.roundedBorder)
                Button(action: search) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Rechercher", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            if results.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Aucun résultat",
                    systemImage: "photo.on.rectangle",
                    description: Text("Lancez une recherche pour voir les photos disponibles.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(results) { result in
                            PhotoSearchThumbnail(result: result) {
                                pick(result)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 480)
        .onAppear {
            query = initialQuery
            if !initialQuery.isEmpty { search() }
        }
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let r = try await LinkedInPhotoSearch.searchImages(
                    name: trimmed,
                    googleAPIKey: googleAPIKey,
                    googleCSEID: googleCSEID
                )
                await MainActor.run {
                    results = r
                    providerLabel = r.first?.provider.rawValue ?? ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    results = []
                    isLoading = false
                }
            }
        }
    }

    private func pick(_ result: LinkedInPhotoSearch.ImageResult) {
        Task {
            do {
                let data = try await LinkedInPhotoSearch.downloadImage(at: result.contentURL)
                await MainActor.run {
                    onPick(data)
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

/// Vignette d'un résultat : charge la miniature en tâche de fond et déclenche
/// `onTap` au clic (le parent télécharge alors l'image pleine résolution).
private struct PhotoSearchThumbnail: View {
    let result: LinkedInPhotoSearch.ImageResult
    /// Action déclenchée au clic sur la vignette.
    let onTap: () -> Void

    @State private var image: NSImage?
    @State private var loading: Bool = true

    var body: some View {
        Button(action: onTap) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            .clipped()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .task { await load() }
    }

    private func load() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: result.thumbnailURL)
            let img = NSImage(data: data)
            await MainActor.run {
                self.image = img
                self.loading = false
            }
        } catch {
            await MainActor.run { self.loading = false }
        }
    }
}
