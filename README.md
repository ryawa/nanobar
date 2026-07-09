# nanobar

A tiny, open-source, Windows-style taskbar for macOS — in the spirit of
[Taskbar](https://lawand.io/taskbar/) and [boringBar](https://boringbar.app/).

A translucent strip pinned to the bottom of your screen shows **one chip per
open window** (not per app, like the Dock). Click a chip to focus that window;
click the focused window's chip to minimize it; click a dimmed (minimized)
chip to bring it back. Only windows on your **current Space** are shown —
including minimized ones, which stay on the Space they were minimized from.

## Requirements

- macOS 26+ (built with Xcode 26)
- The **Accessibility** permission (System Settings → Privacy & Security →
  Accessibility). nanobar uses it to read window titles and to focus/minimize
  windows. It deliberately does **not** need the Screen Recording permission.

## Building

Open `nanobar.xcodeproj` in Xcode and press ⌘R. On first launch, grant the
Accessibility permission when prompted, then relaunch. nanobar runs as a
background app: no Dock icon, just the bar itself plus a menu-bar icon
(⚏) with *About* and *Quit*.

### Troubleshooting: everything degrades after a rebuild

If window titles turn into app names, chips stop minimizing, and minimized
windows vanish from the bar, the Accessibility grant has stopped matching the
binary — macOS ties it to the code signature, and an unsigned debug build's
ad-hoc signature changes on every rebuild (the toggle in System Settings will
still *look* enabled). Check the menu-bar icon's menu: it shows the live
permission state.

To fix: in System Settings → Privacy & Security → Accessibility, select
nanobar, remove it with the **−** button, then relaunch the app and re-grant.
To stop it happening again, set a signing Team (a free personal Apple ID
works) in the target's Signing & Capabilities tab so the binary keeps a
stable identity across rebuilds.

## How it works (architecture)

Full specifications live in [`spec/`](spec/README.md) — product behavior,
architecture, the window-discovery pipeline, the per-desktop panel system,
permissions, and a decision log of approaches that failed and why. The short
version:

The app is native Swift — SwiftUI for the visuals, AppKit for the window
machinery that SwiftUI can't express:

| File | Role |
|---|---|
| `nanobarApp.swift` | Entry point. Declares no regular windows; hands control to `AppDelegate`. |
| `AppDelegate.swift` | Startup: requests Accessibility trust, creates the menu-bar icon, starts the window watcher, and manages the per-desktop bar panels. |
| `TaskbarPanel.swift` | One desktop's bar: a borderless, **non-activating** `NSPanel` pinned to the bottom of the screen. Non-activating means clicking it never steals focus from the window you're switching to. |
| `WindowStore.swift` | The model. Builds each desktop's list of `TaskbarWindow`s and performs click actions. |
| `Accessibility.swift` | Wrappers around the Accessibility (AX) C API: read titles, raise, focus, minimize other apps' windows. |
| `Spaces.swift` | Wrappers around the private CGS calls for Space info: what each display shows, which Space a window belongs to. |
| `BarView.swift` / `WindowChipView.swift` | SwiftUI: the chip row and each individual chip. |

**One bar per desktop.** Every user desktop (Space) gets its own panel, and
each panel *belongs* to its desktop rather than floating above all of them.
That makes Space switching seamless for free: during the switch animation,
macOS slides the old desktop out carrying its bar and the new desktop in
carrying its bar, each already showing exactly its own windows. Because a
window can only be placed onto the *active* Space with public API, a
desktop's bar is created the first time you visit it after launch.

Two macOS APIs are combined to build the per-desktop window lists:

1. **CoreGraphics** (`CGWindowListCopyWindowInfo` with `.optionAll`)
   enumerates every window in the system — including other desktops' windows
   and windows of ⌘H-hidden apps — with its ID, owner process, and layer.
   Each window is assigned to its desktop via `CGSCopySpacesForWindows`
   (`Spaces.swift`), the same association macOS itself uses to switch Spaces
   when you restore a window from the Dock. Reading *titles* through
   CoreGraphics would require the Screen Recording permission, so titles come
   from the Accessibility API instead.
2. **The Accessibility API** provides titles and window control with only the
   Accessibility permission. AX windows are matched to CoreGraphics windows
   via the private `_AXUIElementGetWindow` call — private but stable, and used
   by effectively every macOS window-switcher app. One quirk: AX only lists an
   app's windows on the *current* Space, so elements and titles are cached
   across refreshes — a reference captured while a window's Space was active
   keeps working after you switch away, keeping every desktop's chips labeled
   and clickable.

Minimized windows are collected in a second pass from each app's AX window
list (`AXMinimized`) and stay on the bar dimmed, on the desktop they were
minimized from.

macOS reserves screen space only for the Dock, so a window zoomed by
double-clicking its title bar (or tiled with the green button) fills the
screen to the bottom edge — under the bar. nanobar detects full-height
windows overlapping the bar and shrinks them so they stop at its top edge.

The lists refresh on `NSWorkspace` notifications (app launched/quit/activated)
plus a 0.1 s timer running four cheap checks — did the active Space change,
did focus move, did the focused window resize, did the set of windows change —
with a full refresh once per second as a catch-all for title changes.

## Roadmap

- [ ] Hover thumbnails (ScreenCaptureKit)
- [ ] Pinned apps
- [ ] Multi-monitor (one bar per screen)
- [ ] Instant updates via AXObserver instead of the polling timer
- [ ] Drag to reorder, auto-hide, settings window

## License

[MIT](LICENSE)
