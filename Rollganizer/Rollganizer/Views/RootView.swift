//
//  RootView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import SwiftUI

struct RootView: View {
    @StateObject private var viewModel: RootViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        self._viewModel = StateObject(wrappedValue: RootViewModel())
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left sidebar: Folder tree
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // Middle: File table with edit status
            if viewModel.isScanning {
                ScanningProgressView(progress: viewModel.scanProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            } else if let collection = viewModel.selectedCollection,
                      let rootURL = viewModel.selectedCollectionRootURL {
                FileTableView(collection: collection, rootFolderURL: rootURL, viewModel: viewModel)
                    .navigationTitle(collection.name)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            } else {
                ContentUnavailableView(
                    "No Collection Selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select a folder from the sidebar")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            }
        } detail: {
            // Right: Thumbnail preview
            if let collection = viewModel.selectedCollection,
               let rootURL = viewModel.selectedCollectionRootURL {
                ThumbnailGridView(photos: collection.photos, rootFolderURL: rootURL)
                    .navigationTitle("Photos")
            } else {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.stack",
                    description: Text("Select a folder to view photos")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .sheet(item: $viewModel.pendingJPEGCollection) { collection in
            JPEGClassificationSheet(collection: collection, viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.selectedCollection == nil || viewModel.isScanning)
            }
        }
        .task {
            // Optionally load saved root folders on first appearance
            // This is commented out to avoid accessing folders without explicit permission
            // Uncomment if you want to restore previously selected folders on launch:
            // await viewModel.loadSavedRootFolders()
        }
    }
}
