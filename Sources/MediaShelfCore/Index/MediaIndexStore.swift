import Foundation

/// JSON-file backed index for the MVP (portable, no native SQLite glue required).
/// Can be swapped for SQLite/GRDB without changing call sites.
public actor MediaIndexStore {
    private var sources: [UUID: MediaSourceConfig] = [:]
    private var assets: [UUID: MediaAsset] = [:]
    private var thumbs: [UUID: ThumbRecord] = [:]
    private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    public func load() throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        sources = Dictionary(uniqueKeysWithValues: decoded.sources.map { ($0.id, $0) })
        assets = Dictionary(uniqueKeysWithValues: decoded.assets.map { ($0.id, $0) })
        thumbs = Dictionary(uniqueKeysWithValues: decoded.thumbs.map { ($0.id, $0) })
    }

    public func save() throws {
        guard let fileURL else { return }
        let snapshot = Snapshot(
            sources: Array(sources.values),
            assets: Array(assets.values),
            thumbs: Array(thumbs.values)
        )
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Sources

    public func upsertSource(_ source: MediaSourceConfig) {
        sources[source.id] = source
    }

    public func deleteSource(id: UUID) {
        sources.removeValue(forKey: id)
        let assetIds = assets.values.filter { $0.sourceId == id }.map(\.id)
        for assetId in assetIds {
            assets.removeValue(forKey: assetId)
        }
        thumbs = thumbs.filter { assetIds.contains($0.value.assetId) == false }
    }

    public func allSources() -> [MediaSourceConfig] {
        sources.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func source(id: UUID) -> MediaSourceConfig? {
        sources[id]
    }

    // MARK: Assets

    public func upsertAsset(_ asset: MediaAsset) {
        assets[asset.id] = asset
    }

    public func asset(id: UUID) -> MediaAsset? {
        assets[id]
    }

    public func assets(sourceId: UUID? = nil, kind: MediaKind? = nil, pathPrefix: String? = nil) -> [MediaAsset] {
        assets.values.filter { asset in
            if let sourceId, asset.sourceId != sourceId { return false }
            if let kind, asset.kind != kind { return false }
            if let pathPrefix {
                if pathPrefix.isEmpty { return true }
                return asset.relativePath == pathPrefix
                    || asset.relativePath.hasPrefix(pathPrefix + "/")
            }
            return true
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func findAsset(sourceId: UUID, relativePath: String) -> MediaAsset? {
        assets.values.first { $0.sourceId == sourceId && $0.relativePath == relativePath }
    }

    public func removeMissingAssets(sourceId: UUID, keepingPaths: Set<String>) {
        let stale = assets.values.filter { $0.sourceId == sourceId && keepingPaths.contains($0.relativePath) == false }
        for asset in stale {
            assets.removeValue(forKey: asset.id)
            thumbs = thumbs.filter { $0.value.assetId != asset.id }
        }
    }

    // MARK: Thumbs

    public func upsertThumb(_ thumb: ThumbRecord) {
        thumbs[thumb.id] = thumb
    }

    public func thumb(assetId: UUID, variant: ThumbVariant) -> ThumbRecord? {
        thumbs.values.first { $0.assetId == assetId && $0.variant == variant }
    }

    public func pendingThumbs(limit: Int = 50) -> [ThumbRecord] {
        Array(
            thumbs.values
                .filter { $0.status == .pending }
                .sorted { $0.updatedAt < $1.updatedAt }
                .prefix(limit)
        )
    }

    private struct Snapshot: Codable {
        var sources: [MediaSourceConfig]
        var assets: [MediaAsset]
        var thumbs: [ThumbRecord]
    }
}
