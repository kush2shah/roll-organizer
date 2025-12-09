//
//  ScanProgress.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/8/25.
//

import Foundation

/// Represents the progress of a directory scan
struct ScanProgress {
    var currentFolder: String = ""
    var foldersScanned: Int = 0
    var totalFolders: Int? = nil // nil until we know the total
    var isIndeterminate: Bool {
        return totalFolders == nil
    }

    var percentComplete: Double {
        guard let total = totalFolders, total > 0 else {
            return 0
        }
        return Double(foldersScanned) / Double(total) * 100
    }
}
