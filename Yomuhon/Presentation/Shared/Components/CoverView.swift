//
//  CoverView.swift
//  Yomuhon
//

import SwiftUI
import Foundation

struct CoverView: View {
    let title: String
    var imageURL: URL?
    var cornerRadius: CGFloat = 16

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let size = safeCoverSize(proxy.size)

            ZStack(alignment: .bottomLeading) {
                coverBackground
                    .frame(width: size.width, height: size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.74)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: size.width, height: size.height)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Spacer()

                    if imageURL == nil {
                        Label("cover.noCover", systemImage: "photo")
                            .font(YomuhonTypography.captionMedium)
                            .foregroundColor(.white.opacity(0.74))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                }
                .padding(min(12, max(7, size.width * 0.11)))
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                .clipped()
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .clipped()
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var coverBackground: some View {
        if let imageURL {
            RemoteCoverImageView(url: imageURL) {
                generatedCover
            }
        } else {
            generatedCover
        }
    }

    private var generatedCover: some View {
        ZStack {
            theme.secondaryBackground.opacity(theme.id == .ink ? 0.74 : 1.0)

            VStack(spacing: YomuhonSpacing.small) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(theme.textSecondary.opacity(0.56))

                Text("cover.noCover")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary.opacity(0.74))
                    .lineLimit(1)
            }
            .padding(YomuhonSpacing.small)
        }
    }

    private var coverSkeleton: some View {
        YomuhonSkeletonBlock(cornerRadius: cornerRadius)
    }

    private func safeCoverSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }

    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.10, green: 0.14, blue: 0.22), Color(red: 0.35, green: 0.44, blue: 0.58)],
            [Color(red: 0.17, green: 0.09, blue: 0.10), Color(red: 0.58, green: 0.29, blue: 0.25)],
            [Color(red: 0.09, green: 0.18, blue: 0.13), Color(red: 0.36, green: 0.62, blue: 0.44)],
            [Color(red: 0.22, green: 0.10, blue: 0.22), Color(red: 0.62, green: 0.40, blue: 0.56)],
            [Color(red: 0.20, green: 0.16, blue: 0.10), Color(red: 0.62, green: 0.50, blue: 0.36)]
        ]
        return palettes[abs(title.hashValue) % palettes.count]
    }

    private var initials: String {
        title.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}


private struct RemoteCoverImageView<Placeholder: View>: View {
    let url: URL
    let placeholder: () -> Placeholder

    @StateObject private var loader = RemoteCoverImageLoader()

    init(url: URL, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if loader.isLoading {
                YomuhonSkeletonBlock(cornerRadius: 0)
            } else {
                placeholder()
            }
        }
        .onAppear {
            loader.load(url: url)
        }
        .onChange(of: url) { newURL in
            loader.load(url: newURL)
        }
    }
}

private final class RemoteCoverImageLoader: ObservableObject {
    @Published var image: Image?
    @Published var isLoading = false

