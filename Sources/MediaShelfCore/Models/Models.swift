import Foundation

public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case localFolder
    case smb
    case webdav
}

public enum ConnectionState: String, Codable, Sendable {
    case idle
    case connecting
    case online
    case degraded
    case offline
}

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case unknown
}

public enum ThumbVariant: String, Codable, Sendable, CaseIterable {
    case tiny
    case grid
    case preview

    public var maxEdge: Int {
        switch self {
        case .tiny: return 96
        case .grid: return 512
        case .preview: return 1600
        }
    }
}

public enum ThumbStatus: String, Codable, Sendable {
    case pending
    case ready
    case failed
}

public struct MediaSourceConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: SourceKind
    public var rootURI: String
    public var username: String?
    /// Credential reference only — never persist raw passwords in the index DB.
    public var credentialAccount: String?
    public var createdAt: Date
    public var lastScanAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SourceKind,
        rootURI: String,
        username: String? = nil,
        credentialAccount: String? = nil,
        createdAt: Date = Date(),
        lastScanAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rootURI = rootURI
        self.username = username
        self.credentialAccount = credentialAccount
        self.createdAt = createdAt
        self.lastScanAt = lastScanAt
    }
}

public struct MediaAsset: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var sourceId: UUID
    public var relativePath: String
    public var displayName: String
    public var kind: MediaKind
    public var byteSize: Int64
    public var modifiedAt: Date
    public var width: Int?
    public var height: Int?
    public var durationSeconds: Double?

    public init(
        id: UUID = UUID(),
        sourceId: UUID,
        relativePath: String,
        displayName: String,
        kind: MediaKind,
        byteSize: Int64,
        modifiedAt: Date,
        width: Int? = nil,
        height: Int? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.relativePath = relativePath
        self.displayName = displayName
        self.kind = kind
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
    }
}

public struct ThumbRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var assetId: UUID
    public var variant: ThumbVariant
    public var status: ThumbStatus
    public var filePath: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        assetId: UUID,
        variant: ThumbVariant,
        status: ThumbStatus = .pending,
        filePath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assetId = assetId
        self.variant = variant
        self.status = status
        self.filePath = filePath
        self.updatedAt = updatedAt
    }
}

public struct DirectoryEntry: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var byteSize: Int64?
    public var modifiedAt: Date?

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        byteSize: Int64? = nil,
        modifiedAt: Date? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }
}

public struct ScanProgress: Sendable, Equatable {
    public var scannedFiles: Int
    public var discoveredAssets: Int
    public var currentPath: String?

    public init(scannedFiles: Int = 0, discoveredAssets: Int = 0, currentPath: String? = nil) {
        self.scannedFiles = scannedFiles
        self.discoveredAssets = discoveredAssets
        self.currentPath = currentPath
    }
}

public enum MediaShelfError: Error, Sendable, LocalizedError {
    case invalidURI(String)
    case notConnected
    case unsupported(String)
    case io(String)
    case authFailed
    case notFound(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURI(let value): return "Invalid URI: \(value)"
        case .notConnected: return "Source is not connected"
        case .unsupported(let value): return "Unsupported: \(value)"
        case .io(let value): return value
        case .authFailed: return "Authentication failed"
        case .notFound(let value): return "Not found: \(value)"
        case .database(let value): return "Database error: \(value)"
        }
    }
}

public enum MediaKindDetector {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "raw", "dng",
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "mts", "m2ts", "mpg", "mpeg",
    ]

    public static func detect(fileName: String) -> MediaKind {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return .unknown
    }
}
