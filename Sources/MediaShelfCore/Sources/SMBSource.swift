import Foundation

/// SMB source for LAN access.
///
/// MVP ships with a pluggable transport:
/// - `SimulatedSMBTransport` for demos/tests
/// - On Apple platforms, replace with AMSMB2-backed transport in a follow-up
public protocol SMBTransport: Sendable {
    func connect(host: String, share: String, username: String?, password: String?) async throws
    func disconnect() async
    func listDirectory(path: String) async throws -> [DirectoryEntry]
    func readFile(path: String, maxBytes: Int?) async throws -> Data
}

public struct SMBLocation: Sendable, Equatable {
    public var host: String
    public var share: String
    public var pathInsideShare: String

    public init(host: String, share: String, pathInsideShare: String = "") {
        self.host = host
        self.share = share
        self.pathInsideShare = pathInsideShare
    }

    /// Parses `smb://host/share/optional/path`
    public static func parse(uri: String) throws -> SMBLocation {
        guard let url = URL(string: uri), url.scheme?.lowercased() == "smb" else {
            throw MediaShelfError.invalidURI(uri)
        }
        let host = url.host ?? ""
        guard host.isEmpty == false else { throw MediaShelfError.invalidURI(uri) }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let share = parts.first, share.isEmpty == false else {
            throw MediaShelfError.invalidURI(uri)
        }
        let remainder = parts.dropFirst().joined(separator: "/")
        return SMBLocation(host: host, share: share, pathInsideShare: remainder)
    }
}

public actor SMBSource: MediaSource {
    public let config: MediaSourceConfig
    private let credentials: CredentialStore
    private let transport: SMBTransport
    private var state: ConnectionState = .idle
    private let location: SMBLocation

    public init(
        config: MediaSourceConfig,
        credentials: CredentialStore,
        transport: SMBTransport = SimulatedSMBTransport.shared
    ) {
        self.config = config
        self.credentials = credentials
        self.transport = transport
        self.location = (try? SMBLocation.parse(uri: config.rootURI))
            ?? SMBLocation(host: "invalid", share: "invalid")
    }

    public var connectionState: ConnectionState { state }

    public func connect() async throws {
        state = .connecting
        do {
            _ = try SMBLocation.parse(uri: config.rootURI)
            let password: String? = {
                guard let account = config.credentialAccount else { return nil }
                return try? credentials.loadPassword(account: account)
            }()
            try await transport.connect(
                host: location.host,
                share: location.share,
                username: config.username,
                password: password
            )
            state = .online
        } catch {
            state = .offline
            throw error
        }
    }

    public func disconnect() async {
        await transport.disconnect()
        state = .idle
    }

    public func listDirectory(at relativePath: String) async throws -> [DirectoryEntry] {
        try ensureOnline()
        let path = joinedPath(relativePath)
        let entries = try await transport.listDirectory(path: path)
        return entries.map { entry in
            let rel: String = {
                if relativePath.isEmpty { return entry.name }
                return (relativePath as NSString).appendingPathComponent(entry.name)
            }()
            return DirectoryEntry(
                name: entry.name,
                path: rel,
                isDirectory: entry.isDirectory,
                byteSize: entry.byteSize,
                modifiedAt: entry.modifiedAt
            )
        }
    }

    public func readData(at relativePath: String, maxBytes: Int?) async throws -> Data {
        try ensureOnline()
        return try await transport.readFile(path: joinedPath(relativePath), maxBytes: maxBytes)
    }

    private func joinedPath(_ relativePath: String) -> String {
        let base = location.pathInsideShare
        if relativePath.isEmpty { return base }
        if base.isEmpty { return relativePath }
        return (base as NSString).appendingPathComponent(relativePath)
    }

    private func ensureOnline() throws {
        guard state == .online || state == .degraded else {
            throw MediaShelfError.notConnected
        }
    }
}

/// In-memory SMB stand-in so LAN UX can be developed before AMSMB2 is wired.
public actor SimulatedSMBTransport: SMBTransport {
    public static let shared = SimulatedSMBTransport()

    private var tree: [String: [DirectoryEntry]] = [:]
    private var files: [String: Data] = [:]
    private var connected = false

    public init() {
        // Default demo share content
        tree[""] = [
            DirectoryEntry(name: "Photos", path: "Photos", isDirectory: true),
            DirectoryEntry(name: "Videos", path: "Videos", isDirectory: true),
            DirectoryEntry(name: "README.txt", path: "README.txt", isDirectory: false, byteSize: 32),
        ]
        tree["Photos"] = [
            DirectoryEntry(name: "IMG_1001.JPG", path: "Photos/IMG_1001.JPG", isDirectory: false, byteSize: 120_000, modifiedAt: Date()),
            DirectoryEntry(name: "IMG_1002.HEIC", path: "Photos/IMG_1002.HEIC", isDirectory: false, byteSize: 240_000, modifiedAt: Date()),
            DirectoryEntry(name: "Trip", path: "Photos/Trip", isDirectory: true),
        ]
        tree["Photos/Trip"] = [
            DirectoryEntry(name: "beach.png", path: "Photos/Trip/beach.png", isDirectory: false, byteSize: 80_000, modifiedAt: Date()),
        ]
        files["README.txt"] = Data("MediaShelf SMB demo share".utf8)
        files["Photos/IMG_1001.JPG"] = Self.jpegPlaceholder(colorSeed: 1)
        files["Photos/IMG_1002.HEIC"] = Self.jpegPlaceholder(colorSeed: 2)
        files["Photos/Trip/beach.png"] = Self.jpegPlaceholder(colorSeed: 3)
        files["Videos/clip.mp4"] = Data(repeating: 0, count: 64)
        tree["Videos"] = [
            DirectoryEntry(
                name: "clip.mp4",
                path: "Videos/clip.mp4",
                isDirectory: false,
                byteSize: 5_000_000,
                modifiedAt: Date()
            ),
        ]
    }

    public func seed(tree: [String: [DirectoryEntry]], files: [String: Data]) {
        self.tree = tree
        self.files = files
    }

    public func connect(host: String, share: String, username: String?, password: String?) async throws {
        if share == "denied" { throw MediaShelfError.authFailed }
        connected = true
    }

    public func disconnect() async {
        connected = false
    }

    public func listDirectory(path: String) async throws -> [DirectoryEntry] {
        guard connected else { throw MediaShelfError.notConnected }
        let key = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let entries = tree[key] else {
            throw MediaShelfError.notFound(path)
        }
        return entries
    }

    public func readFile(path: String, maxBytes: Int?) async throws -> Data {
        guard connected else { throw MediaShelfError.notConnected }
        let key = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let data = files[key] else { throw MediaShelfError.notFound(path) }
        if let maxBytes { return data.prefix(maxBytes) }
        return data
    }

    private nonisolated static func jpegPlaceholder(colorSeed: UInt8) -> Data {
        // Minimal valid-ish JPEG SOI/EOI so image pipelines can fail soft.
        Data([0xFF, 0xD8, 0xFF, 0xD9, colorSeed])
    }
}
