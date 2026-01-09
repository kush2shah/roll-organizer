//
//  ErrorDialogView.swift
//  Rollganizer
//
//  Created by Kush Shah on 1/9/26.
//

import SwiftUI
import Combine

// MARK: - Error Types

/// Unified error type for user-facing error presentation
enum RollganizerError: Error, Identifiable {
    case folderAccessDenied(url: URL)
    case scanFailed(folderName: String, underlyingError: Error)
    case invalidDirectory(url: URL)
    case bookmarkStale(url: URL)
    case bookmarkInvalid(url: URL)
    case unknown(message: String)

    var id: String {
        switch self {
        case .folderAccessDenied(let url):
            return "accessDenied-\(url.path)"
        case .scanFailed(let name, _):
            return "scanFailed-\(name)"
        case .invalidDirectory(let url):
            return "invalidDir-\(url.path)"
        case .bookmarkStale(let url):
            return "stale-\(url.path)"
        case .bookmarkInvalid(let url):
            return "invalid-\(url.path)"
        case .unknown(let message):
            return "unknown-\(message)"
        }
    }

    var title: String {
        switch self {
        case .folderAccessDenied:
            return "Folder Access Denied"
        case .scanFailed:
            return "Scan Failed"
        case .invalidDirectory:
            return "Invalid Directory"
        case .bookmarkStale:
            return "Folder Access Expired"
        case .bookmarkInvalid:
            return "Bookmark Invalid"
        case .unknown:
            return "Error"
        }
    }

    var message: String {
        switch self {
        case .folderAccessDenied(let url):
            return "Rollganizer doesn't have permission to access \"\(url.lastPathComponent)\"."
        case .scanFailed(let folderName, let error):
            return "Failed to scan \"\(folderName)\": \(error.localizedDescription)"
        case .invalidDirectory(let url):
            return "The path \"\(url.lastPathComponent)\" is not a valid directory or no longer exists."
        case .bookmarkStale(let url):
            return "The saved access to \"\(url.lastPathComponent)\" has expired."
        case .bookmarkInvalid(let url):
            return "The bookmark for \"\(url.lastPathComponent)\" is invalid or corrupted."
        case .unknown(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .folderAccessDenied:
            return "lock.shield"
        case .scanFailed:
            return "exclamationmark.triangle"
        case .invalidDirectory:
            return "folder.badge.questionmark"
        case .bookmarkStale:
            return "clock.badge.exclamationmark"
        case .bookmarkInvalid:
            return "bookmark.slash"
        case .unknown:
            return "exclamationmark.circle"
        }
    }

    var recoverySuggestions: [RecoverySuggestion] {
        switch self {
        case .folderAccessDenied:
            return [
                RecoverySuggestion(
                    title: "Re-add Folder",
                    description: "Remove the folder and add it again to grant access.",
                    action: .readdFolder
                ),
                RecoverySuggestion(
                    title: "Check System Preferences",
                    description: "Verify Rollganizer has Full Disk Access in System Preferences > Privacy & Security.",
                    action: .openSystemPreferences
                )
            ]
        case .scanFailed:
            return [
                RecoverySuggestion(
                    title: "Retry Scan",
                    description: "Try scanning the folder again.",
                    action: .retry
                ),
                RecoverySuggestion(
                    title: "Skip Folder",
                    description: "Skip this folder and continue with others.",
                    action: .skip
                )
            ]
        case .invalidDirectory:
            return [
                RecoverySuggestion(
                    title: "Remove Folder",
                    description: "Remove this folder from Rollganizer.",
                    action: .removeFolder
                ),
                RecoverySuggestion(
                    title: "Reveal in Finder",
                    description: "Check if the folder exists in Finder.",
                    action: .revealInFinder
                )
            ]
        case .bookmarkStale:
            return [
                RecoverySuggestion(
                    title: "Re-add Folder",
                    description: "Remove and re-add the folder to refresh access.",
                    action: .readdFolder
                )
            ]
        case .bookmarkInvalid:
            return [
                RecoverySuggestion(
                    title: "Remove Folder",
                    description: "Remove the corrupted bookmark.",
                    action: .removeFolder
                )
            ]
        case .unknown:
            return []
        }
    }

    /// Convert from PhotoScanner.ScanError
    static func from(scanError: PhotoScanner.ScanError, folderName: String) -> RollganizerError {
        switch scanError {
        case .directoryNotAccessible:
            return .scanFailed(folderName: folderName, underlyingError: scanError)
        case .invalidDirectory:
            return .invalidDirectory(url: URL(fileURLWithPath: folderName))
        }
    }

    /// Convert from BookmarkManager.BookmarkError
    static func from(bookmarkError: BookmarkManager.BookmarkError, url: URL) -> RollganizerError {
        switch bookmarkError {
        case .accessDenied:
            return .folderAccessDenied(url: url)
        case .invalidBookmark:
            return .bookmarkInvalid(url: url)
        case .bookmarkStale:
            return .bookmarkStale(url: url)
        }
    }
}

/// A recovery suggestion with an associated action
struct RecoverySuggestion: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let action: RecoveryAction
}

