//
//  VersioningDetector.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct VersioningDetector: EditDetectionStrategy, Sendable {
    nonisolated let detectionMethod: EditStatus.DetectionMethod = .versioning

    nonisolated init() {}

    nonisolated func detect(for rawFile: URL, in directory: URL) async -> [URL] {
        let basename = rawFile.deletingPathExtension().lastPathComponent
        var detectedVariants: [URL] = []

        // Patterns to check:
        // - {basename}-2.jpg, {basename}-3.jpg, etc.
        // - {basename}_v2.jpg, {basename}_v3.jpg, etc.
        // - {basename} 2.jpg, {basename} 3.jpg, etc. (with space)

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
            // Check if it's a regular file
            guard let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegularFile else {
                continue
            }

            let filename = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            // Only check edited file types
            guard PhotoFileType.editedExtensions.contains(ext) else {
                continue
            }

            // Check for various versioning patterns
            let patterns = [
                "^\(NSRegularExpression.escapedPattern(for: basename))-\\d+$",  // basename-2
                "^\(NSRegularExpression.escapedPattern(for: basename))_v\\d+$", // basename_v2
                "^\(NSRegularExpression.escapedPattern(for: basename)) \\d+$"   // basename 2
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)) != nil {
                    detectedVariants.append(fileURL)
                    break
                }
            }
        }

        return detectedVariants
    }
}
