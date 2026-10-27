import SwiftUI
import MediaShelfCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    #if os(iOS)
    @State private var tab: Tab = .library
    private enum Tab { case library, browser, sources }
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            SourceSidebar()
        } content: {
            LibraryGridView()
        } detail: {
            if let asset = model.selectedAsset {
                ViewerView(asset: asset)
            } else {
                BrowserPane()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("連線") { Task { await model.connectSelected() } }
                Button("掃描") { Task { await model.scanSelected() } }
                Button("新增來源") { model.showAddSheet = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBar()
        }
        .sheet(isPresented: $model.showAddSheet) {
            AddSourceView()
        }
        #else
        TabView(selection: $tab) {
            NavigationStack {
                LibraryGridView()
                    .navigationTitle("媒體庫")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("掃描") { Task { await model.scanSelected() } }
                        }
                    }
            }
            .tabItem { Label("媒體庫", systemImage: "photo.on.rectangle") }
            .tag(Tab.library)

            NavigationStack {
                BrowserPane()
                    .navigationTitle("瀏覽")
            }
            .tabItem { Label("瀏覽", systemImage: "folder") }
            .tag(Tab.browser)

            NavigationStack {
                SourceSidebar()
                    .navigationTitle("來源")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("新增") { model.showAddSheet = true }
                        }
                    }
            }
            .tabItem { Label("來源", systemImage: "externaldrive") }
            .tag(Tab.sources)
        }
        .sheet(isPresented: $model.showAddSheet) {
            AddSourceView()
        }
        .safeAreaInset(edge: .bottom) {
            StatusBar()
        }
        #endif
    }
}

struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("SMB 區網 · WebDAV 外出")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
