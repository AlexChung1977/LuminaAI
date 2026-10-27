import Foundation
import MediaShelfCore

@main
struct MediaShelfCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"

        do {
            switch command {
            case "help", "-h", "--help":
                printHelp()
            case "demo":
                try await runDemo()
            case "scan-local":
                guard args.count >= 2 else {
                    fputs("usage: mediashelf-cli scan-local <folder>\n", stderr)
                    Foundation.exit(2)
                }
                try await scanLocal(path: args[1])
            default:
                fputs("Unknown command: \(command)\n", stderr)
                printHelp()
                Foundation.exit(2)
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print(
            """
            MediaShelf CLI

            Commands:
              demo                 Seed demo SMB LAN source, scan, build thumbs
              scan-local <folder>  Index a local folder as a media source
              help                 Show this help

            Strategy:
              LAN  -> SMB (primary)
              Away -> WebDAV (fallback)
            """
        )
    }

    static func runDemo() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediashelf-demo-\(UUID().uuidString)", isDirectory: true)
        let library = LibraryService(supportDirectory: support)
        try await library.bootstrap()
        try await library.installDemoSources()

        let sources = await library.snapshot().sources
        guard let smb = sources.first(where: { $0.kind == .smb }) else {
            throw MediaShelfError.io("Demo SMB source missing")
        }

        print("Connecting SMB demo \(smb.rootURI) ...")
        try await library.connect(sourceId: smb.id)
        print("Scanning ...")
        let progress = try await library.scan(sourceId: smb.id)
        await library.processThumbnails()

        let snap = await library.snapshot(sourceId: smb.id)
        print("Scanned files: \(progress.scannedFiles)")
        print("Assets: \(snap.assets.count)")
        for asset in snap.assets.prefix(10) {
            let thumb = await library.thumbPath(assetId: asset.id, variant: .grid) ?? "(pending)"
            print(" - [\(asset.kind.rawValue)] \(asset.relativePath)  thumb=\(thumb)")
        }
        print("Index: \(support.path)")
    }

    static func scanLocal(path: String) async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediashelf-local-\(UUID().uuidString)", isDirectory: true)
        let library = LibraryService(supportDirectory: support)
        try await library.bootstrap()
        let source = try await library.addSource(
            name: URL(fileURLWithPath: path).lastPathComponent,
            kind: .localFolder,
            rootURI: path
        )
        try await library.connect(sourceId: source.id)
        let progress = try await library.scan(sourceId: source.id)
        await library.processThumbnails()
        let snap = await library.snapshot(sourceId: source.id)
        print("folder=\(path)")
        print("scanned=\(progress.scannedFiles) assets=\(snap.assets.count)")
        for asset in snap.assets.prefix(20) {
            print(" - \(asset.relativePath)")
        }
    }
}
