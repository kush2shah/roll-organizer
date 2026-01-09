//
//  Logger.swift
//  Rollganizer
//
//  Structured logging system using os.log for macOS
//

import Foundation
import OSLog

/// Centralized logging service for Rollganizer
/// Uses Apple's unified logging system (os.log) for proper macOS integration
/// Thread-safe and Sendable for use from any actor or thread
final class AppLogger: Sendable {
    static let shared = AppLogger()

    // MARK: - Log Categories

    private let scannerLogger: Logger
    private let cacheLogger: Logger
    private let detectionLogger: Logger
    private let bookmarkLogger: Logger
    private let uiLogger: Logger
    private let generalLogger: Logger

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.rollganizer"

    private init() {
        scannerLogger = Logger(subsystem: subsystem, category: "Scanner")
        cacheLogger = Logger(subsystem: subsystem, category: "Cache")
        detectionLogger = Logger(subsystem: subsystem, category: "Detection")
        bookmarkLogger = Logger(subsystem: subsystem, category: "Bookmark")
        uiLogger = Logger(subsystem: subsystem, category: "UI")
        generalLogger = Logger(subsystem: subsystem, category: "General")
    }

    // MARK: - Log Categories Enum

    enum Category: Sendable {
        case scanner
        case cache
        case detection
        case bookmark
        case ui
        case general
    }

    // MARK: - Logging Methods (all nonisolated for cross-actor access)

    /// Log a debug message (verbose, for development)
    nonisolated func debug(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let context = formatContext(file: file, function: function, line: line)
        logger(for: category).debug("[\(context)] \(message)")
    }

    /// Log an info message (general information)
    nonisolated func info(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let context = formatContext(file: file, function: function, line: line)
        logger(for: category).info("[\(context)] \(message)")
    }

    /// Log a notice message (important but not problematic)
    nonisolated func notice(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let context = formatContext(file: file, function: function, line: line)
        logger(for: category).notice("[\(context)] \(message)")
    }

    /// Log a warning message (potential issues)
    nonisolated func warning(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let context = formatContext(file: file, function: function, line: line)
        logger(for: category).warning("[\(context)] \(message)")
    }

    /// Log an error message (failures and errors)
    nonisolated func error(_ message: String, category: Category = .general, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let context = formatContext(file: file, function: function, line: line)
        if let error = error {
            logger(for: category).error("[\(context)] \(message) - Error: \(error.localizedDescription)")
        } else {
            logger(for: category).error("[\(context)] \(message)")
        }
    }

    /// Log a critical/fault message (severe failures)
    nonisolated func critical(_ message: String, category: Category = .general, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let context = formatContext(file: file, function: function, line: line)
        if let error = error {
            logger(for: category).critical("[\(context)] \(message) - Error: \(error.localizedDescription)")
        } else {
            logger(for: category).critical("[\(context)] \(message)")
        }
    }

    // MARK: - Specialized Logging (all nonisolated for cross-actor access)

    /// Log scan start
    nonisolated func logScanStart(folder: URL, recursive: Bool) {
        scannerLogger.info("Starting scan: \(folder.lastPathComponent, privacy: .public) (recursive: \(recursive))")
    }

    /// Log scan completion
    nonisolated func logScanComplete(folder: URL, photoCount: Int, duration: TimeInterval) {
        scannerLogger.info("Scan complete: \(folder.lastPathComponent, privacy: .public) - \(photoCount) photos in \(String(format: "%.2f", duration))s")
    }

    /// Log scan error
    nonisolated func logScanError(folder: URL, error: Error) {
        scannerLogger.error("Scan failed: \(folder.lastPathComponent, privacy: .public) - \(error.localizedDescription)")
    }

    /// Log edit detection result
    nonisolated func logDetection(photo: String, status: String, method: String?) {
        if let method = method {
            detectionLogger.debug("Detected: \(photo, privacy: .public) - \(status) via \(method)")
        } else {
            detectionLogger.debug("Detected: \(photo, privacy: .public) - \(status)")
        }
    }

    /// Log cache operations
    nonisolated func logCacheHit(key: String) {
        cacheLogger.debug("Cache hit: \(key, privacy: .public)")
    }

    nonisolated func logCacheMiss(key: String) {
        cacheLogger.debug("Cache miss: \(key, privacy: .public)")
    }

    nonisolated func logCacheWrite(key: String) {
        cacheLogger.debug("Cache write: \(key, privacy: .public)")
    }

    /// Log bookmark operations
    nonisolated func logBookmarkCreated(path: String) {
        bookmarkLogger.info("Bookmark created: \(path, privacy: .public)")
    }

    nonisolated func logBookmarkResolved(path: String, wasStale: Bool) {
        if wasStale {
            bookmarkLogger.notice("Bookmark resolved (was stale): \(path, privacy: .public)")
        } else {
            bookmarkLogger.debug("Bookmark resolved: \(path, privacy: .public)")
        }
    }

    nonisolated func logBookmarkError(path: String, error: Error) {
        bookmarkLogger.error("Bookmark error: \(path, privacy: .public) - \(error.localizedDescription)")
    }

    // MARK: - Private Helpers

    nonisolated private func logger(for category: Category) -> Logger {
        switch category {
        case .scanner:
            return scannerLogger
        case .cache:
            return cacheLogger
        case .detection:
            return detectionLogger
        case .bookmark:
            return bookmarkLogger
        case .ui:
            return uiLogger
        case .general:
            return generalLogger
        }
    }

    nonisolated private func formatContext(file: String, function: String, line: Int) -> String {
        let fileName = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        return "\(fileName):\(line)"
    }
}

// MARK: - Convenience Global Access

/// Global logger instance for easy access
let log = AppLogger.shared
