# Panels and Spaces

## One bar per desktop

Each user desktop (Space) gets its own `TaskbarPanel`, and each panel
**belongs** to its desktop (`collectionBehavior = [.managed]`) instead of
floating above all of them. This is what makes Space switching seamless:
during the switch animation, macOS composites each desktop *with its bar* —
the old desktop slides out carrying its bar, the new one slides in carrying
its own, each showing exactly its desktop's windows with its own focus
highlight. nanobar renders nothing special during transitions; the window
server does all the work.

## Panel configuration

`TaskbarPanel` is an `NSPanel` with:

| Setting | Why |
|---|---|
| `styleMask = [.borderless, .nonactivatingPanel]` | no chrome; clicking never activates nanobar (which would steal focus from the window being raised) |
| `canBecomeKey / canBecomeMain = false` | the bar is click-only; it must never take keyboard focus |
| custom `NSHostingView` overriding `acceptsFirstMouse → true` | AppKit swallows the first click on a non-key window; this makes single clicks work |
| `level = .statusBar` | floats above normal windows |
| `collectionBehavior = [.managed]` | participates in Spaces like a normal window — belongs to the Space it was ordered onto, slides with it (explicit, because floating panels otherwise get special treatment) |
| `isReleasedWhenClosed = false` | ARC owns the panel; `close()` must not deallocate it |
| transparent background | `BarView` draws its own material |

Panels pin to the primary screen's bottom edge (`NSScreen.screens.first`,
full `frame` rather than `visibleFrame` so the bar sits at the true edge)
and re-pin on `didChangeScreenParametersNotification`.

## Panel lifecycle (`AppDelegate.syncPanels()`)

Runs after every store refresh:

1. **Retire** any panel whose desktop no longer exists, or whose *actual*
   Space (queried via `CGSCopySpacesForWindows` on the panel's own window
   number) differs from its assigned one. Both happen when a desktop is
   deleted: macOS silently moves its windows to a neighboring Space, which
   already has its own bar.
2. **Create** a panel for the current desktop if it doesn't have one yet
   (`orderFrontRegardless`, because a background app never activates). A new
   window lands on the active Space — that's the only placement public API
   allows, which is why bars appear on first visit rather than all at once.

## First-visit rule (consequence of the above)

After launch, a desktop has no bar until you switch to it once. The same
visit populates the AX caches and the focus record for that desktop
(window-discovery.md), so one visit brings its bar fully up: chips, titles,
highlight. A possible future enhancement is seeding panels onto unvisited
Spaces with the private `CGSAddWindowsToSpaces`; deliberately not used yet.

## Current-Space bookkeeping

- "Current desktop" = the first entry of `CGSCopyManagedDisplaySpaces`'
  current-Space list — i.e. what the **primary display** is showing. This is
  deliberately *not* `CGSGetActiveSpace` (which follows keyboard focus across
  displays); a bar pinned to one display should track that display.
- `CGSGetActiveSpace` is still used as the cheap 0.1 s change detector and as
  a fallback.
- Space IDs are stable, opaque `UInt64`s (they can be large, e.g. 660 — that
  just means the Space was created after many others).

## What happens during a switch, step by step

1. User starts a swipe. The window server animates both desktops (and their
   bars) across the screen. Nothing in nanobar reacts yet — the bars are
   already correct.
2. The switch commits (or the swipe is cancelled — then nothing changed).
   `CGSGetActiveSpace` flips; the 0.1 s tick catches it and refreshes.
3. The refresh updates focus records and window lists; `syncPanels` creates
   the desktop's bar if this was its first visit.
