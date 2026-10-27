import SwiftUI
import MediaShelfCore

@main
struct MediaShelfApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    await model.bootstrap()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}
