//
//  NamingConventionDetector.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct NamingConventionDetector: EditDetectionStrategy, Sendable {
    nonisolated let detectionMethod: EditStatus.DetectionMethod = .namingPattern

    nonisolated init() {}

    nonisolated func detect(for rawFile: URL, in directory: URL) async -> [URL] {
        let basename = rawFile.deletingPathExtension().lastPathComponent
        var detectedVariants: [URL] = []

        let fileManager = FileManager.default

        // Get all files in the directory
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        for fileURL in files {
            // Check if it's a regular file (NOT a directory)
            guard let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegularFile else {
                continue
            }

            let filename = fileURL.lastPathComponent.lowercased()
            let ext = fileURL.pathExtension.lowercased()

            // Only check edited file types
            guard PhotoFileType.editedExtensions.contains(ext) else {
                continue
            }

            // Check if filename contains the basename AND contains "edit"
            // CRITICAL: Only check filenames, never directory names
            if filename.contains(basename.lowercased()) && filename.contains("edit") {
                detectedVariants.append(fileURL)
            }
        }

        return detectedVariants
    }
}
