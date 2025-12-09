//
//  FormatConversionDetector.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct FormatConversionDetector: EditDetectionStrategy, Sendable {
    nonisolated let detectionMethod: EditStatus.DetectionMethod = .formatConversion

    nonisolated init() {}

    /// Detects converted files and in-camera JPEGs
    /// Returns: (editedVariants, inCameraJPEGs)
    nonisolated func detectWithInCameraCheck(for rawFile: URL, in directory: URL) async -> (edited: [URL], inCamera: [URL]) {
        let basename = rawFile.deletingPathExtension().lastPathComponent
        var editedVariants: [URL] = []
        var inCameraJPEGs: [URL] = []

        // Get the RAW file's modification date for comparison
        guard let rawModDate = try? rawFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return ([], [])
        }

        // Check for converted formats with the same basename
        for ext in PhotoFileType.editedExtensions {
            let convertedURL = directory.appendingPathComponent("\(basename).\(ext)")

            // Verify the file exists and is a regular file
            guard FileManager.default.fileExists(atPath: convertedURL.path) else {
                continue
            }

            // Verify it's actually an edited extension and not a RAW file
            let fileExt = convertedURL.pathExtension.lowercased()
            guard PhotoFileType.editedExtensions.contains(fileExt),
                  !PhotoFileType.rawExtensions.contains(fileExt) else {
                continue
            }

            // CRITICAL: Check if this is an in-camera JPEG (created at same time as RAW)
            // or an edited/exported JPEG (created later)
            if let convertedModDate = try? convertedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                // If the files were created within 5 seconds of each other, assume it's an in-camera JPEG
                let timeDifference = abs(convertedModDate.timeIntervalSince(rawModDate))
                if timeDifference < 5.0 {
                    // This is likely an in-camera JPEG, not an edited version
                    inCameraJPEGs.append(convertedURL)
                    continue
                }
            }

            editedVariants.append(convertedURL)
        }

        return (editedVariants, inCameraJPEGs)
    }

    nonisolated func detect(for rawFile: URL, in directory: URL) async -> [URL] {
        let basename = rawFile.deletingPathExtension().lastPathComponent
        var detectedVariants: [URL] = []

        // Get the RAW file's modification date for comparison
        guard let rawModDate = try? rawFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return []
        }

        // Check for converted formats with the same basename
        for ext in PhotoFileType.editedExtensions {
            let convertedURL = directory.appendingPathComponent("\(basename).\(ext)")

            // Verify the file exists and is a regular file
            guard FileManager.default.fileExists(atPath: convertedURL.path) else {
                continue
            }

            // Verify it's actually an edited extension and not a RAW file
            let fileExt = convertedURL.pathExtension.lowercased()
            guard PhotoFileType.editedExtensions.contains(fileExt),
                  !PhotoFileType.rawExtensions.contains(fileExt) else {
                continue
            }

            // CRITICAL: Check if this is an in-camera JPEG (created at same time as RAW)
            // or an edited/exported JPEG (created later)
            if let convertedModDate = try? convertedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                // If the files were created within 5 seconds of each other, assume it's an in-camera JPEG
                let timeDifference = abs(convertedModDate.timeIntervalSince(rawModDate))
                if timeDifference < 5.0 {
                    // This is likely an in-camera JPEG, not an edited version
                    continue
                }
            }

            detectedVariants.append(convertedURL)
        }

        return detectedVariants
    }
}
