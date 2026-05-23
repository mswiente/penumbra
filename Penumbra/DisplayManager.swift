import AppKit
import CoreGraphics

struct ExternalDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isMirrored: Bool
}

final class DisplayManager: ObservableObject {
    @Published private(set) var externalDisplays: [ExternalDisplay] = []
    private var builtInID: CGDirectDisplayID?
    private var nameCache: [CGDirectDisplayID: String] = [:]

    var anyExternalActive: Bool {
        externalDisplays.contains { !$0.isMirrored }
    }

    init() {
        refresh()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { manager.refresh() }
        }, ctx)
    }

    func refresh() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        builtInID = ids.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()

        externalDisplays = ids
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .map { id in
                ExternalDisplay(
                    id: id,
                    name: resolvedName(for: id),
                    isMirrored: CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay
                )
            }
    }

    func toggleMirror(_ display: ExternalDisplay) {
        guard let primary = builtInID, primary != display.id else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        let target: CGDirectDisplayID = display.isMirrored ? kCGNullDirectDisplay : primary
        CGConfigureDisplayMirrorOfDisplay(config, display.id, target)
        CGCompleteDisplayConfiguration(config, .forSession)
        refresh()
    }

    private func resolvedName(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               n.uint32Value == id {
                nameCache[id] = screen.localizedName
                return screen.localizedName
            }
        }
        return nameCache[id] ?? "Display \(id)"
    }
}
