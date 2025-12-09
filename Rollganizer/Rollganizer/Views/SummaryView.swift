//
//  SummaryView.swift
//  Rollganizer
//
//  Created by Kush Shah on 12/7/25.
//

import SwiftUI

struct SummaryView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        Group {
            if viewModel.isScanning {
                ProgressView("Scanning directory...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let collection = viewModel.selectedCollection {
                CollectionDetailView(collection: collection, viewModel: viewModel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Collection Selected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Choose a folder to scan using ⌘O")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.selectedCollection?.name ?? "Summary")
        .sheet(item: $viewModel.pendingJPEGCollection) { collection in
            JPEGClassificationSheet(collection: collection, viewModel: viewModel)
        }
    }
}

struct CollectionDetailView: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel

    private var inCameraJPEGCount: Int {
        collection.photos.filter { photo in
            if case .inCameraJPEG = photo.editStatus {
                return true
            }
            return false
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Progress Card
                ProgressCard(progress: collection.progress)
                    .padding(.horizontal)

                // In-Camera JPEG Warning
                if inCameraJPEGCount > 0 {
                    InCameraJPEGNotice(count: inCameraJPEGCount)
                        .padding(.horizontal)
                }

                // Subdirectories Section
                if !collection.children.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Subdirectories (\(collection.children.count))")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVStack(spacing: 8) {
                            ForEach(collection.children) { childCollection in
                                SubdirectoryRow(collection: childCollection, viewModel: viewModel)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Photos Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Photos (\(collection.photos.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVStack(spacing: 4) {
                        ForEach(collection.photos) { photo in
                            PhotoRow(photo: photo)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct InCameraJPEGNotice: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("In-Camera JPEGs Detected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(count) photo\(count == 1 ? "" : "s") \(count == 1 ? "has" : "have") JPEG files created by the camera (RAW+JPEG mode). These are not counted as edited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProgressCard: View {
    let progress: CollectionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Editing Progress")
                        .font(.headline)
                    Text("\(progress.editedPhotos) of \(progress.totalPhotos) edited")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f%%", progress.percentageEdited))
                    .font(.system(.title, design: .rounded))
                    .bold()
                    .foregroundStyle(progress.percentageEdited > 50 ? .green : .orange)
            }

            ProgressView(value: progress.percentageEdited, total: 100)
                .tint(progress.percentageEdited > 50 ? .green : .orange)
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SubdirectoryRow: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectedCollection = collection
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(collection.name)
                            .font(.body)

                        // Show photo count and progress
                        if collection.progress.totalPhotos > 0 {
                            HStack(spacing: 8) {
                                Text("\(collection.progress.totalPhotos) photos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(String(format: "%.0f%% edited", collection.progress.percentageEdited))
                                    .font(.caption)
                                    .foregroundStyle(collection.progress.percentageEdited > 0 ? .green : .secondary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Reveal in Finder button
            Button {
                NSWorkspace.shared.selectFile(collection.url.path, inFileViewerRootedAtPath: collection.url.deletingLastPathComponent().path)
            } label: {
                Image(systemName: "folder.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct PhotoRow: View {
    let photo: Photo

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon
                .font(.system(size: 16))

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.fileName)
                    .font(.body)

                statusText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Variant count
            variantInfo

            // Reveal in Finder button
            Button {
                NSWorkspace.shared.selectFile(photo.url.path, inFileViewerRootedAtPath: photo.url.deletingLastPathComponent().path)
            } label: {
                Image(systemName: "folder.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
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

    @ViewBuilder
    private var statusText: some View {
        switch photo.editStatus {
        case .edited(let method):
            Text(method.rawValue)
        case .inCameraJPEG:
            Text("In-Camera JPEG (RAW+JPEG mode)")
        case .standaloneJPEG(let classification):
            Text(classification.rawValue)
        case .unedited:
            Text("Not edited")
        }
    }

    @ViewBuilder
    private var variantInfo: some View {
        if !photo.editedVariants.isEmpty {
            Text("\(photo.editedVariants.count) variant\(photo.editedVariants.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !photo.inCameraJPEGs.isEmpty {
            Text("+ JPEG")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}


struct JPEGClassificationSheet: View {
    let collection: PhotoCollection
    @ObservedObject var viewModel: RootViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("JPEG-Only Folder Detected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This folder contains \(collection.photos.count) JPEG file\(collection.photos.count == 1 ? "" : "s") with no RAW files.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Description
            Text("How should these photos be counted in your progress?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Options
            VStack(spacing: 12) {
                ClassificationButton(
                    title: "Edited Export",
                    description: "These are edited JPEGs (exported from RAW or edited directly)",
                    icon: "checkmark.circle.fill",
                    color: .green
                ) {
                    viewModel.classifyJPEGs(as: .editedExport)
                    dismiss()
                }

                ClassificationButton(
                    title: "Final (SOOC)",
                    description: "These are final images, intentionally kept as-is (e.g., Fuji film simulations)",
                    icon: "checkmark.circle.fill",
                    color: .blue
                ) {
                    viewModel.classifyJPEGs(as: .finalSOOC)
                    dismiss()
                }

                ClassificationButton(
                    title: "Needs Editing",
                    description: "These JPEGs still need to be edited",
                    icon: "circle",
                    color: .secondary
                ) {
                    viewModel.classifyJPEGs(as: .needsEditing)
                    dismiss()
                }
            }
            .padding(.horizontal)
        }
        .frame(width: 500)
        .padding(.bottom, 20)
    }
}

struct ClassificationButton: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SummaryView(viewModel: RootViewModel())
}
