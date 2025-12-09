//
//  SidebarView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        List(selection: $viewModel.selectedCollection) {
            Section("Root Folders") {
                if viewModel.rootFolders.isEmpty {
                    Text("No folders added")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(viewModel.rootFolders) { rootFolder in
                        CollapsibleTreeRow(collection: rootFolder, viewModel: viewModel, level: 0)
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
                .help("Add Root Folder")
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

/// Recursive collapsible tree row for hierarchical folder display
struct CollapsibleTreeRow: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel
    let level: Int

    @State private var isExpanded: Bool = false // Default to collapsed

    var body: some View {
        if collection.children.isEmpty {
            // No children - simple row without disclosure
            CollectionRowLabel(collection: collection, isRootFolder: collection.isRootFolder)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedCollection = collection
                }
                .contextMenu {
                    if collection.isRootFolder {
                        Button(role: .destructive) {
                            viewModel.removeRootFolder(collection)
                        } label: {
                            Label("Remove Folder", systemImage: "trash")
                        }
                    }

                    Button {
                        NSWorkspace.shared.selectFile(collection.url.path, inFileViewerRootedAtPath: collection.url.deletingLastPathComponent().path)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder.circle")
                    }
                }
                .tag(collection as PhotoCollection?)
        } else {
            // Has children - use disclosure group
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    // Render children
                    ForEach(collection.children) { child in
                        CollapsibleTreeRow(collection: child, viewModel: viewModel, level: level + 1)
                    }
                },
                label: {
                    CollectionRowLabel(collection: collection, isRootFolder: collection.isRootFolder)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedCollection = collection
                        }
                        .contextMenu {
                            if collection.isRootFolder {
                                Button(role: .destructive) {
                                    viewModel.removeRootFolder(collection)
                                } label: {
                                    Label("Remove Folder", systemImage: "trash")
                                }
                            }

                            Button {
                                NSWorkspace.shared.selectFile(collection.url.path, inFileViewerRootedAtPath: collection.url.deletingLastPathComponent().path)
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder.circle")
                            }
                        }
                }
            )
            .tag(collection as PhotoCollection?)
        }
    }
}

/// Label for a collection row showing folder icon, name, and progress
struct CollectionRowLabel: View {
    let collection: PhotoCollection
    let isRootFolder: Bool

    private var progressColor: Color {
        if collection.progress.percentageEdited >= 100 {
            return .green
        } else if collection.progress.percentageEdited >= 50 {
            return .blue
        } else if collection.progress.percentageEdited > 0 {
            return .orange
        } else {
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Folder icon
            Image(systemName: isRootFolder ? "folder.fill" : "folder")
                .foregroundStyle(progressColor)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 4) {
                // Folder name
                Text(collection.name)
                    .font(.body)
                    .lineLimit(1)

                // Stats row
                HStack(spacing: 12) {
                    // Photo count
                    if collection.progress.totalPhotos > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 10))
                            Text("\(collection.progress.totalPhotos)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    // Child folder count
                    if !collection.children.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text("\(collection.children.count)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Progress percentage
                    if collection.progress.totalPhotos > 0 {
                        Text(String(format: "%.0f%%", collection.progress.percentageEdited))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(progressColor)
                    }
                }

                // Progress bar (compact)
                if collection.progress.totalPhotos > 0 {
                    ProgressView(value: collection.progress.percentageEdited, total: 100)
                        .progressViewStyle(.linear)
                        .tint(progressColor)
                        .frame(height: 3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(viewModel: RootViewModel())
    } detail: {
        Text("Detail View")
    }
}
