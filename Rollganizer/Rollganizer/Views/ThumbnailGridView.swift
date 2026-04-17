//
//  ThumbnailGridView.swift
//  Rollganizer
//

import SwiftUI
import AppKit
import QuickLook

// MARK: - Thumbnail Colors
private enum ThumbnailColors {
    static let edited = Color.green
    static let unedited = Color(nsColor: .tertiaryLabelColor)
    static let inCamera = Color.orange
    static let sooc = Color.blue
    static let raw = Color.accentColor
}

/// Shared thumbnail cache with memory limits
@MainActor
class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [URL: NSImage] = [:]
    private let maxCacheSize = 100 // Maximum number of thumbnails to cache
    private var accessOrder: [URL] = [] // Track access for LRU eviction

    func image(for url: URL) -> NSImage? {
        if let image = cache[url] {
            // Move to end (most recently used)
            accessOrder.removeAll { $0 == url }
            accessOrder.append(url)
            return image
        }
        return nil
    }

    func setImage(_ image: NSImage, for url: URL) {
        // Evict oldest if cache is full
        if cache.count >= maxCacheSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }

        cache[url] = image
        accessOrder.append(url)
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}

struct ThumbnailGridView: View {
    let photos: [Photo]
    let rootFolderURL: URL

    @State private var selectedPhoto: Photo?
    @State private var quickLookURL: URL?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("This collection doesn't contain any photos")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(photos) { photo in
                        ThumbnailItemView(
                            photo: photo,
                            rootFolderURL: rootFolderURL,
                            isSelected: selectedPhoto?.id == photo.id
                        )
                        .onTapGesture {
                            selectedPhoto = photo
                            quickLookURL = photo.url
                        }
                    }
                }
                .padding()
            }
        }
        .quickLookPreview($quickLookURL)
    }
}

struct ThumbnailItemView: View {
    let photo: Photo
    let rootFolderURL: URL
    let isSelected: Bool

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 150)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if isLoading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 150, height: 150)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 150, height: 150)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        }
                }

                // Badges overlay
                VStack {
                    HStack {
                        // XMP sidecar indicator
                        if case .edited(let method) = photo.editStatus, method == .xmpSidecar {
                            BadgePill(icon: "doc.text.fill", color: ThumbnailColors.edited)
                                .help("XMP Sidecar")
                        }
                        Spacer()
                        // Edit status badge
                        editStatusBadge
                    }
                    Spacer()
                }
                .padding(6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.5) : .clear), lineWidth: isSelected ? 3 : 2)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }

            // File name
            Text(photo.fileName)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .task {
            await loadThumbnail()
        }
        .onDisappear {
            thumbnailImage = nil
        }
    }

    @ViewBuilder
    private var editStatusBadge: some View {
        switch photo.editStatus {
        case .edited:
            BadgePill(icon: "checkmark", color: ThumbnailColors.edited)
        case .unedited:
            if photo.fileType == .raw {
                BadgePill(icon: "r.circle", color: ThumbnailColors.raw)
            }
        case .standaloneJPEG(let classification):
            switch classification {
            case .editedExport:
                BadgePill(icon: "checkmark", color: ThumbnailColors.edited)
            case .finalSOOC:
                BadgePill(icon: "checkmark", color: ThumbnailColors.sooc)
            case .needsEditing:
                EmptyView()
            }
        case .inCameraJPEG:
            BadgePill(icon: "camera", color: ThumbnailColors.inCamera)
        }
    }

    private func loadThumbnail() async {
        defer { isLoading = false }

        // Determine which URL to use for the thumbnail
        // For XMP sidecars, use the RAW file; for actual edited images, use the edited variant
        let thumbnailURL: URL
        if case .edited(let method) = photo.editStatus, method == .xmpSidecar {
            // XMP sidecars are metadata files, not images - use the RAW file for thumbnail
            thumbnailURL = photo.url
        } else if !photo.editedVariants.isEmpty {
            // Use the first edited variant (e.g., exported JPEG/TIFF)
            // Filter out XMP files just in case
            if let imageVariant = photo.editedVariants.first(where: { !$0.pathExtension.lowercased().contains("xmp") }) {
                thumbnailURL = imageVariant
            } else {
                thumbnailURL = photo.url
            }
        } else {
            // Fall back to the original RAW file
            thumbnailURL = photo.url
        }

        // Check cache first
        if let cachedImage = ThumbnailCache.shared.image(for: thumbnailURL) {
            thumbnailImage = cachedImage
            return
        }

        // Access the root folder with security scope
        guard rootFolderURL.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource for root: \(rootFolderURL.path)")
            return
        }
        defer { rootFolderURL.stopAccessingSecurityScopedResource() }

        // Load image on background thread
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            // Try to load the image source
            guard let imageSource = CGImageSourceCreateWithURL(thumbnailURL as CFURL, nil) else {
                return nil
            }

            // Create thumbnail with options to reduce memory usage
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 300
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                return nil
            }

            // Convert CGImage to NSImage
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            return NSImage(cgImage: cgImage, size: size)
        }.value

        if let image = image {
            ThumbnailCache.shared.setImage(image, for: thumbnailURL)
            thumbnailImage = image
        }
    }
}

// MARK: - Badge Pill
struct BadgePill: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(color, in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}
