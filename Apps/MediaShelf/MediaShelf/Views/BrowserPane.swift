import SwiftUI
import MediaShelfCore

struct BrowserPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Task { await model.goUpBrowser() }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(model.browserPath.isEmpty)

                Text(model.browserPath.isEmpty ? "/" : model.browserPath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                Button("重新整理") {
                    Task { await model.reloadBrowser() }
                }
            }
            .padding(10)

            List(model.browserEntries) { entry in
                Button {
                    Task { await model.openBrowserEntry(entry) }
                } label: {
                    Label(
                        entry.name,
                        systemImage: entry.isDirectory ? "folder.fill" : icon(for: entry.name)
                    )
                }
            }
        }
        .task {
            await model.reloadBrowser()
        }
        .navigationTitle("資料夾")
    }

    private func icon(for name: String) -> String {
        switch MediaKindDetector.detect(fileName: name) {
        case .image: return "photo"
        case .video: return "video"
        case .unknown: return "doc"
        }
    }
}
