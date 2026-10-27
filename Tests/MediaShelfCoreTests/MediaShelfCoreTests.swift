import XCTest
@testable import MediaShelfCore

final class MediaShelfCoreTests: XCTestCase {
    func testMediaKindDetection() {
        XCTAssertEqual(MediaKindDetector.detect(fileName: "a.JPG"), .image)
        XCTAssertEqual(MediaKindDetector.detect(fileName: "b.heic"), .image)
        XCTAssertEqual(MediaKindDetector.detect(fileName: "c.mp4"), .video)
        XCTAssertEqual(MediaKindDetector.detect(fileName: "readme.txt"), .unknown)
    }

    func testSMBLocationParsing() throws {
        let loc = try SMBLocation.parse(uri: "smb://nas.local/media/Photos")
        XCTAssertEqual(loc.host, "nas.local")
        XCTAssertEqual(loc.share, "media")
        XCTAssertEqual(loc.pathInsideShare, "Photos")
    }

    func testSimulatedSMBScanAndThumbs() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediashelf-test-\(UUID().uuidString)", isDirectory: true)
        let library = LibraryService(supportDirectory: support)
        try await library.bootstrap()
        try await library.installDemoSources()

        let sources = await library.snapshot().sources
        guard let smb = sources.first(where: { $0.kind == .smb }) else {
            return XCTFail("missing demo SMB source")
        }
        try await library.connect(sourceId: smb.id)
        let progress = try await library.scan(sourceId: smb.id)
        XCTAssertGreaterThan(progress.scannedFiles, 0)

        await library.processThumbnails()
        let assets = await library.snapshot(sourceId: smb.id).assets
        XCTAssertFalse(assets.isEmpty)
        XCTAssertTrue(assets.contains { $0.kind == .image })
        XCTAssertTrue(assets.contains { $0.kind == .video })

        guard let first = assets.first else {
            return XCTFail("expected assets")
        }
        let thumb = await library.thumbPath(assetId: first.id, variant: .grid)
        XCTAssertNotNil(thumb)
    }

    func testLocalFolderSource() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediashelf-local-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let imageURL = folder.appendingPathComponent("shot.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: imageURL)

        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediashelf-idx-\(UUID().uuidString)", isDirectory: true)
        let library = LibraryService(supportDirectory: support)
        try await library.bootstrap()
        let source = try await library.addSource(
            name: "Temp",
            kind: .localFolder,
            rootURI: folder.path
        )
        try await library.connect(sourceId: source.id)
        let progress = try await library.scan(sourceId: source.id)
        XCTAssertEqual(progress.discoveredAssets, 1)
        let assets = await library.snapshot(sourceId: source.id).assets
        XCTAssertEqual(assets.first?.displayName, "shot.jpg")
    }

    func testWebDAVXMLParser() {
        let xml = """
        <?xml version="1.0"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/remote.php/dav/files/user/Photos/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/remote.php/dav/files/user/Photos/a.jpg</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>a.jpg</d:displayname>
                <d:getcontentlength>1234</d:getcontentlength>
                <d:resourcetype/>
              </d:prop>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """.data(using: .utf8)!

        let entries = WebDAVXMLParser.parseDirectoryEntries(
            xml: xml,
            basePath: "/remote.php/dav/files/user/Photos/",
            relativeRoot: ""
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "a.jpg")
        XCTAssertEqual(entries[0].isDirectory, false)
        XCTAssertEqual(entries[0].byteSize, 1234)
    }
}
