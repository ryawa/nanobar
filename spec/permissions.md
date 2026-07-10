# Permissions & security posture

## What nanobar needs

**Accessibility** (System Settings → Privacy & Security → Accessibility) —
used to read window titles/subroles/minimized state and to raise, focus, and
minimize other apps' windows. Requested at launch via
`AXIsProcessTrustedWithOptions` with the prompt option.

**Deliberately avoided:**

- **Screen Recording** — would be needed to read titles through CoreGraphics
  (`kCGWindowName`); nanobar reads titles through AX instead. (Hover
  thumbnails, a roadmap item, would require it via ScreenCaptureKit.)
- **App Sandbox** — disabled (`ENABLE_APP_SANDBOX = NO`); the AX API cannot
  be used from a sandboxed process. This rules out Mac App Store
  distribution, as it does for every app in this category.

## Degraded mode (permission not granted)

The app stays functional but limited, and recovers live once the permission
is granted (trust is re-checked on every refresh — no relaunch needed):

| Capability | With AX | Without AX |
|---|---|---|
| Window enumeration | all desktops | on-screen windows only, size-filtered (≥ 100×80) |
| Chip labels | window titles | app names |
| Click | raise the window (un-minimizing if needed) | activate the app |
| Minimized windows | shown, restorable | not shown |
| Focus highlight | per desktop | none |

The menu-bar icon's menu always shows the live permission state
("Accessibility: granted ✓" / "⚠️ not granted — open Settings…", refreshed
each time the menu opens) so degraded mode is never silent.

## The rebuild/TCC gotcha (development)

macOS ties the Accessibility grant to the binary's code signature. A debug
build without a signing team is ad-hoc signed, and its signature changes on
**every rebuild** — the grant silently stops matching while the System
Settings toggle still looks enabled. Symptoms: titles become app names, chips
stop minimizing, minimized windows vanish.

Fixes:

- One-off: remove nanobar from the Accessibility list with the **−** button
  (toggling is not always enough), relaunch, re-grant.
- Permanent: set a signing **Team** (a free personal Apple ID works) in the
  target's Signing & Capabilities tab so the binary keeps a stable identity.

## Private API risk

nanobar links five private symbols (inventory in window-discovery.md). They
have been stable across macOS releases for 10+ years and are load-time
linked (`@_silgen_name`), so a removal would fail at launch, not silently.
Mitigations in code: every CGS lookup has a defined fallback path (empty
layout → keep previous lists; unknown window membership → trust only what's
visible), and `Spaces.displayLayout()`'s payload parsing is defensive about
dictionary shape.

## Distribution

Open source (MIT). Outside the App Store the intended channel is a notarized
Developer ID build (or building from source). Accessibility must be granted
per machine; there is no way to pre-authorize it.
