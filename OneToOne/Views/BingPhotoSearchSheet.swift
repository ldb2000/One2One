import SwiftUI
import AppKit

/// Sheet that searches Bing Image API for "<name> LinkedIn" and presents
/// a thumbnail grid. Clicking a thumbnail downloads the full image and
/// returns the data via `onPick`.
struct BingPhotoSearchSheet: View {

    let initialQuery: String
    let apiKey: String
    let onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isLoading: Bool = false
    @State private var results: [LinkedInPhotoSearch.BingResult] = []
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Rechercher une photo (Bing + LinkedIn)")
                    .font(.headline)
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
                            BingThumbnail(result: result) {
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
                let r = try await LinkedInPhotoSearch.bingImageSearch(name: trimmed, key: apiKey)
                await MainActor.run {
                    results = r
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

    private func pick(_ result: LinkedInPhotoSearch.BingResult) {
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

private struct BingThumbnail: View {
    let result: LinkedInPhotoSearch.BingResult
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
