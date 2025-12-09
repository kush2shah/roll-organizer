//
//  Item.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
