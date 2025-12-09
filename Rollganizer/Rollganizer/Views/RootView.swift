//
//  RootView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = RootViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            SummaryView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 300, ideal: 500)
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
    }
}

#Preview {
    RootView()
}
