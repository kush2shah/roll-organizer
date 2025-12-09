//
//  EditDetectionStrategy.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

protocol EditDetectionStrategy: Sendable {
    nonisolated var detectionMethod: EditStatus.DetectionMethod { get }
    func detect(for rawFile: URL, in directory: URL) async -> [URL]
}
