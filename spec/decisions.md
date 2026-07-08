# Decision log

Chronological record of the design decisions, including the approaches that
failed and what each failure taught us. The failures are documented because
they're the non-obvious part: most of them *look* like they should work.

## D1 — Native Swift, SwiftUI + AppKit hybrid

SwiftUI renders the chips; AppKit provides what SwiftUI can't: borderless
non-activating panels, window levels, Space collection behavior. Electron/web
was never viable — window control requires the AX C API in-process.

## D2 — Titles via AX, not CoreGraphics

`kCGWindowName` requires the Screen Recording permission (since 10.15).
Reading titles through the Accessibility API keeps nanobar to a single
permission. Consequence: an AX↔CG matching layer (`_AXUIElementGetWindow`)
and the cross-Space caches (D7).

## D3 — Show minimized windows on their own desktop

First version showed minimized windows on *every* desktop ("minimized
windows belong to no Space"). Wrong: macOS retains the window→Space
association through minimize — that's how the Dock returns you to the right
Space on restore — and `CGSCopySpacesForWindows` reports it. Users perceive
minimized-everywhere as a bug.

## D4 — ~~Rely on `.optionOnScreenOnly` for Space filtering~~ (failed)

"On screen" ≠ "on the current Space": during a switch gesture macOS puts
**every** desktop's windows in the on-screen list, for the whole animation.
Result: stale and foreign chips around every switch. Fix: filter by real
Space membership (`CGSCopySpacesForWindows`), never by on-screen-ness.

## D5 — ~~Predict the switch destination~~ (failed twice, then obsolete)

Goal: update the bar at gesture *start* rather than commit (the
`activeSpaceDidChange` notification and `CGSGetActiveSpace` both change only
at commit — verified empirically; there is **no** early destination signal,
partly because a swipe can be cancelled mid-gesture).

- Attempt 1: "exactly one non-visible Space has windows on screen → that's
  the destination." Failed: *all* desktops' windows come on screen during a
  gesture, so with 3+ populated desktops the candidate set is ambiguous.
- Attempt 2: tiebreak by desktop adjacency. Failed: both neighbors of the
  current desktop qualify at once.
- What actually worked: the CG window list reports **live positions** during
  the animation — the whole desktop strip slides through the coordinates ~10
  Hz. Rendering whichever Space's windows covered the most screen area
  tracked the swipe frame-by-frame. This shipped briefly and worked, then
  was made obsolete by D6, which needs no inference at all.

## D6 — One bar per desktop, owned by its Space (current design)

Instead of one `.canJoinAllSpaces + .stationary` panel that guesses what to
render mid-transition, every desktop gets its own `.managed` panel that
belongs to it. macOS then animates each desktop *with its bar* — transitions
are pixel-perfect with zero transition logic. Cost: a window can only be
placed on the *active* Space with public API, so each bar is created on its
desktop's first visit (acceptable; self-heals; `CGSAddWindowsToSpaces` could
remove it later). This also forced per-desktop window lists via
`.optionAll` (D8).

## D7 — Cache AX elements and titles across Space switches

The AX API only *lists* windows on the current Space, but an element
reference captured earlier keeps working. Without the cache, chips for
other desktops' windows (first seen mid-animation under D5, permanently
needed under D6) had no titles and dead clicks. Caches are populated on
every live sighting, pruned when apps quit. Corollary: everything is learned
by visiting; a never-visited desktop starts blank.

## D8 — Require AX verification for every chip

Switching enumeration to `.optionAll` (needed by D6) surfaced app-internal
windows — hidden buffers, offscreen helpers, often with no Space membership.
The initial "unknown Space → show everywhere" fail-open sprayed these ghosts
across all bars. Fix: a chip requires an AX element (live standard-subrole
or cached — AX only lists real user windows), alpha-0 windows are dropped,
and unknown membership is trusted only as far as it's visible (on-screen →
current desktop only). Fail-open survives solely in the minimized pass,
where windows are AX-listed (certainly real) and losing one is the worse
failure.

## D9 — Per-desktop focus highlight

`isFocused` from the single globally-focused window meant off-screen bars
had no highlight and within-app focus changes lagged up to 1 s (no
notification fires for them). Fix: record `lastFocusedBySpace` on every
refresh and judge each desktop's chips against its own record; poll the
focused window in the 0.1 s tick so clicks move the highlight in ~100 ms.

## D10 — Polling with cheap change detectors, not AXObserver (yet)

Refresh triggers: 0.1 s tick comparing three cheap values (active Space,
focused window, set of all window IDs), NSWorkspace notifications with a
300 ms settle pass, a 1 s unconditional catch-all, and a 150 ms post-click
refresh. Simple, robust, and idle cost is three tiny queries per tick.
AXObserver push updates are the roadmap replacement for the catch-all.

## D11 — Development ergonomics discovered the hard way

- Ad-hoc-signed debug builds lose the Accessibility grant on every rebuild
  (TCC ties it to the code signature) while the Settings toggle still looks
  on. Every AX-dependent feature degrades at once. Set a signing Team; the
  menu-bar item shows live permission state so this is never silent again.
- Debugging Space behavior blind is hopeless — the payloads differ by macOS
  version and by user configuration (e.g. Space IDs like 660 from long-lived
  installs). The productive loop was: instrument (`DEBUG`-only dumps of
  layout payloads, window Space memberships, bounds), have a human run one
  gesture slowly, read the timestamped log. All instrumentation was removed
  once the design stopped depending on transition inference.
