//
//  FileTableView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/9/25.
//

import SwiftUI

// MARK: - Color Scheme
private enum AppColors {
    static let edited = Color.green
    static let unedited = Color(nsColor: .tertiaryLabelColor)
    static let inCamera = Color.orange
    static let sooc = Color.blue
    static let folder = Color.accentColor
    static let progress50Plus = Color.green
    static let progressUnder50 = Color.orange
}

// MARK: - Filter State
enum EditStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case edited = "Edited"
    case unedited = "Unedited"
    case inCamera = "In-Camera"

    var id: String { rawValue }
}

/// Table-based hierarchical view of files with sortable columns
struct FileTableView: View {
    let collection: PhotoCollection
    let rootFolderURL: URL
    @ObservedObject var viewModel: RootViewModel

    @State private var sortOrder = [KeyPathComparator(\FileRow.name)]
    @State private var selection = Set<FileRow.ID>()
    @State private var cachedRows: [FileRow] = []
    @State private var lastCollectionID: UUID?
    @State private var expandedFolders = Set<UUID>()

    // Search and filter state
    @State private var searchText = ""
    @State private var statusFilter: EditStatusFilter = .all
    @State private var showFoldersOnly = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress header with search
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    // Progress info
                    HStack(spacing: 8) {
                        ProgressRing(progress: collection.progress.percentageEdited / 100)
                            .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(collection.progress.editedPhotos)/\(collection.progress.totalPhotos)")
                                .font(.system(.headline, design: .rounded).monospacedDigit())
                            Text("edited")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Quick filters
                    Picker("Filter", selection: $statusFilter) {
                        ForEach(EditStatusFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)

                    // Search field
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search files...", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 120)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // File table
            Table(of: FileRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name") { row in
                HStack(spacing: 4) {
                    // Indentation for hierarchy
                    ForEach(0..<row.level, id: \.self) { _ in
                        Spacer()
                            .frame(width: 16)
                    }

                    if row.isFolder {
                        // Disclosure triangle for folders
                        Button(action: {
                            toggleFolder(row)
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(expandedFolders.contains(row.id) ? 90 : 0))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    } else {
                        // Spacer for non-folders to align with folder items
                        Spacer()
                            .frame(width: 16)
                    }

                    Text(row.name)
                        .font(row.isFolder ? .body.weight(.medium) : .body)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if row.isFolder {
                        navigateToFolder(row)
                    }
                }
            }
            .width(min: 200, ideal: 300)

            TableColumn("Edit Status") { row in
                if !row.isFolder {
                    HStack(spacing: 6) {
                        row.statusIcon
                        Text(row.statusText)
                            .font(.caption)
                    }
                }
            }
            .width(min: 120, ideal: 150)

            TableColumn("File Type", value: \.fileTypeDisplay)
                .width(min: 80, ideal: 100)

            TableColumn("Variants") { row in
                if !row.isFolder && row.variantCount > 0 {
                    Text("\(row.variantCount)")
                        .monospacedDigit()
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Date Modified") { row in
                if let date = row.dateModified {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 120)
        } rows: {
            ForEach(sortedRows) { row in
                TableRow(row)
                    .contextMenu {
                        FileRowContextMenu(row: row)
                    }
            }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .task(id: collection.id) {
                // Rebuild rows when collection changes
                await rebuildRows()
            }
            .onChange(of: expandedFolders) { _, _ in
                // Rebuild rows when folders are expanded/collapsed
                Task {
                    await rebuildRows()
                }
            }
        }
    }

    private var sortedRows: [FileRow] {
        // Return cached rows in their hierarchical order
        // Sorting is already applied during buildFileRows to maintain hierarchy
        cachedRows
    }

    private func rebuildRows() async {
        // Build rows synchronously since we need access to expandedFolders state
        cachedRows = buildFileRows(from: collection, level: 0, expandedFolders: expandedFolders)
    }

    private func toggleFolder(_ row: FileRow) {
        guard row.isFolder, let folderCollection = row.collection else { return }

        if expandedFolders.contains(row.id) {
            expandedFolders.remove(row.id)
        } else {
            expandedFolders.insert(row.id)

            // Check if this folder needs JPEG classification when expanded
            if folderCollection.needsJPEGClassification {
                viewModel.pendingJPEGCollection = folderCollection
                viewModel.pendingJPEGFolderName = folderCollection.name
            }
        }

        Task {
            await rebuildRows()
        }
    }

    private func navigateToFolder(_ row: FileRow) {
        guard row.isFolder, let folderCollection = row.collection else { return }

        // Update viewModel's selected collection (syncs with sidebar)
        viewModel.selectedCollection = folderCollection

        // Check if this folder needs JPEG classification when navigated to
        if folderCollection.needsJPEGClassification {
            viewModel.pendingJPEGCollection = folderCollection
            viewModel.pendingJPEGFolderName = folderCollection.name
        }
    }

    /// Build file rows from collection - showing expanded folders recursively
    private func buildFileRows(from collection: PhotoCollection, level: Int, expandedFolders: Set<UUID>) -> [FileRow] {
        var rows: [FileRow] = []

        // Build folder rows
        let folderRows: [FileRow] = collection.children.map { child in
            FileRow(
                id: child.id,
                name: child.name,
                level: level,
                isFolder: true,
                url: child.url,
                collection: child,
                statusIcon: AnyView(EmptyView()),
                statusText: "",
                fileTypeDisplay: "",
                variantCount: 0,
                dateModified: nil
            )
        }.sorted(using: sortOrder)

        // Add folders with their expanded contents
        for folderRow in folderRows {
            rows.append(folderRow)

            // If this folder is expanded, recursively add its contents immediately after it
            if let childCollection = folderRow.collection, expandedFolders.contains(folderRow.id) {
                rows.append(contentsOf: buildFileRows(from: childCollection, level: level + 1, expandedFolders: expandedFolders))
            }
        }

        // Build and add photo rows (sorted)
        let photoRows: [FileRow] = collection.photos.map { photo in
            FileRow(
                id: photo.id,
                name: photo.fileName,
                level: level,
                isFolder: false,
                url: photo.url,
                collection: nil,
                statusIcon: AnyView(statusIcon(for: photo)),
                statusText: statusText(for: photo),
                fileTypeDisplay: fileTypeDisplay(for: photo),
                variantCount: photo.editedVariants.count + photo.inCameraJPEGs.count,
                dateModified: fileModificationDate(for: photo.url)
            )
        }.sorted(using: sortOrder)

        rows.append(contentsOf: photoRows)

        return rows
    }

    private nonisolated func statusIcon(for photo: Photo) -> some View {
        Group {
            switch photo.editStatus {
            case .edited:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .inCameraJPEG:
                Image(systemName: "camera.circle.fill")
                    .foregroundStyle(.orange)
            case .standaloneJPEG(let classification):
                switch classification {
                case .editedExport:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .finalSOOC:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                case .needsEditing:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            case .unedited:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .imageScale(.small)
    }

    private nonisolated func statusText(for photo: Photo) -> String {
        switch photo.editStatus {
        case .edited(let method):
            return method.rawValue
        case .inCameraJPEG:
            return "In-Camera JPEG"
        case .standaloneJPEG(let classification):
            return classification.rawValue
        case .unedited:
            return "Not edited"
        }
    }

    private nonisolated func fileTypeDisplay(for photo: Photo) -> String {
        switch photo.fileType {
        case .raw:
            return "RAW"
        case .edited:
            return "Edited"
        case .jpeg:
            return "JPEG"
        }
    }

    private nonisolated func fileModificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

/// Row data for the file table
struct FileRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let level: Int
    let isFolder: Bool
    let url: URL
    let collection: PhotoCollection? // For folder rows, reference to the collection
    let statusIcon: AnyView
    let statusText: String
    let fileTypeDisplay: String
    let variantCount: Int
    let dateModified: Date?

    static func == (lhs: FileRow, rhs: FileRow) -> Bool {
        lhs.id == rhs.id
    }
}

/// Context menu for file rows
struct FileRowContextMenu: View {
    let row: FileRow

    var body: some View {
        Button {
            NSWorkspace.shared.selectFile(
                row.url.path,
                inFileViewerRootedAtPath: row.url.deletingLastPathComponent().path
            )
        } label: {
            Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
        }

        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(row.url.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }
    }
}

#Preview {
    FileTableView(
        collection: PhotoCollection(
            url: URL(fileURLWithPath: "/tmp"),
            name: "Test",
            isRootFolder: true
        ),
        rootFolderURL: URL(fileURLWithPath: "/tmp"),
        viewModel: RootViewModel()
    )
}
