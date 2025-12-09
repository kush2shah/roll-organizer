//
//  EditStatus.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

enum EditStatus: Codable, Equatable, Hashable, Sendable {
    case unedited
    case edited(method: DetectionMethod)
    case inCameraJPEG // Camera-generated JPEG alongside RAW
    case standaloneJPEG(classification: JPEGClassification) // JPEG without RAW

    enum DetectionMethod: String, Codable {
        case xmpSidecar = "XMP Sidecar"
        case formatConversion = "Format Conversion"
        case versioning = "Version Numbering"
        case namingPattern = "Naming Pattern"
    }
    
    enum JPEGClassification: String, Codable {
        case editedExport = "Edited Export"
        case finalSOOC = "Final (SOOC)"
        case needsEditing = "Needs Editing"
    }

    nonisolated var isEdited: Bool {
        switch self {
        case .edited:
            return true
        case .standaloneJPEG(let classification):
            // Both edited exports and final SOOC count as "complete"
            return classification == .editedExport || classification == .finalSOOC
        default:
            return false
        }
    }

    var detectionMethod: DetectionMethod? {
        if case .edited(let method) = self {
            return method
        }
        return nil
    }
}
