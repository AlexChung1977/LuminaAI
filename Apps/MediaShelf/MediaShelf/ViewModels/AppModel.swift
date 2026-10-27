import Foundation
import SwiftUI
import MediaShelfCore

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot = LibrarySnapshot()
    @Published var selectedSourceId: UUID?
    @Published var browserPath: String = ""
    @Published var browserEntries: [DirectoryEntry] = []
    @Published var selectedAsset: MediaAsset?
    @Published var statusMessage: String = "準備中"
    @Published var isBusy = false
    @Published var showAddSheet = false

    let library: LibraryService

    init(library: LibraryService? = nil) {
        if let library {
            self.library = library
        } else {
            let support = Self.defaultSupportDirectory()
            self.library = LibraryService(supportDirectory: support)
        }
    }

    func bootstrap() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await library.bootstrap()
            if await library.snapshot().sources.isEmpty {
                try await library.installDemoSources()
            }
            await refresh()
            statusMessage = "就緒 · LAN 用 SMB，外出用 WebDAV"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refresh() async {
        snapshot = await library.snapshot(sourceId: selectedSourceId)
        if selectedSourceId == nil {
            selectedSourceId = snapshot.sources.first?.id
        }
    }

    func selectSource(_ id: UUID?) async {
        selectedSourceId = id
        browserPath = ""
        selectedAsset = nil
        await refresh()
        await reloadBrowser()
    }

    func connectSelected() async {
        guard let id = selectedSourceId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await library.connect(sourceId: id)
            statusMessage = "已連線"
            await refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func scanSelected() async {
        guard let id = selectedSourceId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            statusMessage = "掃描中…"
            let progress = try await library.scan(sourceId: id)
            await library.processThumbnails()
            await refresh()
            statusMessage = "掃描完成 · \(progress.discoveredAssets) 筆新媒體 · 共掃 \(progress.scannedFiles) 項"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reloadBrowser() async {
        guard let id = selectedSourceId else {
            browserEntries = []
            return
        }
        do {
            browserEntries = try await library.listDirectory(sourceId: id, path: browserPath)
        } catch {
            browserEntries = []
            statusMessage = error.localizedDescription
        }
    }

    func openBrowserEntry(_ entry: DirectoryEntry) async {
        if entry.isDirectory {
            browserPath = entry.path
            await reloadBrowser()
        } else if let asset = snapshot.assets.first(where: { $0.relativePath == entry.path }) {
            selectedAsset = asset
        }
    }

    func goUpBrowser() async {
        guard browserPath.isEmpty == false else { return }
        browserPath = (browserPath as NSString).deletingLastPathComponent
        if browserPath == "." { browserPath = "" }
        await reloadBrowser()
    }

    func addSource(
        name: String,
        kind: SourceKind,
        rootURI: String,
        username: String,
        password: String
    ) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let source = try await library.addSource(
                name: name,
                kind: kind,
                rootURI: rootURI,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password
            )
            showAddSheet = false
            await selectSource(source.id)
            statusMessage = "已新增來源 \(name)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static func defaultSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MediaShelf", isDirectory: true)
    }
}
