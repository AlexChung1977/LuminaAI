import SwiftUI
import MediaShelfCore

struct SourceSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: Binding(
            get: { model.selectedSourceId },
            set: { id in Task { await model.selectSource(id) } }
        )) {
            Section("來源") {
                ForEach(model.snapshot.sources) { source in
                    HStack {
                        Image(systemName: icon(for: source.kind))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text(source.kind == .smb ? "LAN · SMB" : source.kind == .webdav ? "外出 · WebDAV" : "本機")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(color(for: model.snapshot.connectionStates[source.id] ?? .idle))
                            .frame(width: 8, height: 8)
                    }
                    .tag(Optional(source.id))
                }
            }
        }
        .navigationTitle("MediaShelf")
        #if os(macOS)
        .frame(minWidth: 200)
        #endif
    }

    private func icon(for kind: SourceKind) -> String {
        switch kind {
        case .localFolder: return "folder"
        case .smb: return "network"
        case .webdav: return "globe"
        }
    }

    private func color(for state: ConnectionState) -> Color {
        switch state {
        case .online: return .green
        case .connecting: return .yellow
        case .degraded: return .orange
        case .offline: return .red
        case .idle: return .gray
        }
    }
}
