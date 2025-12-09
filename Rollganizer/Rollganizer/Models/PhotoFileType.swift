//
//  PhotoFileType.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

enum PhotoFileType: String, Codable, Sendable {
    case raw
    case edited
    case jpeg

    nonisolated static let rawExtensions: Set<String> = ["nef", "cr2", "cr3", "arw", "dng", "orf", "raf", "rw2"]
    nonisolated static let editedExtensions: Set<String> = ["jpg", "jpeg", "tif", "tiff", "png", "heic", "psd"]

    static func fromExtension(_ ext: String) -> PhotoFileType? {
        let lowercased = ext.lowercased()
        if rawExtensions.contains(lowercased) {
            return .raw
        } else if editedExtensions.contains(lowercased) {
            return .edited
        }
        return nil
    }

    static var allPhotoExtensions: Set<String> {
        rawExtensions.union(editedExtensions)
    }
}
