import SwiftUI

struct UURemoteCloneApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(app)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)

        Window("远程控制", id: "remote") {
            RemoteWindowView()
                .environmentObject(app)
        }
        .defaultSize(width: 1280, height: 800)
    }
}

@main
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--agent") {
            AgentRuntime.run()
        } else {
            UURemoteCloneApp.main()
        }
    }
}
