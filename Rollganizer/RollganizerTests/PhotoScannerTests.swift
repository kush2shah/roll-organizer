//
//  PhotoScannerTests.swift
//  RollganizerTests
//
//  Created by Kush Shah on 12/7/25.
//

import Testing
import Foundation
@testable import Rollganizer

@Suite("Photo Scanner Tests")
@MainActor
struct PhotoScannerTests {

    func createTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func createFile(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Basic Scanning Tests

    @Test("Scanner finds RAW files in directory")
    func testScannerFindsRAWFiles() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create some RAW files
        try createFile(at: tempDir.appendingPathComponent("IMG_001.NEF"))
        try createFile(at: tempDir.appendingPathComponent("IMG_002.CR2"))
        try createFile(at: tempDir.appendingPathComponent("IMG_003.ARW"))

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        #expect(collection.photos.count == 3)
        #expect(collection.name == tempDir.lastPathComponent)
    }

    @Test("Scanner ignores non-RAW files")
    func testScannerIgnoresNonRAWFiles() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create RAW and non-RAW files
        try createFile(at: tempDir.appendingPathComponent("IMG_001.NEF"))
        try createFile(at: tempDir.appendingPathComponent("document.pdf"))
        try createFile(at: tempDir.appendingPathComponent("notes.txt"))

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        #expect(collection.photos.count == 1)
    }

    @Test("Scanner is non-recursive")
    func testScannerNonRecursive() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create files in root
        try createFile(at: tempDir.appendingPathComponent("IMG_001.NEF"))

        // Create subdirectory with files
        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try createFile(at: subdir.appendingPathComponent("IMG_002.NEF"))

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        // Should only find the file in the root directory
        #expect(collection.photos.count == 1)
        #expect(collection.subDirectories.count == 1)
        #expect(collection.subDirectories.first?.lastPathComponent == "subdir")
    }

    @Test("Scanner detects edited photos")
    func testScannerDetectsEdits() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create RAW file with XMP sidecar
        try createFile(at: tempDir.appendingPathComponent("IMG_001.NEF"))
        try createFile(at: tempDir.appendingPathComponent("IMG_001.xmp"))

        // Create RAW file without edits
        try createFile(at: tempDir.appendingPathComponent("IMG_002.NEF"))

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        #expect(collection.photos.count == 2)
        #expect(collection.progress.editedPhotos == 1)
        #expect(collection.progress.totalPhotos == 2)
        #expect(collection.progress.percentageEdited == 50.0)
    }

    @Test("Scanner calculates progress correctly")
    func testScannerProgressCalculation() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create 3 RAW files, 2 with edits
        try createFile(at: tempDir.appendingPathComponent("IMG_001.NEF"))
        try createFile(at: tempDir.appendingPathComponent("IMG_001.jpg")) // edited

        try createFile(at: tempDir.appendingPathComponent("IMG_002.NEF"))
        try createFile(at: tempDir.appendingPathComponent("IMG_002.jpg")) // edited

        try createFile(at: tempDir.appendingPathComponent("IMG_003.NEF")) // unedited

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        #expect(collection.progress.totalPhotos == 3)
        #expect(collection.progress.editedPhotos == 2)
        #expect(collection.progress.percentageEdited == (2.0 / 3.0) * 100, "Expected 66.67% progress")
    }

    @Test("Scanner handles empty directory")
    func testScannerEmptyDirectory() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        #expect(collection.photos.isEmpty)
        #expect(collection.progress.totalPhotos == 0)
        #expect(collection.progress.editedPhotos == 0)
        #expect(collection.progress.percentageEdited == 0.0)
    }

    @Test("Scanner tracks subdirectories count")
    func testScannerSubdirectoriesCount() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create multiple subdirectories
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("2023-01"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("2023-02"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("2023-03"),
            withIntermediateDirectories: true
        )

        let scanner = PhotoScanner()
        let collection = try await scanner.scanDirectory(tempDir)

        #expect(collection.subDirectories.count == 3)
    }
}
