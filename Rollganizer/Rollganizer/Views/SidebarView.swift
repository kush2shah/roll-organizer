//
//  SidebarView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: RootViewModel
    @State private var selection: PhotoCollection.ID?

    var body: some View {
        List(selection: $selection) {
            if viewModel.rootFolders.isEmpty {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a folder to get started")
                )
            } else {
                ForEach(viewModel.rootFolders) { rootFolder in
                    OutlineGroup(rootFolder, children: \.optionalChildren) { collection in
                        FolderRowContent(collection: collection, viewModel: viewModel)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
        .onChange(of: selection) { oldValue, newValue in
            if let newValue = newValue {
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
            selection = newValue?.id
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
}

/// Content for a folder row in the outline
struct FolderRowContent: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel

    private var progressColor: Color {
        if collection.progress.percentageEdited >= 100 {
            return .green
        } else if collection.progress.percentageEdited >= 50 {
            return .blue
        } else if collection.progress.percentageEdited > 0 {
            return .orange
        } else {
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: collection.isRootFolder ? "folder.fill" : "folder")
                .foregroundStyle(progressColor)
                .imageScale(.small)

            Text(collection.name)
                .lineLimit(1)

            Spacer()

            if collection.progress.totalPhotos > 0 {
                Text("\(collection.progress.editedPhotos)/\(collection.progress.totalPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
