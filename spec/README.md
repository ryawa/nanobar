# nanobar specs

Design and behavior documentation for nanobar. Each file covers one area;
together they describe the whole app as implemented.

| File | Covers |
|---|---|
| [product.md](product.md) | What nanobar does: bar, chips, click semantics, highlight rules |
| [architecture.md](architecture.md) | Components, files, data flow, refresh model |
| [window-discovery.md](window-discovery.md) | How the per-desktop window lists are built; filtering; caches |
| [panels-and-spaces.md](panels-and-spaces.md) | The one-bar-per-desktop panel system and Space handling |
| [permissions.md](permissions.md) | Accessibility permission, degraded mode, sandbox, TCC gotchas |
| [decisions.md](decisions.md) | Decision log: approaches tried, what failed, and why the current design won |

Conventions used throughout:

- **Space** — macOS's name for a virtual desktop or a fullscreen app's
  workspace. **Desktop** — specifically a *user* desktop Space (type 0), the
  kind a taskbar cares about.
- **Chip** — one clickable window entry on a bar.
- **CG / AX / CGS** — CoreGraphics window list API, Accessibility API, and
  the private CoreGraphics services calls (see window-discovery.md).
