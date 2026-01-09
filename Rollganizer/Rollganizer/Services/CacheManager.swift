//
//  CacheManager.swift
//  Rollganizer
//
//  SQLite-based caching system for photo metadata and scan results
//

import Foundation
import SQLite3

/// Actor-based cache manager using SQLite for persistent storage
/// Provides thread-safe caching of photo metadata, JPEG classifications, and scan results
actor CacheManager {
    static let shared = CacheManager()

    private var db: OpaquePointer?
    private let dbPath: String

    // MARK: - Schema Version

    private let schemaVersion = 1

    // MARK: - Initialization

    private init() {
        // Store database in Application Support directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("Rollganizer", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        dbPath = appDirectory.appendingPathComponent("cache.sqlite").path

        // Open database synchronously during init
        openDatabase()
        createTablesIfNeeded()
    }

    deinit {
        closeDatabase()
    }

    // MARK: - Database Connection

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            log.error("Failed to open cache database at \(dbPath)", category: .cache)
            db = nil
        } else {
            log.info("Cache database opened at \(dbPath)", category: .cache)

            // Enable WAL mode for better concurrent access
            executeSQL("PRAGMA journal_mode=WAL")
            executeSQL("PRAGMA synchronous=NORMAL")
        }
    }

    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    private func createTablesIfNeeded() {
        // Photo metadata table
        let createPhotoMetadataSQL = """
            CREATE TABLE IF NOT EXISTS photo_metadata (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT UNIQUE NOT NULL,
                file_name TEXT NOT NULL,
                file_type TEXT NOT NULL,
                modification_date REAL NOT NULL,
                file_hash TEXT,
                edit_status TEXT NOT NULL,
                detection_method TEXT,
                jpeg_classification TEXT,
                edited_variants TEXT,
                in_camera_jpegs TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """

        // JPEG classifications table (user-provided classifications)
        let createJPEGClassificationsSQL = """
            CREATE TABLE IF NOT EXISTS jpeg_classifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                folder_path TEXT UNIQUE NOT NULL,
                classification TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """

        // Scan results table (folder scan metadata)
        let createScanResultsSQL = """
            CREATE TABLE IF NOT EXISTS scan_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                folder_path TEXT UNIQUE NOT NULL,
                folder_name TEXT NOT NULL,
                scan_date REAL NOT NULL,
                photo_count INTEGER NOT NULL,
                edited_count INTEGER NOT NULL,
                has_children INTEGER NOT NULL DEFAULT 0,
                parent_path TEXT,
                is_root_folder INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """

        // Schema version table
        let createSchemaVersionSQL = """
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY
            )
        """

        // Create indexes for faster lookups
        let createIndexes = [
            "CREATE INDEX IF NOT EXISTS idx_photo_metadata_path ON photo_metadata(file_path)",
            "CREATE INDEX IF NOT EXISTS idx_photo_metadata_mod_date ON photo_metadata(modification_date)",
            "CREATE INDEX IF NOT EXISTS idx_jpeg_classifications_folder ON jpeg_classifications(folder_path)",
            "CREATE INDEX IF NOT EXISTS idx_scan_results_folder ON scan_results(folder_path)",
            "CREATE INDEX IF NOT EXISTS idx_scan_results_parent ON scan_results(parent_path)"
        ]

        executeSQL(createPhotoMetadataSQL)
        executeSQL(createJPEGClassificationsSQL)
        executeSQL(createScanResultsSQL)
        executeSQL(createSchemaVersionSQL)

        for indexSQL in createIndexes {
            executeSQL(indexSQL)
        }

        // Set schema version if not exists
        executeSQL("INSERT OR IGNORE INTO schema_version (version) VALUES (\(schemaVersion))")
    }

    @discardableResult
    private func executeSQL(_ sql: String) -> Bool {
        guard let db = db else { return false }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            if let errorMessage = errorMessage {
                log.error("SQL Error: \(String(cString: errorMessage))", category: .cache)
                sqlite3_free(errorMessage)
            }
            return false
        }
        return true
    }

    // MARK: - Photo Metadata Cache

    /// Cache photo metadata for a single photo
    func cachePhotoMetadata(_ photo: Photo, modificationDate: Date) {
        guard let db = db else { return }

        let sql = """
            INSERT OR REPLACE INTO photo_metadata
            (file_path, file_name, file_type, modification_date, edit_status,
             detection_method, jpeg_classification, edited_variants, in_camera_jpegs,
             created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log.error("Failed to prepare photo metadata insert", category: .cache)
            return
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970
        let editStatusData = encodeEditStatus(photo.editStatus)
        let editedVariantsJSON = encodeURLArray(photo.editedVariants)
        let inCameraJPEGsJSON = encodeURLArray(photo.inCameraJPEGs)

        sqlite3_bind_text(statement, 1, photo.url.path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, photo.fileName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, photo.fileType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 4, modificationDate.timeIntervalSince1970)
        sqlite3_bind_text(statement, 5, editStatusData.status, -1, SQLITE_TRANSIENT)
        bindOptionalText(statement, 6, editStatusData.detectionMethod)
        bindOptionalText(statement, 7, editStatusData.jpegClassification)
        sqlite3_bind_text(statement, 8, editedVariantsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 9, inCameraJPEGsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 10, now)
        sqlite3_bind_double(statement, 11, now)

        if sqlite3_step(statement) == SQLITE_DONE {
            log.logCacheWrite(key: photo.url.lastPathComponent)
        } else {
            log.error("Failed to cache photo metadata for \(photo.fileName)", category: .cache)
        }
    }

    /// Retrieve cached photo metadata if it's still valid (file hasn't been modified)
    func getCachedPhoto(at url: URL) -> Photo? {
        guard let db = db else { return nil }

        // First check if the file's modification date matches
        guard let currentModDate = getFileModificationDate(url) else { return nil }

        let sql = """
            SELECT file_name, file_type, modification_date, edit_status,
                   detection_method, jpeg_classification, edited_variants, in_camera_jpegs
            FROM photo_metadata WHERE file_path = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, url.path, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            log.logCacheMiss(key: url.lastPathComponent)
            return nil
        }

        let cachedModDate = sqlite3_column_double(statement, 2)

        // Check if file has been modified since caching
        if abs(currentModDate.timeIntervalSince1970 - cachedModDate) > 1.0 {
            log.debug("Cache invalidated (file modified): \(url.lastPathComponent)", category: .cache)
            return nil
        }

        // Reconstruct the photo from cached data
        // Column indices: file_name(0), file_type(1), modification_date(2), edit_status(3),
        //                 detection_method(4), jpeg_classification(5), edited_variants(6), in_camera_jpegs(7)
        guard let fileName = getColumnText(statement, 0),
              let fileTypeRaw = getColumnText(statement, 1),
              let fileType = PhotoFileType(rawValue: fileTypeRaw),
              let editStatusRaw = getColumnText(statement, 3) else {
            return nil
        }

        let detectionMethod = getColumnText(statement, 4)
        let jpegClassification = getColumnText(statement, 5)
        let editedVariantsJSON = getColumnText(statement, 6)
        let inCameraJPEGsJSON = getColumnText(statement, 7)

        let editStatus = decodeEditStatus(
            status: editStatusRaw,
            detectionMethod: detectionMethod,
            jpegClassification: jpegClassification
        )

        let editedVariants = decodeURLArray(editedVariantsJSON)
        let inCameraJPEGs = decodeURLArray(inCameraJPEGsJSON)

        log.logCacheHit(key: url.lastPathComponent)

        return Photo(
            url: url,
            fileName: fileName,
            fileType: fileType,
            editStatus: editStatus,
            editedVariants: editedVariants,
            inCameraJPEGs: inCameraJPEGs
        )
    }

    /// Check if a file needs to be rescanned based on modification date
    func needsRescan(url: URL) -> Bool {
        guard let db = db else { return true }
        guard let currentModDate = getFileModificationDate(url) else { return true }

        let sql = "SELECT modification_date FROM photo_metadata WHERE file_path = ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return true
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, url.path, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return true // Not in cache
        }

        let cachedModDate = sqlite3_column_double(statement, 0)
        return abs(currentModDate.timeIntervalSince1970 - cachedModDate) > 1.0
    }

    /// Batch cache multiple photos
    func cachePhotos(_ photos: [Photo], in folderURL: URL) {
        guard let db = db else { return }

        executeSQL("BEGIN TRANSACTION")

        for photo in photos {
            if let modDate = getFileModificationDate(photo.url) {
                cachePhotoMetadata(photo, modificationDate: modDate)
            }
        }

        executeSQL("COMMIT")
        log.info("Cached \(photos.count) photos from \(folderURL.lastPathComponent)", category: .cache)
    }

    // MARK: - JPEG Classification Cache

    /// Save a user's JPEG classification for a folder
    func saveJPEGClassification(
        for folderPath: String,
        classification: EditStatus.JPEGClassification
    ) {
        guard let db = db else { return }

        let sql = """
            INSERT OR REPLACE INTO jpeg_classifications
            (folder_path, classification, created_at, updated_at)
            VALUES (?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log.error("Failed to prepare JPEG classification insert", category: .cache)
            return
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970

        sqlite3_bind_text(statement, 1, folderPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, classification.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, now)
        sqlite3_bind_double(statement, 4, now)

        if sqlite3_step(statement) == SQLITE_DONE {
            log.info("Saved JPEG classification for \(folderPath): \(classification.rawValue)", category: .cache)
        }
    }

    /// Get cached JPEG classification for a folder
    func getJPEGClassification(for folderPath: String) -> EditStatus.JPEGClassification? {
        guard let db = db else { return nil }

        let sql = "SELECT classification FROM jpeg_classifications WHERE folder_path = ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, folderPath, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let classificationRaw = getColumnText(statement, 0) else {
            return nil
        }

        return EditStatus.JPEGClassification(rawValue: classificationRaw)
    }

    // MARK: - Scan Results Cache

    /// Cache scan results for a folder
    func cacheScanResult(
        folderPath: String,
        folderName: String,
        photoCount: Int,
        editedCount: Int,
        hasChildren: Bool,
        parentPath: String?,
        isRootFolder: Bool
    ) {
        guard let db = db else { return }

        let sql = """
            INSERT OR REPLACE INTO scan_results
            (folder_path, folder_name, scan_date, photo_count, edited_count,
             has_children, parent_path, is_root_folder, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log.error("Failed to prepare scan result insert", category: .cache)
            return
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970

        sqlite3_bind_text(statement, 1, folderPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, folderName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, now)
        sqlite3_bind_int(statement, 4, Int32(photoCount))
        sqlite3_bind_int(statement, 5, Int32(editedCount))
        sqlite3_bind_int(statement, 6, hasChildren ? 1 : 0)
        bindOptionalText(statement, 7, parentPath)
        sqlite3_bind_int(statement, 8, isRootFolder ? 1 : 0)
        sqlite3_bind_double(statement, 9, now)
        sqlite3_bind_double(statement, 10, now)

        if sqlite3_step(statement) == SQLITE_DONE {
            log.logCacheWrite(key: folderPath)
        }
    }

    /// Cache an entire PhotoCollection and its children recursively
    func cacheCollection(_ collection: PhotoCollection) {
        // Cache photos in this collection
        cachePhotos(collection.photos, in: collection.url)

        // Cache the scan result for this folder
        cacheScanResult(
            folderPath: collection.url.path,
            folderName: collection.name,
            photoCount: collection.progress.totalPhotos,
            editedCount: collection.progress.editedPhotos,
            hasChildren: !collection.children.isEmpty,
            parentPath: collection.parentURL?.path,
            isRootFolder: collection.isRootFolder
        )

        // Cache JPEG classification if set
        if let jpegClassification = collection.jpegClassification {
            saveJPEGClassification(for: collection.url.path, classification: jpegClassification)
        }

        // Recursively cache children
        for child in collection.children {
            cacheCollection(child)
        }
    }

    /// Get cached scan result for a folder
    func getCachedScanResult(for folderPath: String) -> CachedScanResult? {
        guard let db = db else { return nil }

        let sql = """
            SELECT folder_name, scan_date, photo_count, edited_count,
                   has_children, parent_path, is_root_folder
            FROM scan_results WHERE folder_path = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, folderPath, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let folderName = getColumnText(statement, 0) else {
            return nil
        }

        return CachedScanResult(
            folderPath: folderPath,
            folderName: folderName,
            scanDate: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            photoCount: Int(sqlite3_column_int(statement, 2)),
            editedCount: Int(sqlite3_column_int(statement, 3)),
            hasChildren: sqlite3_column_int(statement, 4) == 1,
            parentPath: getColumnText(statement, 5),
            isRootFolder: sqlite3_column_int(statement, 6) == 1
        )
    }

    /// Check if a folder scan is still valid (no files modified since scan)
    func isScanValid(for folderURL: URL) -> Bool {
        guard let cachedResult = getCachedScanResult(for: folderURL.path) else {
            return false
        }

        // Check if any files in the folder have been modified since the scan
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for fileURL in contents {
            if let modDate = getFileModificationDate(fileURL),
               modDate > cachedResult.scanDate {
                return false
            }
        }

        return true
    }

    // MARK: - Cache Invalidation

    /// Remove cached data for a specific file
    func invalidatePhoto(at url: URL) {
        guard let db = db else { return }

        let sql = "DELETE FROM photo_metadata WHERE file_path = ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, url.path, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    /// Remove cached data for a folder and all its contents
    func invalidateFolder(at folderPath: String) {
        guard let db = db else { return }

        executeSQL("BEGIN TRANSACTION")

        // Delete photos in this folder
        let deletePhotosSQL = "DELETE FROM photo_metadata WHERE file_path LIKE ?"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deletePhotosSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, "\(folderPath)%", -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        // Delete scan results for this folder and subfolders
        let deleteScanSQL = "DELETE FROM scan_results WHERE folder_path LIKE ?"
        if sqlite3_prepare_v2(db, deleteScanSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, "\(folderPath)%", -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        // Delete JPEG classifications for this folder and subfolders
        let deleteClassificationsSQL = "DELETE FROM jpeg_classifications WHERE folder_path LIKE ?"
        if sqlite3_prepare_v2(db, deleteClassificationsSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, "\(folderPath)%", -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        executeSQL("COMMIT")
        log.info("Invalidated cache for folder: \(folderPath)", category: .cache)
    }

    /// Clear all cached data
    func clearAllCache() {
        executeSQL("DELETE FROM photo_metadata")
        executeSQL("DELETE FROM jpeg_classifications")
        executeSQL("DELETE FROM scan_results")
        executeSQL("VACUUM")
        log.info("All cache cleared", category: .cache)
    }

    // MARK: - Statistics

    /// Get cache statistics
    func getCacheStatistics() -> CacheStatistics {
        guard let db = db else {
            return CacheStatistics(photoCount: 0, folderCount: 0, classificationCount: 0, databaseSize: 0)
        }

        var stats = CacheStatistics(photoCount: 0, folderCount: 0, classificationCount: 0, databaseSize: 0)

        // Count photos
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM photo_metadata", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                stats.photoCount = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        // Count folders
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM scan_results", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                stats.folderCount = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        // Count classifications
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM jpeg_classifications", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                stats.classificationCount = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        // Get database file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
           let size = attrs[.size] as? Int64 {
            stats.databaseSize = size
        }

        return stats
    }

    // MARK: - Private Helpers

    private nonisolated func getFileModificationDate(_ url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return modDate
    }

    private func getColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    // MARK: - EditStatus Encoding/Decoding

    private struct EncodedEditStatus {
        let status: String
        let detectionMethod: String?
        let jpegClassification: String?
    }

    private func encodeEditStatus(_ status: EditStatus) -> EncodedEditStatus {
        switch status {
        case .unedited:
            return EncodedEditStatus(status: "unedited", detectionMethod: nil, jpegClassification: nil)
        case .edited(let method):
            return EncodedEditStatus(status: "edited", detectionMethod: method.rawValue, jpegClassification: nil)
        case .inCameraJPEG:
            return EncodedEditStatus(status: "inCameraJPEG", detectionMethod: nil, jpegClassification: nil)
        case .standaloneJPEG(let classification):
            return EncodedEditStatus(status: "standaloneJPEG", detectionMethod: nil, jpegClassification: classification.rawValue)
        }
    }

    private func decodeEditStatus(
        status: String,
        detectionMethod: String?,
        jpegClassification: String?
    ) -> EditStatus {
        switch status {
        case "unedited":
            return .unedited
        case "edited":
            if let methodRaw = detectionMethod,
               let method = EditStatus.DetectionMethod(rawValue: methodRaw) {
                return .edited(method: method)
            }
            return .unedited
        case "inCameraJPEG":
            return .inCameraJPEG
        case "standaloneJPEG":
            if let classRaw = jpegClassification,
               let classification = EditStatus.JPEGClassification(rawValue: classRaw) {
                return .standaloneJPEG(classification: classification)
            }
            return .standaloneJPEG(classification: .needsEditing)
        default:
            return .unedited
        }
    }

    // MARK: - URL Array Encoding/Decoding

    private func encodeURLArray(_ urls: [URL]) -> String {
        let paths = urls.map { $0.path }
        guard let data = try? JSONEncoder().encode(paths),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func decodeURLArray(_ json: String?) -> [URL] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }
}

// MARK: - SQLITE_TRANSIENT Constant

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Supporting Types

/// Represents a cached scan result
struct CachedScanResult: Sendable {
    let folderPath: String
    let folderName: String
    let scanDate: Date
    let photoCount: Int
    let editedCount: Int
    let hasChildren: Bool
    let parentPath: String?
    let isRootFolder: Bool
}

/// Cache statistics for monitoring
struct CacheStatistics: Sendable {
    var photoCount: Int
    var folderCount: Int
    var classificationCount: Int
    var databaseSize: Int64

    var formattedDatabaseSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: databaseSize)
    }
}
