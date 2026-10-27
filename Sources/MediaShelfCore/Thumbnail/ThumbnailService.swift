import Foundation

public protocol ThumbnailGenerator: Sendable {
    func generate(from data: Data, kind: MediaKind, variant: ThumbVariant) async throws -> Data
}

/// MVP generator: stores a compact sidecar payload (not a real decode pipeline yet).
/// On Apple platforms this can be replaced with ImageIO / AVFoundation.
public struct PlaceholderThumbnailGenerator: ThumbnailGenerator {
    public init() {}

    public func generate(from data: Data, kind: MediaKind, variant: ThumbVariant) async throws -> Data {
        let prefix = data.prefix(64)
        var payload = Data("MSH1".utf8)
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(variant.maxEdge).bigEndian) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(kind == .video ? 1 : 0).bigEndian) { Array($0) })
        payload.append(prefix)
        return payload
    }
}

public actor ThumbnailService {
    private let index: MediaIndexStore
    private let cacheDirectory: URL
    private let generator: ThumbnailGenerator
    private var isRunning = false

    public init(
        index: MediaIndexStore,
        cacheDirectory: URL,
        generator: ThumbnailGenerator = PlaceholderThumbnailGenerator()
    ) {
        self.index = index
        self.cacheDirectory = cacheDirectory
        self.generator = generator
    }

    public func enqueueVisible(assetIds: [UUID]) async {
        for assetId in assetIds {
            for variant in [ThumbVariant.grid, .tiny] {
                if await index.thumb(assetId: assetId, variant: variant) == nil {
                    await index.upsertThumb(ThumbRecord(assetId: assetId, variant: variant, status: .pending))
                }
            }
        }
    }

    public func processQueue(
        sourceProvider: @escaping @Sendable (UUID) async -> (any MediaSource)?,
        limit: Int = 20
    ) async {
        guard isRunning == false else { return }
        isRunning = true
        defer { isRunning = false }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let pending = await index.pendingThumbs(limit: limit)

        for thumb in pending {
            guard let asset = await index.asset(id: thumb.assetId) else { continue }
            guard let source = await sourceProvider(asset.sourceId) else { continue }
            do {
                let maxRead = thumb.variant == .preview ? 4_000_000 : 1_500_000
                let data = try await source.readData(at: asset.relativePath, maxBytes: maxRead)
                let generated = try await generator.generate(from: data, kind: asset.kind, variant: thumb.variant)
                let fileName = "\(asset.id.uuidString)_\(thumb.variant.rawValue).thumb"
                let fileURL = cacheDirectory.appendingPathComponent(fileName)
                try generated.write(to: fileURL, options: .atomic)

                var ready = thumb
                ready.status = .ready
                ready.filePath = fileURL.path
                ready.updatedAt = Date()
                await index.upsertThumb(ready)
            } catch {
                var failed = thumb
                failed.status = .failed
                failed.updatedAt = Date()
                await index.upsertThumb(failed)
            }
        }
        try? await index.save()
    }

    public func thumbURL(assetId: UUID, variant: ThumbVariant) async -> URL? {
        guard let record = await index.thumb(assetId: assetId, variant: variant),
              record.status == .ready,
              let path = record.filePath
        else { return nil }
        return URL(fileURLWithPath: path)
    }
}
