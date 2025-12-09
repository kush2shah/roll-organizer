//
//  CollectionProgress.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct CollectionProgress: Codable, Hashable, Sendable {
    let totalPhotos: Int
    let editedPhotos: Int

    var percentageEdited: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(editedPhotos) / Double(totalPhotos) * 100
    }

    var uneditedPhotos: Int {
        totalPhotos - editedPhotos
    }
}
