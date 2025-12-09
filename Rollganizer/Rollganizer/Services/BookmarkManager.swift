//
//  BookmarkManager.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/8/25.
//

import Foundation

/// Manages security-scoped bookmarks for persistent folder access across app launches
class BookmarkManager {
    static let shared = BookmarkManager()

    private let userDefaults = UserDefaults.standard
    private let bookmarksKey = "savedFolderBookmarks"

    private init() {}

    // MARK: - Bookmark Storage

    /// Save a bookmark for a folder URL
    func createBookmark(for url: URL) throws -> Data {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return bookmarkData
    }

    /// Resolve a bookmark to get the URL
    func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            // Bookmark is stale, recreate it
            let newBookmarkData = try createBookmark(for: url)
            // Update stored bookmark
            updateBookmark(for: url, with: newBookmarkData)
        }

        return url
    }

    // MARK: - Root Folders Management

    /// Save a root folder bookmark
    func saveRootFolder(_ url: URL) throws {
        let bookmarkData = try createBookmark(for: url)

        var savedBookmarks = loadAllBookmarks()
        savedBookmarks[url.path] = bookmarkData

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(savedBookmarks)
        userDefaults.set(encoded, forKey: bookmarksKey)
    }

    /// Remove a root folder bookmark
    func removeRootFolder(_ url: URL) {
        var savedBookmarks = loadAllBookmarks()
        savedBookmarks.removeValue(forKey: url.path)

        if let encoded = try? JSONEncoder().encode(savedBookmarks) {
            userDefaults.set(encoded, forKey: bookmarksKey)
        }
    }

    /// Load all saved root folder bookmarks
    func loadAllBookmarks() -> [String: Data] {
        guard let data = userDefaults.data(forKey: bookmarksKey) else {
            return [:]
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([String: Data].self, from: data)) ?? [:]
    }

    /// Get all saved root folder URLs
    func loadAllRootFolders() -> [URL] {
        let bookmarks = loadAllBookmarks()
        var urls: [URL] = []

        for (_, bookmarkData) in bookmarks {
            if let url = try? resolveBookmark(bookmarkData) {
                urls.append(url)
            }
        }

        return urls
    }

    /// Update a bookmark (used when bookmark becomes stale)
    private func updateBookmark(for url: URL, with bookmarkData: Data) {
        var savedBookmarks = loadAllBookmarks()
        savedBookmarks[url.path] = bookmarkData

        if let encoded = try? JSONEncoder().encode(savedBookmarks) {
            userDefaults.set(encoded, forKey: bookmarksKey)
        }
    }

    // MARK: - Security-Scoped Resource Access

    /// Access a security-scoped resource safely
    func accessSecuredResource<T>(_ url: URL, work: () throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        return try work()
    }

    /// Access a security-scoped resource safely (async version)
    func accessSecuredResourceAsync<T>(_ url: URL, work: () async throws -> T) async throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        return try await work()
    }

    enum BookmarkError: Error {
        case accessDenied
        case invalidBookmark
        case bookmarkStale
    }
}
