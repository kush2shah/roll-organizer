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
    @Published var rootFolders: [PhotoCollection] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: ScanProgress?
    @Published var errorMessage: String?
    @Published var pendingJPEGCollection: PhotoCollection?
    @Published var pendingJPEGFolderName: String?

    private lazy var scanner = PhotoScanner()
    private let bookmarkManager = BookmarkManager.shared

    nonisolated init() {
        // Nonisolated init to allow creation from any context
    }

    /// Load all saved root folders from bookmarks
    func loadSavedRootFolders() async {
        let urls = bookmarkManager.loadAllRootFolders()

        for url in urls {
            do {
                try await bookmarkManager.accessSecuredResourceAsync(url) {
                    let collection = try await scanner.scanDirectoryTree(url, isRootFolder: true) { [weak self] progress in
                        Task { @MainActor in
                            self?.scanProgress = progress
                        }
                    }
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
        scanProgress = ScanProgress(currentFolder: url.lastPathComponent, foldersScanned: 0, totalFolders: nil)
        errorMessage = nil

        do {
            // Save bookmark for persistence
            try bookmarkManager.saveRootFolder(url)

            // Scan the entire directory tree with progress updates
            try await bookmarkManager.accessSecuredResourceAsync(url) {
                let collection = try await scanner.scanDirectoryTree(url, isRootFolder: true) { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = progress
                    }
                }

                rootFolders.append(collection)
                selectedCollection = collection

                // IMPORTANT: Set isScanning to false BEFORE showing JPEG classification dialog
                isScanning = false
                scanProgress = nil

                // Only check the root folder itself for JPEG classification
                // Subfolders will be prompted when the user navigates to them
                if collection.needsJPEGClassification {
                    pendingJPEGCollection = collection
                    pendingJPEGFolderName = collection.name
                }
            }
        } catch {
            errorMessage = "Failed to scan directory: \(error.localizedDescription)"
            isScanning = false
            scanProgress = nil
        }
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
            scanProgress = ScanProgress(currentFolder: rootURL.lastPathComponent, foldersScanned: 0, totalFolders: nil)
            errorMessage = nil

            do {
                try await bookmarkManager.accessSecuredResourceAsync(rootURL) {
                    // Re-scan the entire root folder tree
                    let updatedRoot = try await scanner.scanDirectoryTree(rootURL, isRootFolder: true) { [weak self] progress in
                        Task { @MainActor in
                            self?.scanProgress = progress
                        }
                    }
                    rootFolders[rootFolderIndex] = updatedRoot

                    // Try to find and re-select the corresponding collection in the updated tree
                    if let updatedCollection = updatedRoot.flattenedCollections().first(where: { $0.url == currentCollection.url }) {
                        selectedCollection = updatedCollection
                    } else {
                        selectedCollection = updatedRoot
                    }

                    // Set isScanning to false before showing any dialogs
                    isScanning = false
                    scanProgress = nil
                }
            } catch {
                errorMessage = "Failed to refresh: \(error.localizedDescription)"
                isScanning = false
                scanProgress = nil
            }
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
        pendingJPEGFolderName = nil
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
        pendingJPEGFolderName = nil
    }

    /// Get the root folder URL for a given collection
    func getRootFolderURL(for collection: PhotoCollection?) -> URL? {
        guard let collection = collection else { return nil }

        // Find the root folder that contains this collection
        for rootFolder in rootFolders {
            if rootFolder.id == collection.id || rootFolder.flattenedCollections().contains(where: { $0.id == collection.id }) {
                return rootFolder.url
            }
        }

        return nil
    }

    /// Get the root folder URL for the currently selected collection
    var selectedCollectionRootURL: URL? {
        getRootFolderURL(for: selectedCollection)
    }
}
