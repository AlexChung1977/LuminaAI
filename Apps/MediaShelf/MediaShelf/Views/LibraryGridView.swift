import SwiftUI
import MediaShelfCore

struct LibraryGridView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 8)]

    var body: some View {
        ScrollView {
            if model.snapshot.assets.isEmpty {
                ContentUnavailableView(
                    "尚無媒體",
                    systemImage: "photo.stack",
                    description: Text("選一個來源後按「連線」與「掃描」。區網建議 SMB。")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.snapshot.assets) { asset in
                        Button {
                            model.selectedAsset = asset
                        } label: {
                            AssetCell(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle(model.snapshot.sources.first(where: { $0.id == model.selectedSourceId })?.name ?? "媒體庫")
    }
}

struct AssetCell: View {
    let asset: MediaAsset
    @EnvironmentObject private var model: AppModel
    @State private var thumbPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                if asset.kind == .video {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                if let thumbPath {
                    Text(URL(fileURLWithPath: thumbPath).lastPathComponent)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(asset.displayName)
                .font(.caption)
                .lineLimit(1)
        }
        .task(id: asset.id) {
            thumbPath = await model.library.thumbPath(assetId: asset.id, variant: .grid)
        }
    }
}
