import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// WebDAV source for remote / off-LAN access (HTTPS preferred).
public actor WebDAVSource: MediaSource {
    public let config: MediaSourceConfig
    private let credentials: CredentialStore
    private var state: ConnectionState = .idle
    private let session: URLSession
    private let rootURL: URL

    public init(
        config: MediaSourceConfig,
        credentials: CredentialStore,
        session: URLSession = URLSession.shared
    ) {
        self.config = config
        self.credentials = credentials
        self.session = session
        var uri = config.rootURI
        if uri.hasSuffix("/") == false { uri += "/" }
        self.rootURL = URL(string: uri) ?? URL(fileURLWithPath: "/")
    }

    public var connectionState: ConnectionState { state }

    public func connect() async throws {
        state = .connecting
        do {
            _ = try await listDirectory(at: "")
            state = .online
        } catch MediaShelfError.authFailed {
            state = .offline
            throw MediaShelfError.authFailed
        } catch {
            state = .offline
            throw error
        }
    }

    public func disconnect() async {
        state = .idle
    }

    public func listDirectory(at relativePath: String) async throws -> [DirectoryEntry] {
        let url = try makeURL(relativePath: relativePath, isDirectory: true)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:getcontentlength/>
            <d:getlastmodified/>
            <d:resourcetype/>
          </d:prop>
        </d:propfind>
        """.utf8)
        try applyAuth(to: &request)

        // Depth 1 for children
        request.setValue("1", forHTTPHeaderField: "Depth")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let hrefBase = url.path
        return WebDAVXMLParser.parseDirectoryEntries(
            xml: data,
            basePath: hrefBase,
            relativeRoot: relativePath
        )
    }

    public func readData(at relativePath: String, maxBytes: Int?) async throws -> Data {
        let url = try makeURL(relativePath: relativePath, isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let maxBytes {
            request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
        }
        try applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    public func readData(at relativePath: String, offset: Int64, length: Int) async throws -> Data {
        let url = try makeURL(relativePath: relativePath, isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let end = offset + Int64(length) - 1
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
        try applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    private func makeURL(relativePath: String, isDirectory: Bool) throws -> URL {
        guard var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) else {
            throw MediaShelfError.invalidURI(config.rootURI)
        }
        var path = components.path
        if path.hasSuffix("/") == false { path += "/" }
        if relativePath.isEmpty == false {
            let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            path += trimmed.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        }
        if isDirectory && path.hasSuffix("/") == false { path += "/" }
        components.percentEncodedPath = path
        guard let url = components.url else {
            throw MediaShelfError.invalidURI(config.rootURI)
        }
        return url
    }

    private func applyAuth(to request: inout URLRequest) throws {
        guard let account = config.credentialAccount,
              let password = try credentials.loadPassword(account: account),
              let username = config.username
        else { return }
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MediaShelfError.io("Invalid HTTP response")
        }
        switch http.statusCode {
        case 200...299, 207:
            return
        case 401, 403:
            throw MediaShelfError.authFailed
        case 404:
            throw MediaShelfError.notFound(config.rootURI)
        default:
            throw MediaShelfError.io("WebDAV HTTP \(http.statusCode)")
        }
    }
}

enum WebDAVXMLParser {
    static func parseDirectoryEntries(xml: Data, basePath: String, relativeRoot: String) -> [DirectoryEntry] {
        let text = String(decoding: xml, as: UTF8.self)
        // Lightweight response splitting — enough for common NAS WebDAV listings.
        let chunks = text.components(separatedBy: "<d:response>").dropFirst()
        var results: [DirectoryEntry] = []

        for chunk in chunks {
            guard let href = firstTag("d:href", in: chunk)?.removingPercentEncoding else { continue }
            let normalizedHref = href.hasSuffix("/") ? String(href.dropLast()) : href
            let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
            if normalizedHref == normalizedBase || href == basePath { continue }

            let name: String = {
                if let display = firstTag("d:displayname", in: chunk), display.isEmpty == false {
                    return display
                }
                return (normalizedHref as NSString).lastPathComponent
            }()

            let isCollection = chunk.contains("<d:collection") || chunk.contains("<d:collection/>")
            let size: Int64? = {
                guard let raw = firstTag("d:getcontentlength", in: chunk), let value = Int64(raw) else { return nil }
                return value
            }()
            let modified: Date? = {
                guard let raw = firstTag("d:getlastmodified", in: chunk) else { return nil }
                return HTTPDateParser.parse(raw)
            }()

            let childName = name
            let rel: String = {
                if relativeRoot.isEmpty { return childName }
                return (relativeRoot as NSString).appendingPathComponent(childName)
            }()

            results.append(
                DirectoryEntry(
                    name: childName,
                    path: rel,
                    isDirectory: isCollection,
                    byteSize: isCollection ? nil : size,
                    modifiedAt: modified
                )
            )
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func firstTag(_ tag: String, in chunk: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = chunk.range(of: open)?.upperBound,
              let end = chunk.range(of: close)?.lowerBound,
              start < end
        else { return nil }
        return String(chunk[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HTTPDateParser {
    static func parse(_ value: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
