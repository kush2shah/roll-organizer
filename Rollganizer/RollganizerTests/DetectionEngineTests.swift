//
//  DetectionEngineTests.swift
//  RollganizerTests
//
//  Created by Kush Shah on 12/7/25.
//

import Testing
import Foundation
@testable import Rollganizer

@Suite("Edit Detection Tests")
@MainActor
struct DetectionEngineTests {

    // MARK: - Helper Methods

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

    // MARK: - XMP Sidecar Detection Tests

    @Test("XMP Sidecar detector finds XMP file")
    func testXMPSidecarDetection() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create a RAW file and its XMP sidecar
        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let xmpFile = tempDir.appendingPathComponent("DSC_1234.xmp")

        try createFile(at: rawFile)
        try createFile(at: xmpFile)

        let detector = XMPSidecarDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count == 1)
        #expect(results.first?.lastPathComponent == "DSC_1234.xmp")
    }

    @Test("XMP Sidecar detector returns empty when no XMP exists")
    func testXMPSidecarNotFound() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        try createFile(at: rawFile)

        let detector = XMPSidecarDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.isEmpty)
    }

    // MARK: - Format Conversion Detection Tests

    @Test("Format conversion detector finds JPEG conversion")
    func testFormatConversionJPEG() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let jpegFile = tempDir.appendingPathComponent("DSC_1234.jpg")

        try createFile(at: rawFile)
        try createFile(at: jpegFile)

        let detector = FormatConversionDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count >= 1)
        #expect(results.contains(where: { $0.lastPathComponent == "DSC_1234.jpg" }))
    }

    @Test("Format conversion detector finds multiple formats")
    func testFormatConversionMultiple() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let jpegFile = tempDir.appendingPathComponent("DSC_1234.jpg")
        let tiffFile = tempDir.appendingPathComponent("DSC_1234.tiff")

        try createFile(at: rawFile)
        try createFile(at: jpegFile)
        try createFile(at: tiffFile)

        let detector = FormatConversionDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count >= 2)
    }

    // MARK: - Versioning Detection Tests

    @Test("Versioning detector finds dash numbering (DSC-2.jpg)")
    func testVersioningDashNumbering() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let versionFile = tempDir.appendingPathComponent("DSC_1234-2.jpg")

        try createFile(at: rawFile)
        try createFile(at: versionFile)

        let detector = VersioningDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count >= 1)
        #expect(results.contains(where: { $0.lastPathComponent == "DSC_1234-2.jpg" }))
    }

    @Test("Versioning detector finds v notation (DSC_v2.jpg)")
    func testVersioningVNotation() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let versionFile = tempDir.appendingPathComponent("DSC_1234_v2.jpg")

        try createFile(at: rawFile)
        try createFile(at: versionFile)

        let detector = VersioningDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count >= 1)
        #expect(results.contains(where: { $0.lastPathComponent == "DSC_1234_v2.jpg" }))
    }

    @Test("Versioning detector finds space numbering (DSC 2.jpg)")
    func testVersioningSpaceNumbering() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let versionFile = tempDir.appendingPathComponent("DSC_1234 2.jpg")

        try createFile(at: rawFile)
        try createFile(at: versionFile)

        let detector = VersioningDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count >= 1)
        #expect(results.contains(where: { $0.lastPathComponent == "DSC_1234 2.jpg" }))
    }

    // MARK: - Naming Convention Detection Tests

    @Test("Naming convention detector finds files with 'edit' in name")
    func testNamingConventionEdit() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let editFile = tempDir.appendingPathComponent("DSC_1234edit.jpg")

        try createFile(at: rawFile)
        try createFile(at: editFile)

        let detector = NamingConventionDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        #expect(results.count >= 1)
        #expect(results.contains(where: { $0.lastPathComponent == "DSC_1234edit.jpg" }))
    }

    @Test("Naming convention detector ignores folders named 'edits'")
    func testNamingConventionIgnoresFolders() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create a folder named "edits"
        let editsFolder = tempDir.appendingPathComponent("edits")
        try FileManager.default.createDirectory(at: editsFolder, withIntermediateDirectories: true)

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        try createFile(at: rawFile)

        let detector = NamingConventionDetector()
        let results = await detector.detect(for: rawFile, in: tempDir)

        // Should NOT detect the folder as an edit
        #expect(results.isEmpty)
    }

    // MARK: - Edit Detection Engine Tests

    @Test("Detection engine returns XMP as highest priority")
    func testDetectionEnginePriority() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        // Create multiple detection methods
        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        let xmpFile = tempDir.appendingPathComponent("DSC_1234.xmp")
        let jpegFile = tempDir.appendingPathComponent("DSC_1234.jpg")

        try createFile(at: rawFile)
        try createFile(at: xmpFile)
        try createFile(at: jpegFile)

        let engine = EditDetectionEngine()
        let (status, variants) = await engine.detectEditStatus(for: rawFile, in: tempDir)

        // Should detect XMP first (highest priority)
        #expect(status.isEdited)
        #expect(status.detectionMethod == .xmpSidecar)
        #expect(!variants.isEmpty)
    }

    @Test("Detection engine returns unedited when no edits found")
    func testDetectionEngineUnedited() async throws {
        let tempDir = try createTemporaryDirectory()
        defer { cleanup(tempDir) }

        let rawFile = tempDir.appendingPathComponent("DSC_1234.NEF")
        try createFile(at: rawFile)

        let engine = EditDetectionEngine()
        let (status, variants) = await engine.detectEditStatus(for: rawFile, in: tempDir)

        #expect(!status.isEdited)
        #expect(status.detectionMethod == nil)
        #expect(variants.isEmpty)
    }
}
