//
//  EditDetectionEngine.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

actor EditDetectionEngine {
    private let strategies: [EditDetectionStrategy]

    init() {
        // Priority order: XMP → Format Conversion → Versioning → Naming Pattern
        self.strategies = [
            XMPSidecarDetector(),
            FormatConversionDetector(),
            VersioningDetector(),
            NamingConventionDetector()
        ]
    }

    /// Detects if a RAW file has been edited using the configured detection strategies.
    /// Returns the EditStatus, any detected edited variants, and in-camera JPEGs.
    func detectEditStatus(for rawFile: URL, in directory: URL) async -> (EditStatus, [URL], [URL]) {
        var inCameraJPEGs: [URL] = []

        // Special handling for format conversion detector to separate in-camera JPEGs
        if let formatDetector = strategies.first(where: { $0 is FormatConversionDetector }) as? FormatConversionDetector {
            let (edited, inCamera) = await formatDetector.detectWithInCameraCheck(for: rawFile, in: directory)
            inCameraJPEGs = inCamera
            if !edited.isEmpty {
                return (.edited(method: formatDetector.detectionMethod), edited, inCameraJPEGs)
            }
        }

        // Try other strategies in priority order
        for strategy in strategies where !(strategy is FormatConversionDetector) {
            let variants = await strategy.detect(for: rawFile, in: directory)
            if !variants.isEmpty {
                return (.edited(method: strategy.detectionMethod), variants, inCameraJPEGs)
            }
        }

        // No edits detected, but may have in-camera JPEGs
        if !inCameraJPEGs.isEmpty {
            return (.inCameraJPEG, [], inCameraJPEGs)
        }

        return (.unedited, [], [])
    }
}
