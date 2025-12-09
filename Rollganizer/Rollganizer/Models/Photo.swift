//
//  Photo.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import Foundation

struct Photo: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let fileName: String
    let fileType: PhotoFileType
    var editStatus: EditStatus
    var editedVariants: [URL]
    var inCameraJPEGs: [URL] // JPEGs created by camera alongside RAW

    nonisolated init(id: UUID = UUID(), url: URL, fileName: String, fileType: PhotoFileType, editStatus: EditStatus = .unedited, editedVariants: [URL] = [], inCameraJPEGs: [URL] = []) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.fileType = fileType
        self.editStatus = editStatus
        self.editedVariants = editedVariants
        self.inCameraJPEGs = inCameraJPEGs
    }
}
