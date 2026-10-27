import Foundation

public struct LibrarySnapshot: Sendable, Equatable {
    public var sources: [MediaSourceConfig]
    public var assets: [MediaAsset]
    public var connectionStates: [UUID: ConnectionState]

    public init(
        sources: [MediaSourceConfig] = [],
        assets: [MediaAsset] = [],
        connectionStates: [UUID: ConnectionState] = [:]
    ) {
        self.sources = sources
        self.assets = assets
        self.connectionStates = connectionStates
    }
}

public actor LibraryService {
    public let index: MediaIndexStore
    public let indexer: MediaIndexer
    public let thumbnails: ThumbnailService
    public let credentials: CredentialStore

    private var liveSources: [UUID: any MediaSource] = [:]
    private let supportDirectory: URL

    public init(supportDirectory: URL, credentials: CredentialStore = SharedCredentialStore()) {
        self.supportDirectory = supportDirectory
        self.credentials = credentials
        let indexURL = supportDirectory.appendingPathComponent("index.json")
        let thumbDir = supportDirectory.appendingPathComponent("Thumbs", isDirectory: true)
        self.index = MediaIndexStore(fileURL: indexURL)
        self.indexer = MediaIndexer(index: index)
        self.thumbnails = ThumbnailService(index: index, cacheDirectory: thumbDir)
    }

    public func bootstrap() async throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try await index.load()
        for source in await index.allSources() {
            _ = try? await activate(config: source)
        }
    }

    public func snapshot(sourceId: UUID? = nil, kind: MediaKind? = nil) async -> LibrarySnapshot {
        let sources = await index.allSources()
        let assets = await index.assets(sourceId: sourceId, kind: kind)
        var states: [UUID: ConnectionState] = [:]
        for source in sources {
            if let live = liveSources[source.id] {
                states[source.id] = await live.connectionState
            } else {
                states[source.id] = .idle
            }
        }
        return LibrarySnapshot(sources: sources, assets: assets, connectionStates: states)
    }

    @discardableResult
    public func addSource(
        name: String,
        kind: SourceKind,
        rootURI: String,
        username: String? = nil,
        password: String? = nil
    ) async throws -> MediaSourceConfig {
        let account: String? = {
            guard password != nil else { return nil }
            return "mediashelf.\(kind.rawValue).\(UUID().uuidString)"
        }()
        if let password, let account {
            try credentials.savePassword(password, account: account)
        }

        let config = MediaSourceConfig(
            name: name,
            kind: kind,
            rootURI: rootURI,
            username: username,
            credentialAccount: account
        )
        await index.upsertSource(config)
        try await index.save()
        _ = try await activate(config: config)
        return config
    }

    public func removeSource(id: UUID) async throws {
        if let live = liveSources.removeValue(forKey: id) {
            await live.disconnect()
        }
        if let config = await index.source(id: id), let account = config.credentialAccount {
            try? credentials.deletePassword(account: account)
        }
        await index.deleteSource(id: id)
        try await index.save()
    }

    public func connect(sourceId: UUID) async throws {
        guard let config = await index.source(id: sourceId) else {
            throw MediaShelfError.notFound(sourceId.uuidString)
        }
        let source = try await activate(config: config)
        try await source.connect()
    }

    public func scan(sourceId: UUID, recursive: Bool = true) async throws -> ScanProgress {
        guard let source = liveSources[sourceId] else {
            throw MediaShelfError.notConnected
        }
        let scanState = await source.connectionState
        if scanState == .idle || scanState == .offline {
            try await source.connect()
        }
        let progress = try await indexer.scan(source: source, recursive: recursive)
        await thumbnails.processQueue(sourceProvider: { [weak self] id in
            await self?.liveSources[id]
        })
        return progress
    }

    public func listDirectory(sourceId: UUID, path: String) async throws -> [DirectoryEntry] {
        guard let source = liveSources[sourceId] else {
            throw MediaShelfError.notConnected
        }
        let listState = await source.connectionState
        if listState != .online && listState != .degraded {
            try await source.connect()
        }
        return try await source.listDirectory(at: path)
    }

    public func processThumbnails(limit: Int = 40) async {
        await thumbnails.processQueue(
            sourceProvider: { [weak self] id in
                await self?.liveSources[id]
            },
            limit: limit
        )
    }

    public func thumbPath(assetId: UUID, variant: ThumbVariant) async -> String? {
        await thumbnails.thumbURL(assetId: assetId, variant: variant)?.path
    }

    /// Seeds a demo SMB LAN source + optional local folder for first-run UX.
    public func installDemoSources(localFolder: String? = nil) async throws {
        let existing = await index.allSources()
        if existing.contains(where: { $0.kind == .smb && $0.name == "NAS · LAN (Demo)" }) == false {
            _ = try await addSource(
                name: "NAS · LAN (Demo)",
                kind: .smb,
                rootURI: "smb://nas.local/media",
                username: "demo",
                password: "demo"
            )
        }
        if existing.contains(where: { $0.kind == .webdav && $0.name == "NAS · Away (WebDAV Demo)" }) == false {
            // Not auto-connected; user fills real URL later. Stored as template-less — skip if no server.
            // Provide a bookmark-style placeholder source using local simulation via invalid host is confusing.
            // Instead only document in UI. Optional: add when user taps.
        }
        if let localFolder {
            let already = existing.contains { $0.kind == .localFolder && $0.rootURI.contains(localFolder) }
            if already == false {
                _ = try await addSource(
                    name: "本機資料夾",
                    kind: .localFolder,
                    rootURI: localFolder
                )
            }
        }
    }

    private func activate(config: MediaSourceConfig) async throws -> any MediaSource {
        if let existing = liveSources[config.id] { return existing }
        let source = try MediaSourceFactory.make(config: config, credentials: credentials)
        liveSources[config.id] = source
        return source
    }
}
