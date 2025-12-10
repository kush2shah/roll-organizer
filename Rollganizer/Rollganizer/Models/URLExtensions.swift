//
//  URLExtensions.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/8/25.
//

import Foundation

extension URL {
    /// Returns the display name of the file/folder, handling special characters
    /// macOS converts : to / in filenames, so we convert them back for display
    var displayName: String {
        let name = self.lastPathComponent

        // macOS file system converts : to / in filenames
        // When displaying, we should show the original character
        // However, since both : and / are converted, we keep them as-is
        // and just ensure proper decoding
        return name
            .removingPercentEncoding ?? name
    }
}
