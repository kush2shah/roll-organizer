//
//  XMPSidecarDetector.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct XMPSidecarDetector: EditDetectionStrategy, Sendable {
    nonisolated let detectionMethod: EditStatus.DetectionMethod = .xmpSidecar

    nonisolated init() {}

    nonisolated func detect(for rawFile: URL, in directory: URL) async -> [URL] {
        let basename = rawFile.deletingPathExtension().lastPathComponent
        let xmpURL = directory.appendingPathComponent("\(basename).xmp")

        // Check if XMP sidecar file exists
        if FileManager.default.fileExists(atPath: xmpURL.path) {
            return [xmpURL]
        }

        return []
    }
}
