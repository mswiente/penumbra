# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Penumbra is a macOS menu bar app (Swift/SwiftUI) that hides and reveals external displays without unplugging cables. It solves the "ghost display" problem when a monitor is shared between two Macs via input switching.

## Build & run

Open `Penumbra/Penumbra.xcodeproj` in Xcode 15+ and run (⌘R), or:

```bash
xcodebuild -project Penumbra/Penumbra.xcodeproj -scheme Penumbra -configuration Debug build
```

Run the built `.app` directly — it lives in the menu bar, no window opens.

## Project setup requirements

- Deployment target: **macOS 13.0**
- **App Sandbox must be disabled** — display configuration APIs (`CGBeginDisplayConfiguration`, etc.) do not work inside the sandbox.
- `Info.plist` must include `LSUIElement = YES` to suppress the dock icon.
- No package dependencies for the core feature.

## Architecture

```
Penumbra/
├── Penumbra.xcodeproj
└── Penumbra/
    ├── PenumbraApp.swift     # @main, MenuBarExtra scene, icon state
    ├── DisplayManager.swift  # CoreGraphics enumeration + mirror/disconnect ops
    ├── MenuView.swift        # SwiftUI menu content
    └── Info.plist
```

**DisplayManager** is an `ObservableObject` that owns all CoreGraphics interaction:
- Enumerates displays via `CGGetActiveDisplayList`
- Identifies the built-in via `CGDisplayIsBuiltin`
- Registers `CGDisplayRegisterReconfigurationCallback` to react to hardware changes (dispatched to main queue)
- Implements Strategy A (mirroring) via `CGConfigureDisplayMirrorOfDisplay`

**Strategy A (default)** — mirrors the external onto the built-in using public CoreGraphics APIs. The two displays become one logical unit; windows cannot drift to the external.

**Strategy B (stretch goal)** — uses the private symbol `CGSConfigureDisplayEnabled` inside the same begin/complete block. This makes macOS treat the display as physically disconnected, which causes windows to migrate — behavior Strategy A does not provide. Acceptable here because this is a personal tool not distributed via the App Store.

```swift
@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?,
                                _ display: CGDirectDisplayID,
                                _ enabled: Bool) -> CGError
```

## Menu bar icon convention

- `rectangle.on.rectangle` — all externals active (extended mode)
- `rectangle.on.rectangle.slash` — any external is hidden

## Stretch goals (implement in this order if extending)

1. Global hotkey (`⌃⌥⌘D`) via [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) package
2. Hide all / Show all actions (when >1 external connected)
3. Launch at login via `SMAppService.mainApp.register()` (macOS 13+)
4. Strategy B toggle (submenu or settings item, off by default)
5. Remember last state via `UserDefaults`

## Out of scope

DDC, brightness, HDR, custom resolutions, EDID overrides, sandboxing/notarization, localization.
