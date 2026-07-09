# Window discovery

How `WindowStore.refresh()` builds `windowsBySpace`. Three APIs cooperate,
each covering another's blind spot:

| API | Gives us | Can't give us |
|---|---|---|
| CoreGraphics (`CGWindowListCopyWindowInfo`) | every window's ID, owner pid, layer, alpha, on-screen flag, bounds | titles (needs Screen Recording since 10.15); which Space; whether it's a *real* user window |
| Accessibility (`AXUIElement`) | titles, subrole, minimized state, raise/minimize actions | windows on other Spaces (only lists the current Space); enumeration by CGWindowID |
| CGS private calls (`Spaces.swift`) | window→Space membership, desktop layout | anything else |

The AX↔CG bridge is the private `_AXUIElementGetWindow(element) → CGWindowID`
(stable; used by every macOS window-switcher).

## Pass 1 — enumerate and filter

Enumerate `CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])`
— *all* windows, including other desktops' and hidden apps' — and keep a
window only if **all** of these hold, in order:

1. **Layer 0** (the normal document-window layer; menus/Dock/overlays live
   elsewhere). All layer-0 IDs are also collected into the tick detector's
   reference set — the two must use identical predicates or the 0.1 s check
   would refresh forever.
2. **Owned by a regular app** (Dock-visible activation policy) that isn't
   nanobar itself; not a duplicate ID.
3. **Not fully transparent** (alpha 0 = app-internal machinery).
4. **Not an AX helper window**: if a live AX match exists, its subrole must
   be `AXStandardWindow` (filters tooltips, palettes, popovers).
5. **AX-verified**: it must have an AX element — live, or cached from an
   earlier refresh. `.optionAll` reports plenty of app-internal windows
   (hidden buffers, offscreen helpers) that AX never lists; requiring a
   verified element is what keeps them off the bars. This loses nothing,
   because a desktop's bar only exists once that desktop has been visited,
   and visiting is what verifies its windows.
   *Degraded mode* (no Accessibility permission): fall back to on-screen
   windows of plausible size (≥ 100×80).
6. **Assigned to at least one user desktop** via `CGSCopySpacesForWindows`:
   - several Spaces → the window is pinned to every desktop → all bars;
   - only fullscreen-app Spaces → no bar;
   - empty (lookup failed) → trusted only as far as visible: on-screen → the
     current desktop's bar, off-screen → skipped. Never "fail open to every
     bar" — that's how ghost windows once spread everywhere.

Each surviving window becomes one `TaskbarWindow` **per target desktop** (the
chips differ per desktop in their `isFocused` flag; see below).

## Pass 2 — minimized windows

Minimized windows may be missing from the CG list, so a second pass walks
each regular app's AX window list and adds any window with `AXMinimized`
set that pass 1 didn't emit. Space assignment as above, except an unknown
membership fails open to all desktops — an AX-listed window is certainly
real, and losing a minimized window (no way to restore it) is the worse
failure.

## Keeping the bar's strip clear (`clampIfUnderBar`)

macOS reserves screen space only for the Dock; there is no public API for
another app to do the same. So zooming a window (double-click on the title
bar) or tiling it fills the visible frame down to the true bottom edge —
under the bar. During pass 1, any window that is on screen, on the current
desktop, not minimized, and **spans the full height** of the screen (top
within ~5 pt of the menu bar's bottom, bottom inside the bar's 40 pt strip)
is shrunk via `AXSize` so its bottom edge meets the bar's top edge.

- Full-height only: a window deliberately dragged partway under the bar is
  never touched.
- Apps may refuse or adjust the resize (minimum sizes, terminals snapping to
  a character grid). Bounds that didn't budge after a request are remembered
  in `clampDeclined` so a refusing window isn't re-asked on every refresh.
- Responsiveness comes from the tick detector polling the focused window's
  *size*: a zoom changes it, which triggers the refresh that clamps
  (~100 ms). Zooms of non-focused windows are caught by the 1 s catch-all.

## Caches (the cross-Space memory)

The AX API only lists windows on the **current** Space, so windows on other
desktops have no live AX match. Two dictionaries bridge that gap, populated
whenever a window *does* have a live match:

- `cachedElements[windowID] = (pid, AXUIElement)` — an element reference
  captured on the window's own Space keeps working after switching away
  (AX just stops *listing* it), so off-desktop chips stay clickable and can
  often still read fresh titles.
- `cachedTitles[windowID]` — last successfully read title, the fallback when
  a cross-Space title read fails.

Also `lastFocusedBySpace[spaceID] = windowID` — recorded on every refresh
from the live focused window; gives each desktop's bar its own persistent
focus highlight.

Entries are pruned when their app quits. Closed windows of running apps
linger harmlessly (never looked up again).

## Known blind spot

Everything cached is learned by *visiting* a desktop. Until a desktop's first
visit after launch: no bar (see panels-and-spaces.md), its windows show no
chips elsewhere either way, and it has no focus record. One visit heals all
of it.

## Private API inventory

Declared via `@_silgen_name`; all stable for a decade-plus and used by
AltTab, yabai, etc.:

| Symbol | Used for |
|---|---|
| `_AXUIElementGetWindow` | AX element → CGWindowID matching |
| `CGSMainConnectionID` | connection handle for the calls below |
| `CGSGetActiveSpace` | cheap change detector for the 0.1 s tick |
| `CGSCopySpacesForWindows` | window → Space membership (mask 7 = all Spaces) |
| `CGSCopyManagedDisplaySpaces` | per-display layout: current Space + ordered Space list with types (0 = user desktop, 4 = fullscreen app) |

Payload shape of `CGSCopyManagedDisplaySpaces` (observed on macOS 26): array
of display dicts with `"Display Identifier"`, `"Current Space"`
(`{ManagedSpaceID, id64, type, uuid}`), and `"Spaces"` (same dict shape,
in left-to-right order).
