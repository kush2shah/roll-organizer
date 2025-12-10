//
//  FileTableView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/9/25.
//

import SwiftUI

/// Table-based hierarchical view of files with sortable columns
struct FileTableView: View {
    let collection: PhotoCollection
    let rootFolderURL: URL

    @State private var sortOrder = [KeyPathComparator(\FileRow.name)]
    @State private var selection = Set<FileRow.ID>()
    @State private var cachedRows: [FileRow] = []
    @State private var lastCollectionID: UUID?

    var body: some View {
        Table(of: FileRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name") { row in
                HStack(spacing: 4) {
                    // Indentation for hierarchy
                    ForEach(0..<row.level, id: \.self) { _ in
                        Spacer()
                            .frame(width: 16)
                    }

                    if row.isFolder {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }

                    Text(row.name)
                        .font(row.isFolder ? .body.weight(.medium) : .body)
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
            // Rebuild rows asynchronously when collection changes
            await rebuildRows()
        }
    }

    private var sortedRows: [FileRow] {
        cachedRows.sorted(using: sortOrder)
    }

    private func rebuildRows() async {
        // Build rows on background queue to avoid blocking UI
        let rows = await Task.detached {
            buildFileRows(from: collection, level: 0)
        }.value
        cachedRows = rows
    }

    /// Build file rows from collection - only current folder, not recursive
    private nonisolated func buildFileRows(from collection: PhotoCollection, level: Int) -> [FileRow] {
        var rows: [FileRow] = []

        // Add child folders (but not their contents)
        for child in collection.children {
            rows.append(FileRow(
                id: child.id,
                name: child.name,
                level: level,
                isFolder: true,
                url: child.url,
                statusIcon: AnyView(EmptyView()),
                statusText: "",
                fileTypeDisplay: "",
                variantCount: 0,
                dateModified: nil
            ))
        }

        // Add photos in this collection only
        for photo in collection.photos {
            rows.append(FileRow(
                id: photo.id,
                name: photo.fileName,
                level: level,
                isFolder: false,
                url: photo.url,
                statusIcon: AnyView(statusIcon(for: photo)),
                statusText: statusText(for: photo),
                fileTypeDisplay: fileTypeDisplay(for: photo),
                variantCount: photo.editedVariants.count + photo.inCameraJPEGs.count,
                dateModified: fileModificationDate(for: photo.url)
            ))
        }

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
        rootFolderURL: URL(fileURLWithPath: "/tmp")
    )
}
