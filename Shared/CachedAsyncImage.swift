import SwiftUI
import UIKit

/// Ported from keepMovin's Discover / library image loader.
struct CachedAsyncImage: View {
    let url: URL?
    let localURL: URL?
    let placeholder: AnyView

    init(
        url: URL?,
        localURL: URL? = nil,
        @ViewBuilder placeholder: () -> some View = {
            Color.gray.opacity(0.3).overlay(
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundColor(.gray)
            )
        }
    ) {
        self.url = url
        self.localURL = localURL
        self.placeholder = AnyView(placeholder())
    }

    var body: some View {
        if let url {
            CachedAsyncImageInner(url: url, localURL: localURL, placeholder: placeholder)
        } else {
            placeholder
        }
    }
}

private struct CachedAsyncImageInner: View {
    let url: URL
    let localURL: URL?
    let placeholder: AnyView

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                placeholder
            }
        }
        .task(id: url) { await loadImage() }
    }

    private func loadImage() async {
        guard !isLoading else { return }
        isLoading = true

        if let localURL,
           let data = try? Data(contentsOf: localURL),
           let localImage = UIImage(data: data) {
            withAnimation { self.image = localImage }
            isLoading = false
            return
        }

        if let cached = await ImageCache.shared.image(for: url) {
            withAnimation { self.image = cached }
            isLoading = false
            return
        }

        if let downloaded = await ImageCache.shared.loadImage(from: url) {
            await MainActor.run {
                withAnimation { self.image = downloaded }
            }
        }
        isLoading = false
    }
}

actor ImageCache {
    static let shared = ImageCache()
    private var memory: [URL: UIImage] = [:]

    func image(for url: URL) -> UIImage? { memory[url] }

    func loadImage(from url: URL) async -> UIImage? {
        if let cached = memory[url] { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memory[url] = image
            return image
        } catch {
            return nil
        }
    }
}
