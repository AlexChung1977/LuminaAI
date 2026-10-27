import Foundation

public actor MediaIndexer {
    private let index: MediaIndexStore

    public init(index: MediaIndexStore) {
        self.index = index
    }

    @discardableResult
    public func scan(
        source: any MediaSource,
        recursive: Bool = true,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanProgress {
        var progress = ScanProgress()
        var keptPaths = Set<String>()

        try await walk(
            source: source,
            relativePath: "",
            recursive: recursive,
            progress: &progress,
            keptPaths: &keptPaths,
            onProgress: onProgress
        )

        await index.removeMissingAssets(sourceId: source.config.id, keepingPaths: keptPaths)

        var config = source.config
        config.lastScanAt = Date()
        await index.upsertSource(config)
        try await index.save()
        return progress
    }

    private func walk(
        source: any MediaSource,
        relativePath: String,
        recursive: Bool,
        progress: inout ScanProgress,
        keptPaths: inout Set<String>,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) async throws {
        let entries = try await source.listDirectory(at: relativePath)
        for entry in entries {
            progress.scannedFiles += 1
            progress.currentPath = entry.path
            onProgress?(progress)

            if entry.isDirectory {
                if recursive {
                    try await walk(
                        source: source,
                        relativePath: entry.path,
                        recursive: true,
                        progress: &progress,
                        keptPaths: &keptPaths,
                        onProgress: onProgress
                    )
                }
                continue
            }

            let kind = MediaKindDetector.detect(fileName: entry.name)
            guard kind != .unknown else { continue }

            keptPaths.insert(entry.path)
            if let existing = await index.findAsset(sourceId: source.config.id, relativePath: entry.path) {
                var updated = existing
                updated.byteSize = entry.byteSize ?? existing.byteSize
                updated.modifiedAt = entry.modifiedAt ?? existing.modifiedAt
                updated.kind = kind
                await index.upsertAsset(updated)
                await ensureThumbPlaceholders(assetId: updated.id)
            } else {
                let asset = MediaAsset(
                    sourceId: source.config.id,
                    relativePath: entry.path,
                    displayName: entry.name,
                    kind: kind,
                    byteSize: entry.byteSize ?? 0,
                    modifiedAt: entry.modifiedAt ?? Date()
                )
                await index.upsertAsset(asset)
                await ensureThumbPlaceholders(assetId: asset.id)
                progress.discoveredAssets += 1
            }
        }
    }

    private func ensureThumbPlaceholders(assetId: UUID) async {
        for variant in ThumbVariant.allCases {
            if await index.thumb(assetId: assetId, variant: variant) == nil {
                await index.upsertThumb(ThumbRecord(assetId: assetId, variant: variant, status: .pending))
            }
        }
    }
}
