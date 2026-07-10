# Product spec

nanobar is an open-source, Windows-style taskbar for macOS, in the spirit of
[Taskbar](https://lawand.io/taskbar/) and [boringBar](https://boringbar.app/).
It shows **one chip per open window** (not per app, like the Dock), scoped to
the desktop the window lives on.

## The bar

- A translucent strip (ultra-thin material with a 45 % window-background
  tint for text contrast) pinned to the **bottom edge** of
  the **primary display**, full width, 40 pt tall, floating above normal
  windows (`.statusBar` level). It occupies the same strip as the Dock; users
  are expected to auto-hide the Dock or keep it on a side.
- **Every user desktop has its own bar** showing only that desktop's windows.
  During a Space-switch animation each desktop slides in/out carrying its own
  bar (see panels-and-spaces.md). A desktop's bar is created the first time
  the desktop is visited after launch.
- Chips overflow into a horizontal scroll (no scrollbar).
- **The bar keeps its strip clear**: a window zoomed (double-click on the
  title bar) or tiled (green-button options) fills the screen to the bottom
  edge, under the bar — macOS reserves space only for the Dock. nanobar
  shrinks such windows so their bottom edge meets the bar's top edge. Only
  **full-height** windows on the current desktop are touched; a window
  deliberately dragged partway under the bar stays put.
- The app is a background app: no Dock icon (`LSUIElement`), no main window.
  A menu-bar icon (`dock.rectangle`) offers *About*, the live Accessibility
  permission state (click opens System Settings), and *Quit* (⌘Q).

## Chips

One chip per window: app icon (22 pt) + window title (12 pt, truncated,
fixed chip width 170 pt, full title as tooltip). States:

| State | Look |
|---|---|
| Focused (this desktop's active window) | strong background (primary 22 %) |
| Hovered | medium background (primary 15 %) |
| Idle | faint background (primary 10 %) |
| Minimized | 55 % opacity, no focus highlight |

Chips are sorted by window creation order (ascending `CGWindowID`) so they
don't reshuffle when focus changes.

## Click semantics

| Chip state | Click does |
|---|---|
| Normal (focused or not) | Raise that window and activate its app |
| Minimized | Un-minimize, raise, activate |
| No Accessibility permission | Activate the app (best effort) |

Clicking never minimizes — a click always means "focus this window".

Clicking the bar never steals keyboard focus (non-activating panel +
first-mouse acceptance: a single click works even though the bar is never the
key window).

## Which windows get chips

- Windows of **regular** apps (Dock/app-switcher apps) on the **normal
  window layer**, verified as real user windows (see window-discovery.md).
- **Minimized** windows stay on the bar (dimmed) on the desktop they were
  minimized from — otherwise minimizing would make them unreachable.
- **Hidden apps'** (⌘H) windows stay on the bar; clicking un-hides.
- Windows **pinned to every desktop** (Dock → Options → All Desktops) appear
  on every bar.
- Windows in **fullscreen-app Spaces** appear on no desktop bar.
- nanobar's own windows never appear.

## Focus highlight

Each bar highlights *its own desktop's* active window: the currently focused
window while the desktop is visible, or the window that was focused when the
desktop was last visited. The highlight follows within-app focus changes in
~100 ms and survives Space switches (the incoming bar already shows its
highlight mid-animation).

## Latency budget (as implemented)

| Event | Bar reflects it within |
|---|---|
| Space switch | animation itself is seamless (bars belong to desktops) |
| Window opened / closed | ~100 ms |
| Focus moved (any app) | ~100 ms |
| Chip clicked | ~150 ms |
| Window zoomed over the bar → shrunk back | ~100 ms (focused-window size is polled) |
| App launched / quit / activated | immediate (notification) + 300 ms settle |
| Title change, minimize via yellow button | ≤ 1 s (catch-all refresh) |

## Out of scope for v1 (roadmap)

Hover thumbnails (ScreenCaptureKit) · pinned apps · multi-monitor bars ·
AXObserver push updates · drag-to-reorder · auto-hide · settings window.