/// Actions that can be taken to recover from an error
enum RecoveryAction {
    case retry
    case skip
    case removeFolder
    case readdFolder
    case revealInFinder
    case openSystemPreferences
    case dismiss
}

// MARK: - Alert-Style Error View

/// A view modifier that presents an alert-style error dialog with retry option
struct ErrorAlertModifier: ViewModifier {
    @Binding var error: RollganizerError?
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .alert(
                error?.title ?? "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                ),
                presenting: error
            ) { presentedError in
                if onRetry != nil {
                    Button("Retry") {
                        onRetry?()
                        error = nil
                    }
                }
                Button("Dismiss", role: .cancel) {
                    onDismiss?()
                    error = nil
                }
            } message: { presentedError in
                Text(presentedError.message)
            }
    }
}

extension View {
    /// Present an alert-style error dialog
    func errorAlert(
        error: Binding<RollganizerError?>,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorAlertModifier(error: error, onRetry: onRetry, onDismiss: onDismiss))
    }
}

// MARK: - Sheet-Style Detailed Error View

/// A detailed error sheet with recovery suggestions
struct ErrorDetailSheet: View {
    let error: RollganizerError
    let onAction: (RecoveryAction, RollganizerError) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: error.systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text(error.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            // Recovery suggestions
            if !error.recoverySuggestions.isEmpty {
                Divider()
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Recovery Options")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    ForEach(error.recoverySuggestions) { suggestion in
                        RecoverySuggestionRow(suggestion: suggestion) {
                            onAction(suggestion.action, error)
                            dismiss()
                        }
                    }
                }
            }

            // Dismiss button
            Divider()
                .padding(.top, 8)

            HStack {
                Spacer()
                Button("Close") {
                    onAction(.dismiss, error)
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding(16)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A row displaying a recovery suggestion
struct RecoverySuggestionRow: View {
    let suggestion: RecoverySuggestion
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(suggestion.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// View modifier for presenting error detail sheet
struct ErrorSheetModifier: ViewModifier {
    @Binding var error: RollganizerError?
    let onAction: (RecoveryAction, RollganizerError) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $error) { presentedError in
                ErrorDetailSheet(error: presentedError, onAction: onAction)
            }
    }
}

extension View {
    /// Present a detailed error sheet with recovery options
    func errorSheet(
        error: Binding<RollganizerError?>,
        onAction: @escaping (RecoveryAction, RollganizerError) -> Void
    ) -> some View {
        modifier(ErrorSheetModifier(error: error, onAction: onAction))
    }
}

// MARK: - Toast-Style Transient Error

/// A transient toast notification for errors
struct ErrorToast: View {
    let message: String
    let systemImage: String
    let isWarning: Bool

    init(message: String, systemImage: String = "exclamationmark.triangle", isWarning: Bool = false) {
        self.message = message
        self.systemImage = systemImage
        self.isWarning = isWarning
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isWarning ? .orange : .red)

            Text(message)
                .font(.callout)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: 400)
    }
}

/// A container view that manages toast presentation
struct ToastContainer<Content: View>: View {
    @Binding var toast: ToastMessage?
    let content: Content

    @State private var workItem: DispatchWorkItem?

