//
//  RootViewModel.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation
import AppKit
import Combine

@MainActor
class RootViewModel: ObservableObject {
    @Published var selectedCollection: PhotoCollection?
    @Published var rootFolders: [PhotoCollection] = [] // User-selected root folders with full tree
    @Published var isScanning: Bool = false
    @Published var scanProgress: ScanProgress?
    @Published var errorMessage: String?
    @Published var pendingJPEGCollection: PhotoCollection?
    @Published var pendingJPEGFolderName: String? // Track which folder needs classification

    private let scanner = PhotoScanner()
    private let bookmarkManager = BookmarkManager.shared

    init() {
        // Load saved root folders on launch
        Task {
            await loadSavedRootFolders()
        }
    }

    /// Load all saved root folders from bookmarks
    func loadSavedRootFolders() async {
        let urls = bookmarkManager.loadAllRootFolders()

        for url in urls {
            do {
                try await bookmarkManager.accessSecuredResourceAsync(url) {
                    let collection = try await scanner.scanDirectoryTree(url, isRootFolder: true)
                    rootFolders.append(collection)
                }
            } catch {
                print("Failed to load root folder \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// Opens a folder picker and scans the selected directory as a new root folder
    func selectFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder containing photos to scan"

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            return
        }

        await addRootFolder(url)
    }

    /// Adds a new root folder and scans its entire tree
    func addRootFolder(_ url: URL) async {
        // Check if already added
        if rootFolders.contains(where: { $0.url == url }) {
            errorMessage = "This folder is already added"
            return
        }

        isScanning = true
        errorMessage = nil

        do {
            // Save bookmark for persistence
            try bookmarkManager.saveRootFolder(url)

            // Scan the entire directory tree
            try await bookmarkManager.accessSecuredResourceAsync(url) {
                let collection = try await scanner.scanDirectoryTree(url, isRootFolder: true)

                // Check if there are JPEG-only folders that need classification
                let jpegOnlyCollections = collection.flattenedCollections().filter { $0.needsJPEGClassification }

                if let firstJPEGCollection = jpegOnlyCollections.first {
                    // For now, prompt for the first one we find
                    // The user will only be asked when they open a folder, not for every subdirectory
                    pendingJPEGCollection = firstJPEGCollection
                }

                rootFolders.append(collection)
                selectedCollection = collection
            }
        } catch {
            errorMessage = "Failed to scan directory: \(error.localizedDescription)"
        }

        isScanning = false
    }

    /// Removes a root folder
    func removeRootFolder(_ collection: PhotoCollection) {
        guard collection.isRootFolder else { return }

        // Remove bookmark
        bookmarkManager.removeRootFolder(collection.url)

        // Remove from list
        rootFolders.removeAll { $0.id == collection.id }

        // Clear selection if this was selected
        if selectedCollection?.id == collection.id {
            selectedCollection = rootFolders.first
        }
    }

    /// Re-scans a specific collection (updates it in the tree)
    func refresh() async {
        guard let currentCollection = selectedCollection else {
            return
        }

        // Find the root folder that contains this collection
        if let rootFolderIndex = rootFolders.firstIndex(where: { root in
            root.flattenedCollections().contains(where: { $0.id == currentCollection.id })
        }) {
            let rootURL = rootFolders[rootFolderIndex].url

            isScanning = true
            errorMessage = nil

            do {
                try await bookmarkManager.accessSecuredResourceAsync(rootURL) {
                    // Re-scan the entire root folder tree
                    let updatedRoot = try await scanner.scanDirectoryTree(rootURL, isRootFolder: true)
                    rootFolders[rootFolderIndex] = updatedRoot

                    // Try to find and re-select the corresponding collection in the updated tree
                    if let updatedCollection = updatedRoot.flattenedCollections().first(where: { $0.url == currentCollection.url }) {
                        selectedCollection = updatedCollection
                    } else {
                        selectedCollection = updatedRoot
                    }
                }
            } catch {
                errorMessage = "Failed to refresh: \(error.localizedDescription)"
            }

            isScanning = false
        }
    }

    /// Classifies JPEGs in a pending collection
    func classifyJPEGs(as classification: EditStatus.JPEGClassification) {
        guard let collection = pendingJPEGCollection else { return }

        // Update collection with classification
        var updated = collection
        updated.jpegClassification = classification

        // Update all photos with the classification
        updated.photos = updated.photos.map { photo in
            var updatedPhoto = photo
            if case .standaloneJPEG = photo.editStatus {
                updatedPhoto.editStatus = .standaloneJPEG(classification: classification)
            }
            return updatedPhoto
        }

        // Recalculate progress
        updated.updateProgress()

        // Find and update this collection in the tree
        for (rootIndex, rootFolder) in rootFolders.enumerated() {
            if var updatedRoot = updateCollectionInTree(rootFolder, targetID: collection.id, newCollection: updated) {
                updatedRoot.updateProgress() // Recalculate root progress
                rootFolders[rootIndex] = updatedRoot
                break
            }
        }

        // Clear pending
        pendingJPEGCollection = nil
    }

    /// Recursively updates a collection in the tree
    private func updateCollectionInTree(_ collection: PhotoCollection, targetID: UUID, newCollection: PhotoCollection) -> PhotoCollection? {
        if collection.id == targetID {
            return newCollection
        }

        var updated = collection
        var childrenUpdated = false

        for (index, child) in collection.children.enumerated() {
            if let updatedChild = updateCollectionInTree(child, targetID: targetID, newCollection: newCollection) {
                updated.children[index] = updatedChild
                childrenUpdated = true
                break
            }
        }

        return childrenUpdated ? updated : nil
    }

    /// Dismisses the JPEG classification prompt without adding the collection
    func dismissJPEGClassification() {
        pendingJPEGCollection = nil
    }
}
