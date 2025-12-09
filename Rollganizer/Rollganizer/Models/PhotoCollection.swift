//
//  PhotoCollection.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct PhotoCollection: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    var photos: [Photo]
    var children: [PhotoCollection] // Child collections (subdirectories)
    var progress: CollectionProgress
    var parentURL: URL? // Track parent directory for hierarchy
    var isRootFolder: Bool // True if this is a user-selected root folder
    var jpegClassification: EditStatus.JPEGClassification? // Classification for JPEG-only folders

    nonisolated init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        photos: [Photo] = [],
        children: [PhotoCollection] = [],
        parentURL: URL? = nil,
        isRootFolder: Bool = false,
        jpegClassification: EditStatus.JPEGClassification? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.photos = photos
        self.children = children
        self.parentURL = parentURL
        self.isRootFolder = isRootFolder
        self.jpegClassification = jpegClassification

        // Calculate progress including children
        self.progress = Self.calculateProgress(photos: photos, children: children)
    }

    mutating func updateProgress() {
        self.progress = Self.calculateProgress(photos: photos, children: children)
    }
    
    /// Calculate progress including all children recursively
    private nonisolated static func calculateProgress(photos: [Photo], children: [PhotoCollection]) -> CollectionProgress {
        var totalPhotos = photos.count
        var editedPhotos = photos.filter { $0.editStatus.isEdited }.count
        
        // Recursively add children's progress
        for child in children {
            totalPhotos += child.progress.totalPhotos
            editedPhotos += child.progress.editedPhotos
        }
        
        return CollectionProgress(totalPhotos: totalPhotos, editedPhotos: editedPhotos)
    }
    
    /// Calculate the depth level based on parent relationships
    func hierarchyLevel() -> Int {
        var level = 0
        let current = self

        while current.parentURL != nil {
            level += 1
            // In a proper tree, we'd traverse up, but we'll use isRootFolder as the base
            if current.isRootFolder {
                break
            }
            // This is a simplification - in practice, the tree structure handles this
            break
        }

        return level
    }
    
    /// Get all subdirectory URLs (flattened from children)
    var subDirectoryURLs: [URL] {
        return children.map { $0.url }
    }
    
    /// Check if this collection contains only standalone JPEGs (no RAWs)
    var hasOnlyStandaloneJPEGs: Bool {
        return !photos.isEmpty && photos.allSatisfy { photo in
            if case .standaloneJPEG = photo.editStatus {
                return true
            }
            return false
        }
    }
    
    /// Check if JPEGs need classification
    var needsJPEGClassification: Bool {
        return hasOnlyStandaloneJPEGs && jpegClassification == nil
    }
    
    /// Recursively flatten all collections in the tree
    func flattenedCollections() -> [PhotoCollection] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.flattenedCollections())
        }
        return result
    }
}
