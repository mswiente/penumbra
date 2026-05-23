import SwiftUI

struct MenuView: View {
    @ObservedObject var manager: DisplayManager

    var body: some View {
        if manager.externalDisplays.isEmpty {
            Text("No external displays").disabled(true)
        } else {
            ForEach(manager.externalDisplays) { display in
                Button {
                    manager.toggleMirror(display)
                } label: {
                    Label(
                        display.isMirrored ? "Show \(display.name)" : "Hide \(display.name)",
                        systemImage: display.isMirrored ? "eye" : "eye.slash"
                    )
                }
            }
        }
        Divider()
        Button("Refresh") { manager.refresh() }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
