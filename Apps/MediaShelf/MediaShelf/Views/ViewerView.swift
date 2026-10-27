import SwiftUI
import MediaShelfCore

struct ViewerView: View {
    let asset: MediaAsset
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: asset.kind == .video ? "play.rectangle.fill" : "photo.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(asset.displayName)
                .font(.title2.weight(.semibold))
            Text(asset.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(byteSize)
                .font(.caption)
                .foregroundStyle(.secondary)
            if asset.kind == .video {
                Text("影片播放器將接 AVPlayer；初版先顯示中繼資料。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            #if os(macOS)
            Button("關閉預覽") { model.selectedAsset = nil }
                .keyboardShortcut(.cancelAction)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("檢視")
    }

    private var byteSize: String {
        ByteCountFormatter.string(fromByteCount: asset.byteSize, countStyle: .file)
    }
}
