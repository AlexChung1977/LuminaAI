import Foundation

public protocol CredentialStore: Sendable {
    func savePassword(_ password: String, account: String) throws
    func loadPassword(account: String) throws -> String?
    func deletePassword(account: String) throws
}

public final class SharedCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func savePassword(_ password: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[account] = password
    }

    public func loadPassword(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[account]
    }

    public func deletePassword(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: account)
    }
}

public protocol MediaSource: Sendable {
    var config: MediaSourceConfig { get }
    var connectionState: ConnectionState { get async }

    func connect() async throws
    func disconnect() async
    func listDirectory(at relativePath: String) async throws -> [DirectoryEntry]
    func readData(at relativePath: String, maxBytes: Int?) async throws -> Data
    /// Optional range read for video keyframes / large files. Default falls back to full read.
    func readData(at relativePath: String, offset: Int64, length: Int) async throws -> Data
}

public extension MediaSource {
    func readData(at relativePath: String, offset: Int64, length: Int) async throws -> Data {
        let data = try await readData(at: relativePath, maxBytes: nil)
        let start = Int(offset)
        guard start < data.count else { return Data() }
        let end = min(data.count, start + length)
        return data.subdata(in: start..<end)
    }
}

public enum MediaSourceFactory {
    public static func make(
        config: MediaSourceConfig,
        credentials: CredentialStore
    ) throws -> any MediaSource {
        switch config.kind {
        case .localFolder:
            return LocalFolderSource(config: config)
        case .smb:
            return SMBSource(config: config, credentials: credentials)
        case .webdav:
            return WebDAVSource(config: config, credentials: credentials)
        }
    }
}
