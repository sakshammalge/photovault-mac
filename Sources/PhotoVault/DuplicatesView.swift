import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var gallery: GalleryModel
    @StateObject private var model = DuplicateModel()

    var body: some View {
        Group {
            if let progress = model.progress {
                VStack(spacing: 10) {
                    Text(progress.stage).font(.headline)
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 280)
                    Text("\(progress.done) of \(progress.total)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button("Cancel") { model.cancel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasRun {
                VStack(spacing: 10) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
                    Text("Find Duplicates").font(.title2.weight(.semibold))
                    Text("Looks for identical files and for photos that look almost the same.\nIt only reports them. Nothing is deleted or moved.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Scan \(gallery.items.count) Items") { model.scan(gallery.items) }
                        .buttonStyle(.borderedProminent)
                        .disabled(gallery.items.count < 2)
                        .padding(.top, 4)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48, weight: .light)).foregroundStyle(.green)
                    Text("No Duplicates Found").font(.title2.weight(.semibold))
                    Button("Scan Again") { model.scan(gallery.items) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
        }
        .navigationTitle("Duplicates")
        .navigationSubtitle(model.groups.isEmpty ? "" : "\(model.groups.count) groups")
        .toolbar {
            ToolbarItem {
                Button { model.scan(gallery.items) } label: { Image(systemName: "arrow.clockwise") }
                    .help("Scan again")
                    .disabled(model.isRunning)
            }
        }
    }

    private var results: some View {
        List(model.groups) { group in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.kind == .identical ? "Identical files" : "Look alike").font(.headline)
                    Text("\(group.items.count) photos · \(ByteCountFormatter.string(fromByteCount: group.reclaimableBytes, countStyle: .file)) in extra copies")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(group.items) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                ThumbnailCell(item: item).frame(width: 140, height: 140).cornerRadius(6)
                                Text(item.name).font(.caption).lineLimit(1)
                                Text(item.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                                .font(.caption)
                            }
                            .frame(width: 140)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}
