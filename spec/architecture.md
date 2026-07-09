# Architecture

Native Swift: SwiftUI for the visuals, AppKit for the window machinery
SwiftUI can't express. No dependencies. One process, everything on the main
actor (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

## Components

```
nanobarApp (SwiftUI @main, no scenes of its own)
   └─ AppDelegate ──────────── startup, menu-bar item, panel fleet
        ├─ WindowStore ─────── model: windowsBySpace + click actions
        │     ├─ Accessibility (AX enum) ── titles, raise/minimize, matching
        │     └─ Spaces (CGS wrappers) ──── desktop layout, window→Space
        └─ TaskbarPanel (×1 per visited desktop)
              └─ BarView(spaceID) ── WindowChipView per chip
```

| File | Role |
|---|---|
| `nanobar/nanobarApp.swift` | Entry point; empty `Settings` scene; installs AppDelegate. |
| `nanobar/AppDelegate.swift` | Requests Accessibility trust, builds the status item, owns `panels: [spaceID: TaskbarPanel]`, syncs them after every store refresh. |
| `nanobar/WindowStore.swift` | Publishes `windowsBySpace: [UInt64: [TaskbarWindow]]`; refresh triggers; caches; `handleClick`. |
| `nanobar/TaskbarPanel.swift` | Borderless non-activating `NSPanel`, `.managed` collection behavior, pinned to the primary screen's bottom edge. |
| `nanobar/Accessibility.swift` | `AX` enum: trust check/prompt, per-app window lists, title/subrole/minimized accessors, raise, `_AXUIElementGetWindow` shim. |
| `nanobar/Spaces.swift` | `Spaces` enum: active Space, per-display layout (`DisplayLayout`), window→Space membership. |
| `nanobar/BarView.swift` | Scrolling chip row for one desktop (`windowsBySpace[spaceID]`). |
| `nanobar/WindowChipView.swift` | One chip: icon, title, states, tap/hover handling. |

## Data flow

1. **Refresh triggers** (all funnel into `WindowStore.refresh()`):
   - 0.1 s timer tick with four cheap change detectors — active Space ID,
     focused window ID, focused window *size* (so zooming a window over the
     bar is corrected promptly), set of all normal-layer window IDs — plus
     an unconditional refresh every 10th tick (≈1 s catch-all).
   - `NSWorkspace` notifications (app launched / terminated / activated,
     active Space changed), each followed by a 300 ms settle refresh.
   - 150 ms after any chip click.
2. **`refresh()`** rebuilds `windowsBySpace` from scratch (see
   window-discovery.md), publishes it only if it actually changed
   (`TaskbarWindow` equality covers only render-relevant fields), then calls
   `onRefresh`. As a side effect it shrinks any full-height window that
   extends under the bar (see window-discovery.md → "Keeping the bar's strip
   clear").
3. **`AppDelegate.syncPanels()`** (the `onRefresh` hook) reconciles the panel
   fleet with the current desktop layout (see panels-and-spaces.md).
4. **SwiftUI** — each panel's `BarView` observes the store and re-renders its
   own slice.

## Concurrency model

Everything runs on the main actor. The AX calls are synchronous IPC; a hung
target app could block them, so every app-level `AXUIElement` gets a 0.25 s
messaging timeout (`AXUIElementSetMessagingTimeout`). Delayed refreshes use
`Task` + `Task.sleep` (inherits the main actor); the timer and notifications
use selector-based APIs to stay off the Sendable-closure path.

## Build settings that matter

- `ENABLE_APP_SANDBOX = NO` — the AX API doesn't work sandboxed (this is why
  taskbar apps aren't on the Mac App Store).
- `INFOPLIST_KEY_LSUIElement = YES` — background app, no Dock icon.
- New Swift files are picked up automatically
  (`PBXFileSystemSynchronizedRootGroup`); no pbxproj edits needed.
