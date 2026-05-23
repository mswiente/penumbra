import SwiftUI

@main
struct PenumbraApp: App {
    @StateObject private var manager = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            Image(systemName: manager.anyExternalActive
                  ? "rectangle.on.rectangle"
                  : "rectangle.on.rectangle.slash")
        }
        .menuBarExtraStyle(.menu)
    }
}