    // Checking the on-disk cache was previously done synchronously on the
    // main thread (from .onAppear), which meant a burst of visible cover
    // cells scrolling into view could each block the UI with a file read
    // and image decode. Do that lookup on a background queue instead.
    private static let diskCacheQueue = DispatchQueue(
        label: "com.yomuhon.cover-disk-cache",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var task: URLSessionDataTask?
    private var currentURL: URL?

    func load(url: URL) {
        guard currentURL != url else {
            return
        }

        currentURL = url
        image = nil
        isLoading = true
        task?.cancel()

        Self.diskCacheQueue.async { [weak self] in
            let cachedImage = Self.cachedImage(for: url)

            DispatchQueue.main.async {
                guard let self, self.currentURL == url else {
                    return
                }

                if let cachedImage {
                    self.image = cachedImage
                    self.isLoading = false
                    return
                }

                self.load(url: url, referers: Self.referers(for: url))
            }
        }
    }

    private func load(url: URL, referers: [String?]) {
        var remainingReferers = referers

        let referer = remainingReferers.isEmpty ? nil : remainingReferers.removeFirst()
        var request = URLRequest(url: url)

        if let config = Self.sourceConfig(for: url) {
            for (key, value) in config.network?.headers ?? [:] {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 Yomuhon/1.0", forHTTPHeaderField: "User-Agent")
        }

        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let startedAt = Date()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            let loadedImage = data.flatMap(Self.platformImage(from:))

            if loadedImage != nil, let data {
                Self.cache(data: data, for: url)
            }

            if loadedImage == nil, !remainingReferers.isEmpty {
                DispatchQueue.main.async {
                    guard self?.currentURL == url else {
                        return
                    }

                    self?.load(url: url, referers: remainingReferers)
                }
                return
            }

            if let sourceID = Self.unambiguousSourceID(for: url) {
                if loadedImage != nil {
                    SourceMetricsStore.shared.recordSuccess(
                        sourceID: sourceID,
                        operation: .image,
                        latency: Date().timeIntervalSince(startedAt)
                    )
                } else if !Self.isCancellation(error) {
                    SourceMetricsStore.shared.recordFailure(
                        sourceID: sourceID,
                        operation: .image
                    )
                }
            }

            DispatchQueue.main.async {
                guard self?.currentURL == url else {
                    return
                }

                self?.image = loadedImage
                self?.isLoading = false
            }
        }

        task?.resume()
    }

    private static func referers(for url: URL) -> [String?] {
        var candidates: [String?] = []

        if let config = sourceConfig(for: url) {
            let value = config.baseURL.absoluteString
            candidates.append(value.hasSuffix("/") ? value : value + "/")
        }

        if let origin = originString(for: url) {
            candidates.append(origin)
        }
        candidates.append(nil)

        var seen = Set<String>()
        return candidates.filter { value in
            guard let value else { return true }
            return seen.insert(value).inserted
        }
    }

    private static func sourceConfig(for url: URL) -> DeclarativeSourceConfig? {
        sourceConfigs(for: url).first
    }

    private static func unambiguousSourceID(for url: URL) -> String? {
        let sourceIDs = Set(sourceConfigs(for: url).map(\.id))
        guard sourceIDs.count == 1 else { return nil }
        return sourceIDs.first
    }

    private static func sourceConfigs(for url: URL) -> [DeclarativeSourceConfig] {
        guard let host = url.host?.lowercased() else { return [] }
        return DeclarativeRemoteConfigLoader.availableConfigs().filter { config in
            config.allowedDomains.contains { domain in
                let normalized = domain.lowercased()
                return host == normalized || host.hasSuffix("." + normalized)
            }
        }
    }

    private static func isCancellation(_ error: Error?) -> Bool {
        guard let error = error as? URLError else { return false }
        return error.code == .cancelled
    }

    private static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let origin = components.url?.absoluteString else { return nil }
        return origin.hasSuffix("/") ? origin : origin + "/"
    }

    private static func cachedImage(for url: URL) -> Image? {
        guard let fileURL = cacheFileURL(for: url),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return platformImage(from: data)
    }

    private static func cache(data: Data, for url: URL) {
        guard let fileURL = cacheFileURL(for: url) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }

    private static func cacheFileURL(for url: URL) -> URL? {
        guard let directory = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("ImageCache", isDirectory: true)
        else {
            return nil
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(url.absoluteString.stableCacheFileName)
    }

    private static func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else {
            return nil
        }

        return Image(nsImage: image)
        #elseif canImport(UIKit)
        guard let image = UIImage(data: data) else {
            return nil
        }

        return Image(uiImage: image)
        #else
        return nil
        #endif
    }

    deinit {
        task?.cancel()
    }
}

private extension String {
    var stableCacheFileName: String {
        let allowed = CharacterSet.alphanumerics

        let sanitized = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar).lowercased() : "-"
        }
        .joined()
        .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }
}

