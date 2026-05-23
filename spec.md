# Penumbra — Spec

A small macOS menu bar app that hides and reveals external displays without unplugging cables.

## Problem

One external monitor is shared between two MacBooks (one via USB-C, one via HDMI). The monitor's physical input switch toggles which Mac it shows, but macOS on the unused Mac keeps the external display attached. Windows then drift to that invisible "ghost" display, the cursor wanders off-screen, notifications appear nowhere visible, etc.

Penumbra solves this by giving a one-click way to hide an external display from macOS's perspective and bring it back when needed — without touching cables.

## Goals

- Pure menu bar app, no dock icon, no main window.
- One click per external display to hide/reveal.
- Auto-update when displays are connected/disconnected.
- State persists for the login session.
- Personal tool — not distributed via the App Store.

## Non-goals

- Not a general display management tool. BetterDisplay and Lunar already cover DDC brightness, HDR, custom resolutions, EDID overrides, etc. Do not duplicate them.
- No preferences window initially.
- No multi-user, no telemetry, no auto-updater.

## Platform

- macOS 13.0 (Ventura) or later — required for SwiftUI `MenuBarExtra`.
- Apple Silicon and Intel both supported.
- Swift 5.9+ / Xcode 15+.

## Approach

Two viable strategies. Implement **Strategy A** as the default. **Strategy B** is a stretch goal exposed via a toggle.

### Strategy A — Mirror to built-in (default, public API)

Use public CoreGraphics calls to mirror the external display onto the built-in one. From macOS's perspective the two become one logical display, so no windows can drift to the external. When the user wants to extend again, un-mirror.

Key calls:

- `CGGetActiveDisplayList` — enumerate displays
- `CGDisplayIsBuiltin` — identify the built-in
- `CGBeginDisplayConfiguration`
- `CGConfigureDisplayMirrorOfDisplay(config, externalID, builtInID)` to hide; pass `kCGNullDirectDisplay` as the master to un-mirror
- `CGCompleteDisplayConfiguration(config, .forSession)`

### Strategy B — True disconnect (stretch, private API)

Use the private CoreGraphics symbol `CGSConfigureDisplayEnabled` inside the same begin/complete block. This causes macOS to treat the display as physically disconnected; windows migrate to the remaining display, which Strategy A does not do.

```swift
@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?,
                                _ display: CGDirectDisplayID,
                                _ enabled: Bool) -> CGError
```

Acceptable because this is a personal tool not headed for the App Store. This is what BetterDisplay and Lunar use under the hood.

## UI

Menu bar icon:

- `rectangle.on.rectangle` when all externals are active (extended).
- `rectangle.on.rectangle.slash` when any external is hidden.

Menu contents:

- One entry per external display, labeled `Hide <Name>` or `Show <Name>`, where `<Name>` comes from `NSScreen.localizedName`.
- If no externals are connected: a disabled item "No external displays".
- Divider.
- `Refresh` — re-enumerates displays manually.
- `Quit` — `⌘Q`.

Display change handling:

- Register `CGDisplayRegisterReconfigurationCallback` and refresh state on every event, dispatched to the main queue.

## File layout

```
Penumbra/
├── Penumbra.xcodeproj
└── Penumbra/
    ├── PenumbraApp.swift        # @main, MenuBarExtra scene
    ├── DisplayManager.swift     # CoreGraphics enumeration + mirror/disconnect ops
    ├── MenuView.swift           # SwiftUI menu content
    └── Info.plist
```

Single-file is fine if it stays under ~200 lines; split when it grows.

## Xcode / project setup

- New macOS App, SwiftUI, Swift.
- Deployment target: macOS 13.0.
- `Info.plist`: add `Application is agent (UIElement)` → `YES` (`LSUIElement`). This hides the dock icon.
- Signing & Capabilities: **disable App Sandbox**. Display configuration APIs do not work in the sandbox without entitlements that aren't granted to ordinary developers.
- No additional dependencies for the core feature.

## Starter implementation

This is a working baseline for Strategy A. Adapt and split into files as appropriate.

```swift
import SwiftUI
import CoreGraphics
import AppKit

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
                        display.isMirrored
                            ? "Show \(display.name)"
                            : "Hide \(display.name)",
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

struct ExternalDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isMirrored: Bool
}

final class DisplayManager: ObservableObject {
    @Published private(set) var externalDisplays: [ExternalDisplay] = []
    private var builtInID: CGDirectDisplayID?

    var anyExternalActive: Bool {
        externalDisplays.contains { !$0.isMirrored }
    }

    init() {
        refresh()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { manager.refresh() }
        }, ctx)
    }

    func refresh() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        builtInID = ids.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()

        externalDisplays = ids
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .map { id in
                ExternalDisplay(
                    id: id,
                    name: Self.name(for: id),
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

    private static func name(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               n.uint32Value == id {
                return screen.localizedName
            }
        }
        return "Display \(id)"
    }
}
```

## Acceptance criteria

1. App launches into the menu bar with no dock icon and no opened window.
2. Menu lists one entry per external display by name (e.g. "LG UltraFine"), not by numeric ID, when `NSScreen.localizedName` provides a name.
3. Clicking an entry toggles that display between hidden (mirrored / disconnected) and active (extended), with the visual change happening within ~1 second.
4. Menu state and icon update automatically when displays are physically connected or disconnected.
5. `Refresh` re-enumerates displays without restarting the app.
6. `Quit` (`⌘Q`) terminates cleanly.
7. If only the built-in display is present, the menu shows "No external displays" and no toggle entries.

## Stretch goals

Implement in this order if extending:

1. **Global hotkey** — toggle the most-recently-used external display. Use the [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) Swift package. Recommended default: `⌃⌥⌘D`.
2. **Hide all / Show all** — single menu actions when more than one external is connected.
3. **Launch at login** — `SMAppService.mainApp.register()` (macOS 13+), toggleable from the menu.
4. **Strategy B toggle** — submenu or settings item to use `CGSConfigureDisplayEnabled` instead of mirroring. Off by default.
5. **Remember last state** — restore hidden displays on next launch via `UserDefaults`.

## Out of scope

- DDC, brightness, contrast, HDR, custom resolutions, EDID overrides.
- Sandboxing and notarization for distribution.
- Multi-user support.
- Localization (English only is fine).

## References

- CoreGraphics display services: <https://developer.apple.com/documentation/coregraphics/quartz_display_services>
- `MenuBarExtra`: <https://developer.apple.com/documentation/swiftui/menubarextra>
- Prior art (more featureful, useful for cross-checking behavior): BetterDisplay by waydabber, Lunar by alin23.