    init(toast: Binding<ToastMessage?>, @ViewBuilder content: () -> Content) {
        self._toast = toast
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content

            if let toast = toast {
                ErrorToast(
                    message: toast.message,
                    systemImage: toast.systemImage,
                    isWarning: toast.isWarning
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
                .onAppear {
                    scheduleHide(duration: toast.duration)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toast != nil)
    }

    private func scheduleHide(duration: TimeInterval) {
        workItem?.cancel()
        let task = DispatchWorkItem {
            withAnimation {
                toast = nil
            }
        }
        workItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

/// A toast message configuration
struct ToastMessage: Equatable {
    let message: String
    let systemImage: String
    let isWarning: Bool
    let duration: TimeInterval

    init(
        message: String,
        systemImage: String = "exclamationmark.triangle",
        isWarning: Bool = false,
        duration: TimeInterval = 4.0
    ) {
        self.message = message
        self.systemImage = systemImage
        self.isWarning = isWarning
        self.duration = duration
    }

    static func error(_ message: String) -> ToastMessage {
        ToastMessage(message: message, systemImage: "xmark.circle", isWarning: false)
    }

    static func warning(_ message: String) -> ToastMessage {
        ToastMessage(message: message, systemImage: "exclamationmark.triangle", isWarning: true)
    }

    static func info(_ message: String) -> ToastMessage {
        ToastMessage(message: message, systemImage: "info.circle", isWarning: true, duration: 3.0)
    }
}

extension View {
    /// Wrap content with a toast container
    func toastContainer(toast: Binding<ToastMessage?>) -> some View {
        ToastContainer(toast: toast) {
            self
        }
    }
}

// MARK: - Inline Error Banner

/// An inline error banner for displaying errors within content areas
struct ErrorBanner: View {
    let error: RollganizerError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.systemImage)
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.headline)

                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onRetry = onRetry {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Error State View

/// A full content area error state with recovery options
struct ErrorStateView: View {
    let error: RollganizerError
    let onAction: (RecoveryAction) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: error.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(error.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            // Primary recovery actions as buttons
            if !error.recoverySuggestions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(error.recoverySuggestions.prefix(2)) { suggestion in
                        Button(suggestion.title) {
                            onAction(suggestion.action)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error Handler Helper

/// A helper class for handling errors and performing recovery actions
@MainActor
class ErrorHandler: ObservableObject {
    @Published var alertError: RollganizerError?
    @Published var sheetError: RollganizerError?
    @Published var toastMessage: ToastMessage?

    /// Show an alert-style error
    func showAlert(_ error: RollganizerError) {
        alertError = error
    }

    /// Show a detailed error sheet
    func showSheet(_ error: RollganizerError) {
        sheetError = error
    }

    /// Show a toast notification
    func showToast(_ message: ToastMessage) {
        toastMessage = message
    }

    /// Show error toast from RollganizerError
    func showErrorToast(_ error: RollganizerError) {
        toastMessage = ToastMessage.error(error.message)
    }

    /// Handle a recovery action
    func handleAction(_ action: RecoveryAction, for error: RollganizerError, context: ErrorContext) {
        switch action {
        case .retry:
            context.onRetry?()
        case .skip:
            context.onSkip?()
        case .removeFolder:
            if let url = error.associatedURL {
                context.onRemoveFolder?(url)
            }
        case .readdFolder:
            if let url = error.associatedURL {
                context.onRemoveFolder?(url)
                context.onReaddFolder?()
            }
        case .revealInFinder:
            if let url = error.associatedURL {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
        case .openSystemPreferences:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        case .dismiss:
            break
        }
    }
}

/// Context for error recovery actions
struct ErrorContext {
    var onRetry: (() -> Void)?
    var onSkip: (() -> Void)?
    var onRemoveFolder: ((URL) -> Void)?
    var onReaddFolder: (() -> Void)?
}

// MARK: - Error URL Helper

extension RollganizerError {
    /// Get the associated URL for this error, if any
    var associatedURL: URL? {
        switch self {
        case .folderAccessDenied(let url),
             .invalidDirectory(let url),
             .bookmarkStale(let url),
             .bookmarkInvalid(let url):
            return url
        case .scanFailed, .unknown:
            return nil
        }
    }
}

// MARK: - Previews

#Preview("Error Alert") {
    struct PreviewWrapper: View {
        @State private var error: RollganizerError? = .folderAccessDenied(url: URL(fileURLWithPath: "/Users/test/Photos"))

        var body: some View {
            VStack {
                Button("Show Error") {
                    error = .folderAccessDenied(url: URL(fileURLWithPath: "/Users/test/Photos"))
                }
            }
            .frame(width: 300, height: 200)
            .errorAlert(error: $error, onRetry: { print("Retry") })
        }
    }
    return PreviewWrapper()
}

#Preview("Error Sheet") {
    ErrorDetailSheet(
        error: .scanFailed(
            folderName: "Vacation Photos",
            underlyingError: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        )
    ) { action, error in
        print("Action: \(action)")
    }
}

#Preview("Error Toast") {
    struct PreviewWrapper: View {
        @State private var toast: ToastMessage? = .error("Failed to scan folder")

        var body: some View {
            VStack {
                Button("Show Toast") {
                    toast = .error("Failed to scan folder")
                }
                Spacer()
            }
            .frame(width: 500, height: 400)
            .toastContainer(toast: $toast)
        }
    }
    return PreviewWrapper()
}

#Preview("Error Banner") {
    VStack {
        ErrorBanner(
            error: .invalidDirectory(url: URL(fileURLWithPath: "/Users/test/Missing")),
            onRetry: { print("Retry") },
            onDismiss: { print("Dismiss") }
        )
        .padding()

        Spacer()
    }
}

#Preview("Error State") {
    ErrorStateView(
        error: .folderAccessDenied(url: URL(fileURLWithPath: "/Users/test/Photos"))
    ) { action in
        print("Action: \(action)")
    }
}
