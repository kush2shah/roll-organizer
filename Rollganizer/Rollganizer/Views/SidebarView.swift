//
//  SidebarView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import SwiftUI

// MARK: - Sidebar Colors
private enum SidebarColors {
    static let complete = Color.green
    static let partial = Color.accentColor
    static let started = Color.orange
    static let empty = Color(nsColor: .tertiaryLabelColor)
}

struct SidebarView: View {
    @ObservedObject var viewModel: RootViewModel
    @State private var selection: PhotoCollection.ID?
    @State private var expandedFolders = Set<UUID>()

    var body: some View {
        Group {
            if viewModel.rootFolders.isEmpty {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a folder to get started")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(selection: $selection) {
                    ForEach(viewModel.rootFolders) { rootFolder in
                        FolderTreeRow(
                            collection: rootFolder,
                            viewModel: viewModel,
                            expandedFolders: $expandedFolders,
                            level: 0
                        )
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selection) { oldValue, newValue in
                    // Only update if selection actually changed and is different from viewModel
                    if let newValue = newValue, newValue != viewModel.selectedCollection?.id {
                        // Find the collection with this ID
                        for rootFolder in viewModel.rootFolders {
                            if let found = findCollection(id: newValue, in: rootFolder) {
                                viewModel.selectedCollection = found

                                // Check if this folder needs JPEG classification
                                if found.needsJPEGClassification {
                                    viewModel.pendingJPEGCollection = found
                                    viewModel.pendingJPEGFolderName = found.name
                                }
                                break
                            }
                        }
                    }
                }
                .onChange(of: viewModel.selectedCollection) { oldValue, newValue in
                    // Sync selection with viewModel
                    if selection != newValue?.id {
                        selection = newValue?.id
                    }

                    // Auto-expand parent folders to reveal the selected folder
                    if let newValue = newValue {
                        expandParentFolders(for: newValue)
                    }
                }
            }
        }
        .navigationTitle("Photo Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.selectFolder()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Root Folder (⌘O)")
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private func findCollection(id: UUID, in collection: PhotoCollection) -> PhotoCollection? {
        if collection.id == id {
            return collection
        }
        for child in collection.children {
            if let found = findCollection(id: id, in: child) {
                return found
            }
        }
        return nil
    }

    /// Find the path of parent IDs needed to reach the target collection
    private func findParentPath(for target: PhotoCollection, in collection: PhotoCollection, currentPath: [UUID] = []) -> [UUID]? {
        if collection.id == target.id {
            return currentPath
        }

        for child in collection.children {
            let newPath = currentPath + [collection.id]
            if let found = findParentPath(for: target, in: child, currentPath: newPath) {
                return found
            }
        }

        return nil
    }

    /// Expand all parent folders needed to show the target collection
    private func expandParentFolders(for target: PhotoCollection) {
        // Find which root folder contains the target
        for rootFolder in viewModel.rootFolders {
            if let parentPath = findParentPath(for: target, in: rootFolder) {
                // Expand all folders in the path
                for parentID in parentPath {
                    expandedFolders.insert(parentID)
                }
                break
            }
        }
    }
}

/// Recursive folder tree row with disclosure control
struct FolderTreeRow: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel
    @Binding var expandedFolders: Set<UUID>
    let level: Int

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedFolders.contains(collection.id) },
            set: { newValue in
                if newValue {
                    expandedFolders.insert(collection.id)
                } else {
                    expandedFolders.remove(collection.id)
                }
            }
        )
    }

    var body: some View {
        if collection.children.isEmpty {
            // Leaf node - no disclosure
            FolderRowContent(collection: collection, viewModel: viewModel)
        } else {
            // Node with children - use disclosure group
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(collection.children) { child in
                    FolderTreeRow(
                        collection: child,
                        viewModel: viewModel,
                        expandedFolders: $expandedFolders,
                        level: level + 1
                    )
                }
            } label: {
                FolderRowContent(collection: collection, viewModel: viewModel)
            }
        }
    }
}

/// Content for a folder row in the outline
struct FolderRowContent: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel

    private var progressColor: Color {
        let pct = collection.progress.percentageEdited
        if pct >= 100 {
            return SidebarColors.complete
        } else if pct >= 50 {
            return SidebarColors.partial
        } else if pct > 0 {
            return SidebarColors.started
        } else {
            return SidebarColors.empty
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Folder icon with subtle badge
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: collection.isRootFolder ? "folder.fill" : "folder")
                    .foregroundStyle(progressColor)
                    .font(.system(size: 14))

                // Completion dot for root folders
                if collection.isRootFolder && collection.progress.percentageEdited >= 100 {
                    Circle()
                        .fill(SidebarColors.complete)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: 2)
                }
            }

            Text(collection.name)
                .lineLimit(1)
                .font(.system(size: 13))

            Spacer()

            // Compact progress indicator
            if collection.progress.totalPhotos > 0 {
                HStack(spacing: 4) {
                    // Mini progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(nsColor: .separatorColor))
                            Capsule()
                                .fill(progressColor)
                                .frame(width: geo.size.width * CGFloat(collection.progress.percentageEdited / 100))
                        }
                    }
                    .frame(width: 24, height: 4)

                    Text("\(collection.progress.editedPhotos)")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            if collection.isRootFolder {
                Button(role: .destructive) {
                    viewModel.removeRootFolder(collection)
                } label: {
                    Label("Remove Folder", systemImage: "trash")
                }

                Divider()
            }

            Button {
                NSWorkspace.shared.selectFile(
                    collection.url.path,
                    inFileViewerRootedAtPath: collection.url.deletingLastPathComponent().path
                )
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
            }
        }
    }
}


#Preview {
    NavigationSplitView {
        SidebarView(viewModel: RootViewModel())
    } detail: {
        Text("Detail View")
    }
}
