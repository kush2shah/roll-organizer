//
//  PhotoScanner.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

actor PhotoScanner {
    private let detectionEngine: EditDetectionEngine
    
    init() {
        self.detectionEngine = EditDetectionEngine()
    }

    enum ScanError: Error {
        case directoryNotAccessible
        case invalidDirectory
    }

    /// Scans a directory for RAW photo files and detects their edit status.
    /// Non-recursive: only scans immediate directory contents.
    /// Tracks subdirectories for display but does not scan them.
    /// Scans a directory for RAW photo files and detects their edit status.
    /// Non-recursive: only scans immediate directory contents.
    /// Tracks subdirectories for display but does not scan them.
    func scanDirectory(_ url: URL) async throws -> PhotoCollection {
        let fileManager = FileManager.default

        // Verify the URL is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScanError.invalidDirectory
        }

        // Get directory contents (non-recursive)
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .typeIdentifierKey,
            .fileSizeKey,
            .isPackageKey,
            .isHiddenKey
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        ) else {
            throw ScanError.directoryNotAccessible
        }

        var rawFiles: [URL] = []
        var jpegFiles: [URL] = []

        // First pass: separate files from subdirectories
        for fileURL in contents {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))

            // Skip packages
            if resourceValues.isPackage == true {
                continue
            }

            // Skip directories
            if resourceValues.isDirectory == true {
                continue
            }

            // Check if it's a regular file
            guard resourceValues.isRegularFile == true else {
                continue
            }

            // Check file type
            let ext = fileURL.pathExtension.lowercased()
            if PhotoFileType.rawExtensions.contains(ext) {
                rawFiles.append(fileURL)
            } else if ["jpg", "jpeg"].contains(ext) {
                jpegFiles.append(fileURL)
            }
        }

        var photos: [Photo] = []
        
        // Second pass: detect edit status for each RAW file
        for rawFileURL in rawFiles {
            let (editStatus, variants, inCameraJPEGs) = await detectionEngine.detectEditStatus(
                for: rawFileURL,
                in: url
            )

            let photo = Photo(
                url: rawFileURL,
                fileName: rawFileURL.lastPathComponent,
                fileType: .raw,
                editStatus: editStatus,
                editedVariants: variants,
                inCameraJPEGs: inCameraJPEGs
            )
            photos.append(photo)
        }
        
        // If there are no RAW files but there are JPEGs, treat them as standalone JPEGs
        if rawFiles.isEmpty && !jpegFiles.isEmpty {
            for jpegFileURL in jpegFiles {
                let photo = Photo(
                    url: jpegFileURL,
                    fileName: jpegFileURL.lastPathComponent,
                    fileType: .jpeg,
                    editStatus: .standaloneJPEG(classification: .needsEditing),
                    editedVariants: [],
                    inCameraJPEGs: []
                )
                photos.append(photo)
            }
        }

        // Create and return the collection
        let collection = PhotoCollection(
            url: url,
            name: url.lastPathComponent,
            photos: photos
        )

        return collection
    }

    /// Recursively scans a directory and all subdirectories, building a tree structure.
    /// This is used when the user opens a root folder to show the entire hierarchy.
    func scanDirectoryTree(
        _ url: URL,
        parentURL: URL? = nil,
        isRootFolder: Bool = false,
        progressHandler: ((ScanProgress) -> Void)? = nil
    ) async throws -> PhotoCollection {
        // First pass: count total folders for progress tracking
        var totalFolderCount = 0
        if isRootFolder {
            totalFolderCount = await countSubdirectories(url)
        }

        var scannedCount = 0

        return try await scanDirectoryTreeRecursive(
            url,
            parentURL: parentURL,
            isRootFolder: isRootFolder,
            totalFolders: isRootFolder ? totalFolderCount : nil,
            scannedCount: &scannedCount,
            progressHandler: progressHandler
        )
    }

    /// Internal recursive scan with progress tracking
    private func scanDirectoryTreeRecursive(
        _ url: URL,
        parentURL: URL? = nil,
        isRootFolder: Bool = false,
        totalFolders: Int?,
        scannedCount: inout Int,
        progressHandler: ((ScanProgress) -> Void)?
    ) async throws -> PhotoCollection {
        // Report progress
        scannedCount += 1
        if let progressHandler = progressHandler {
            let progress = ScanProgress(
                currentFolder: url.lastPathComponent,
                foldersScanned: scannedCount,
                totalFolders: totalFolders
            )
            progressHandler(progress)
        }
        let fileManager = FileManager.default

        // Verify the URL is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScanError.invalidDirectory
        }

        // Get directory contents (non-recursive for this level)
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .typeIdentifierKey,
            .fileSizeKey,
            .isPackageKey,
            .isHiddenKey
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScanError.directoryNotAccessible
        }

        var rawFiles: [URL] = []
        var jpegFiles: [URL] = []
        var subDirectoryURLs: [URL] = []

        // First pass: separate files from subdirectories
        for fileURL in contents {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))

            // Skip packages
            if resourceValues.isPackage == true {
                continue
            }

            // Check if it's a directory
            if resourceValues.isDirectory == true {
                subDirectoryURLs.append(fileURL)
                continue
            }

            // Check if it's a regular file
            guard resourceValues.isRegularFile == true else {
                continue
            }

            // Check file type
            let ext = fileURL.pathExtension.lowercased()
            if PhotoFileType.rawExtensions.contains(ext) {
                rawFiles.append(fileURL)
            } else if ["jpg", "jpeg"].contains(ext) {
                jpegFiles.append(fileURL)
            }
        }

        var photos: [Photo] = []

        // Second pass: detect edit status for each RAW file
        for rawFileURL in rawFiles {
            let (editStatus, variants, inCameraJPEGs) = await detectionEngine.detectEditStatus(
                for: rawFileURL,
                in: url
            )

            let photo = Photo(
                url: rawFileURL,
                fileName: rawFileURL.lastPathComponent,
                fileType: .raw,
                editStatus: editStatus,
                editedVariants: variants,
                inCameraJPEGs: inCameraJPEGs
            )
            photos.append(photo)
        }

        // If there are no RAW files but there are JPEGs, treat them as standalone JPEGs
        if rawFiles.isEmpty && !jpegFiles.isEmpty {
            for jpegFileURL in jpegFiles {
                let photo = Photo(
                    url: jpegFileURL,
                    fileName: jpegFileURL.lastPathComponent,
                    fileType: .jpeg,
                    editStatus: .standaloneJPEG(classification: .needsEditing),
                    editedVariants: [],
                    inCameraJPEGs: []
                )
                photos.append(photo)
            }
        }

        // Recursively scan subdirectories
        var childCollections: [PhotoCollection] = []
        for subDirURL in subDirectoryURLs {
            do {
                let childCollection = try await scanDirectoryTreeRecursive(
                    subDirURL,
                    parentURL: url,
                    isRootFolder: false,
                    totalFolders: totalFolders,
                    scannedCount: &scannedCount,
                    progressHandler: progressHandler
                )
                childCollections.append(childCollection)
            } catch {
                // Skip directories that can't be accessed
                print("Failed to scan subdirectory \(subDirURL.lastPathComponent): \(error)")
            }
        }

        // Create and return the collection with children
        let collection = PhotoCollection(
            url: url,
            name: url.lastPathComponent,
            photos: photos,
            children: childCollections,
            parentURL: parentURL,
            isRootFolder: isRootFolder
        )

        return collection
    }

    /// Counts the total number of subdirectories recursively for progress tracking
    private func countSubdirectories(_ url: URL) async -> Int {
        let fileManager = FileManager.default
        var count = 1 // Count the root directory itself

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return count
        }

        for item in contents {
            guard let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                  resourceValues.isDirectory == true,
                  resourceValues.isPackage != true else {
                continue
            }

            count += await countSubdirectories(item)
        }

        return count
    }
}
