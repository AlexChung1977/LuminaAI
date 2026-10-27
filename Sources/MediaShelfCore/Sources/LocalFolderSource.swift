import Foundation

public actor LocalFolderSource: MediaSource {
    public let config: MediaSourceConfig
    private var state: ConnectionState = .idle
    private let rootURL: URL

    public init(config: MediaSourceConfig) {
        self.config = config
        if config.rootURI.hasPrefix("file:") {
            self.rootURL = URL(string: config.rootURI) ?? URL(fileURLWithPath: config.rootURI)
        } else {
            self.rootURL = URL(fileURLWithPath: config.rootURI)
        }
    }

    public var connectionState: ConnectionState { state }

    public func connect() async throws {
        state = .connecting
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            state = .offline
            throw MediaShelfError.notFound(rootURL.path)
        }
        state = .online
    }

    public func disconnect() async {
        state = .idle
    }

    public func listDirectory(at relativePath: String) async throws -> [DirectoryEntry] {
        try ensureOnline()
        let dir = resolve(relativePath)
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        return names.sorted().compactMap { name -> DirectoryEntry? in
            if name.hasPrefix(".") { return nil }
            let child = dir.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory) else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: child.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value
            let modified = attrs?[.modificationDate] as? Date
            let rel = relativePath.isEmpty ? name : (relativePath as NSString).appendingPathComponent(name)
            return DirectoryEntry(
                name: name,
                path: rel,
                isDirectory: isDirectory.boolValue,
                byteSize: isDirectory.boolValue ? nil : size,
                modifiedAt: modified
            )
        }
    }

    public func readData(at relativePath: String, maxBytes: Int?) async throws -> Data {
        try ensureOnline()
        let url = resolve(relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let maxBytes {
            return try handle.read(upToCount: maxBytes) ?? Data()
        }
        return try handle.readToEnd() ?? Data()
    }

    private func resolve(_ relativePath: String) -> URL {
        if relativePath.isEmpty { return rootURL }
        return rootURL.appendingPathComponent(relativePath)
    }

    private func ensureOnline() throws {
        guard state == .online || state == .degraded else {
            throw MediaShelfError.notConnected
        }
    }
}
