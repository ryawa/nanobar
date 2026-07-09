//
//  WindowStore.swift
//  nanobar
//
//  The app's model layer: keeps an up-to-date list of taskbar chips for
//  every desktop (Space), and performs the focus/minimize actions when a
//  chip is clicked. Each desktop's bar panel observes this object and
//  renders its own slice of `windowsBySpace`.
//

import AppKit
import Combine

/// One chip on a taskbar.
struct TaskbarWindow: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let appName: String
    let pid: pid_t
    let isMinimized: Bool
    let isFocused: Bool
    let icon: NSImage?
    let axElement: AXUIElement?

    // Only compare the fields that affect rendering, so a refresh doesn't
    // cause SwiftUI updates when nothing visible changed.
    static func == (lhs: TaskbarWindow, rhs: TaskbarWindow) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.appName == rhs.appName
            && lhs.isMinimized == rhs.isMinimized
            && lhs.isFocused == rhs.isFocused
    }
}

final class WindowStore: NSObject, ObservableObject {
    /// Chips for each user desktop, keyed by Space ID. Every desktop's bar
    /// renders its own entry, and the lists are maintained even for desktops
    /// that are currently off screen — that's what lets each desktop slide
    /// in already carrying a correct bar during the switch animation.
    @Published private(set) var windowsBySpace: [UInt64: [TaskbarWindow]] = [:]

    /// Called after every refresh. AppDelegate uses it to create/retire the
    /// per-desktop bar panels.
    var onRefresh: (() -> Void)?

    private var timer: Timer?
    private var lastActiveSpace: UInt64 = 0
    private var lastWindowIDs: Set<CGWindowID> = []
    private var ticksSinceRefresh = 0

    /// AX window elements and titles remembered across refreshes. The AX API
    /// only lists an app's windows on the *current* Space, so windows on
    /// other desktops have no live AX match — but an element reference (and
    /// title) captured while their Space was active keeps working, so their
    /// chips stay labeled and clickable.
    private var cachedElements: [CGWindowID: (pid: pid_t, element: AXUIElement)] = [:]
    private var cachedTitles: [CGWindowID: String] = [:]

    /// Each desktop's most recently focused window, so its bar keeps the
    /// active-window highlight even while the desktop is off screen.
    private var lastFocusedBySpace: [UInt64: CGWindowID] = [:]
    private var lastFocusedWindowID: CGWindowID?
    private var lastFocusedWindowSize: CGSize?

    /// Bounds for which a window declined (or adjusted away) our shrink
    /// request, so it isn't re-asked on every refresh. See clampIfUnderBar.
    private var clampDeclined: [CGWindowID: CGRect] = [:]

    /// Begin watching for window changes. Workspace notifications catch app
    /// launches/quits and focus changes. The timer runs two cheap checks
    /// every 0.1 s — did the active Space change? did the set of windows
    /// change? — and triggers the expensive full refresh only when one of
    /// them fires, or once per second as a catch-all (title changes, the
    /// yellow minimize button, …).
    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in events {
            center.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }

        timer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = 0.02

        refresh()
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        refresh()
        // Some state (frontmost app, minimized flags) can still be mid-flight
        // when a notification fires. Refresh again once things settle.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            refresh()
        }
    }

    @objc private func timerFired() {
        ticksSinceRefresh += 1
        let (focusedID, focusedSize) = Self.currentFocusedWindowState()
        if ticksSinceRefresh >= 10
            || Spaces.activeSpaceID != lastActiveSpace
            || focusedID != lastFocusedWindowID
            || focusedSize != lastFocusedWindowSize
            || Self.allWindowIDs() != lastWindowIDs {
            refresh()
        }
    }

    /// The window that has keyboard focus right now, and its size. Cheap
    /// enough to poll, so clicking between windows moves the highlight — and
    /// zooming a window over the bar gets it shrunk back — without waiting
    /// for the once-per-second full refresh.
    private static func currentFocusedWindowState() -> (id: CGWindowID?, size: CGSize?) {
        guard AX.isTrusted, let app = NSWorkspace.shared.frontmostApplication,
              let window = AX.focusedWindow(inAppWithPID: app.processIdentifier)
        else { return (nil, nil) }
        return (AX.windowID(of: window), AX.size(of: window))
    }

    /// IDs of every normal-layer window in the system. Cheap enough to poll;
    /// any change (window opened or closed anywhere) is a reason to rebuild.
    private static func allWindowIDs() -> Set<CGWindowID> {
        let cgInfo = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return Set(cgInfo.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    // MARK: - Building the window lists

    func refresh() {
        // Only apps that show in the Dock / app switcher ("regular" activation
        // policy). This filters out menu-bar utilities and background agents.
        let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let appsByPID = Dictionary(uniqueKeysWithValues: regularApps.map { ($0.processIdentifier, $0) })
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        lastActiveSpace = Spaces.activeSpaceID
        ticksSinceRefresh = 0

        // Drop cache entries for apps that have quit. (Entries for closed
        // windows of running apps linger until then — harmless, they're just
        // never looked up again.)
        cachedElements = cachedElements.filter { appsByPID[$0.value.pid] != nil }
        cachedTitles = cachedTitles.filter { cachedElements[$0.key] != nil }
        clampDeclined = clampDeclined.filter { cachedElements[$0.key] != nil }

        let layout = Spaces.displayLayout()
        let desktops = layout.orderedUserSpaceIDs
        let currentSpace = layout.currentSpaceIDs.first
        guard !desktops.isEmpty else { return }  // CGS hiccup — keep the old lists

        // The window that has keyboard focus, for the highlighted chip.
        let focusedWindow = frontmostPID.flatMap { AX.focusedWindow(inAppWithPID: $0) }
        let focusedWindowID = focusedWindow.flatMap { AX.windowID(of: $0) }
        lastFocusedWindowID = focusedWindowID
        lastFocusedWindowSize = focusedWindow.flatMap { AX.size(of: $0) }

        // Record it against the desktop it's focused *on*, so that desktop's
        // bar keeps the highlight after the user switches away. (No record is
        // erased when focus is momentarily nowhere, e.g. right after closing
        // a window.)
        if let currentSpace, let focusedWindowID {
            lastFocusedBySpace[currentSpace] = focusedWindowID
        }
        lastFocusedBySpace = lastFocusedBySpace.filter { desktops.contains($0.key) }

        // Fetch each app's AX window list at most once per refresh.
        var axCache: [pid_t: [AX.WindowHandle]] = [:]
        func axWindows(for pid: pid_t) -> [AX.WindowHandle] {
            if let cached = axCache[pid] { return cached }
            let list = AX.isTrusted ? AX.windows(inAppWithPID: pid) : []
            axCache[pid] = list
            return list
        }

        var chipsBySpace: [UInt64: [TaskbarWindow]] = [:]
        for desktop in desktops {
            chipsBySpace[desktop] = []
        }
        var seenIDs = Set<CGWindowID>()

        // Pass 1: every normal-layer window in the system — `.optionAll`
        // includes windows on other Spaces and windows of hidden (⌘H) apps,
        // so each desktop's list stays correct while it's off screen.
        let cgInfo = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        var allIDs = Set<CGWindowID>()
        for info in cgInfo {
            guard
                // Layer 0 is the normal document-window layer; menus, the
                // Dock, overlays, etc. live on other layers.
                (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }

            // Must mirror allWindowIDs() exactly, or the 0.1 s check would
            // see a permanent difference and refresh at full tilt.
            allIDs.insert(windowID)

            guard
                let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                pid != myPID,
                let app = appsByPID[pid],
                !seenIDs.contains(windowID)
            else { continue }

            // Fully transparent windows are app-internal machinery.
            if (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 0 {
                continue
            }

            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

            let liveHandle = axWindows(for: pid).first { $0.windowID == windowID }

            // Skip helper windows (tooltips, palettes, popovers). Real windows
            // have the "standard" subrole.
            if let liveHandle, let subrole = AX.subrole(of: liveHandle.element),
               subrole != kAXStandardWindowSubrole as String {
                continue
            }
            if let liveElement = liveHandle?.element {
                cachedElements[windowID] = (pid, liveElement)
            }

            // No live AX match means the window is on another Space — fall
            // back to the element captured while its Space was active.
            let element = liveHandle?.element ?? cachedElements[windowID]?.element

            // `.optionAll` also reports app-internal windows (hidden buffers,
            // offscreen helpers) that no taskbar should show. The AX API only
            // lists real user windows, so require a verified AX element —
            // live, or cached from when the window's Space was last visited.
            // Nothing is lost: a desktop's bar only exists once that desktop
            // has been visited, and visiting is what verifies its windows.
            // Degraded mode (no Accessibility permission) can't verify
            // anything, so it falls back to on-screen windows of plausible
            // size.
            if element == nil {
                guard !AX.isTrusted, isOnScreen else { continue }
                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                   let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                   bounds.width < 100 || bounds.height < 80 {
                    continue
                }
            }

            // Which desktops' bars should carry this window? Windows pinned
            // to every desktop report several Spaces; windows that belong
            // only to a fullscreen-app Space belong on no desktop bar. If the
            // membership lookup fails, trust the window only as far as we can
            // see it: on screen → the visible desktop's bar; otherwise skip.
            let spaces = Spaces.spaceIDs(ofWindow: windowID)
            var targets = desktops.filter { spaces.contains($0) }
            if spaces.isEmpty, isOnScreen, let currentSpace, desktops.contains(currentSpace) {
                targets = [currentSpace]
            }
            if targets.isEmpty { continue }

            let liveTitle = element.flatMap { AX.title(of: $0) }
            if let liveTitle {
                cachedTitles[windowID] = liveTitle
            }
            let isMinimized = element.map { AX.isMinimized($0) } ?? false
            let title = liveTitle ?? cachedTitles[windowID] ?? app.localizedName ?? "Window"

            // A window zoomed with the title bar's double-click (or tiled with
            // the green button) fills the screen to the bottom edge and slides
            // under the bar — macOS reserves space for the Dock but has no
            // public way for anyone else to do the same. Fix offenders after
            // the fact by shrinking them to stop at the bar's top edge.
            if let element, !isMinimized, isOnScreen,
               let currentSpace, targets.contains(currentSpace),
               let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                clampIfUnderBar(windowID, element: element, bounds: bounds)
            }

            for space in targets {
                chipsBySpace[space, default: []].append(TaskbarWindow(
                    id: windowID,
                    title: title,
                    appName: app.localizedName ?? "App",
                    pid: pid,
                    isMinimized: isMinimized,
                    // Highlight each desktop's *own* active window — the one
                    // focused now, or when the desktop was last visited.
                    isFocused: !isMinimized && windowID == lastFocusedBySpace[space],
                    icon: app.icon,
                    axElement: element
                ))
            }
            seenIDs.insert(windowID)
        }
        lastWindowIDs = allIDs

        // Pass 2: minimized windows the CG list missed, from each app's AX
        // window list. A minimized window still belongs to the Space it was
        // minimized from, so it lands on that desktop's bar.
        if AX.isTrusted {
            for app in regularApps where app.processIdentifier != myPID {
                for handle in axWindows(for: app.processIdentifier) {
                    guard
                        let windowID = handle.windowID,
                        !seenIDs.contains(windowID),
                        AX.isMinimized(handle.element)
                    else { continue }

                    let spaces = Spaces.spaceIDs(ofWindow: windowID)
                    let targets: [UInt64]
                    if spaces.isEmpty {
                        targets = desktops
                    } else {
                        targets = desktops.filter { spaces.contains($0) }
                        if targets.isEmpty { continue }
                    }

                    cachedElements[windowID] = (app.processIdentifier, handle.element)
                    let title = AX.title(of: handle.element)
                    if let title {
                        cachedTitles[windowID] = title
                    }

                    let chip = TaskbarWindow(
                        id: windowID,
                        title: title ?? cachedTitles[windowID] ?? app.localizedName ?? "Window",
                        appName: app.localizedName ?? "App",
                        pid: app.processIdentifier,
                        isMinimized: true,
                        isFocused: false,
                        icon: app.icon,
                        axElement: handle.element
                    )
                    for space in targets {
                        chipsBySpace[space, default: []].append(chip)
                    }
                    seenIDs.insert(windowID)
                }
            }
        }

        // Window IDs increase as windows are created, so sorting by ID keeps
        // chips in a stable creation order instead of jumping around whenever
        // focus changes.
        for space in chipsBySpace.keys {
            chipsBySpace[space]?.sort { $0.id < $1.id }
        }

        if chipsBySpace != windowsBySpace {
            windowsBySpace = chipsBySpace
        }
        onRefresh?()
    }

    // MARK: - Keeping windows out of the bar's strip

    /// Shrink a window that extends under the bar so its bottom edge meets
    /// the bar's top edge. Only *full-height* windows are touched — the shape
    /// zooming and tiling produce — so a window deliberately dragged partway
    /// under the bar is left alone.
    private func clampIfUnderBar(_ windowID: CGWindowID, element: AXUIElement, bounds: CGRect) {
        guard let screen = NSScreen.screens.first else { return }

        // CG window bounds use top-left-origin global coordinates; NSScreen
        // frames are bottom-left-origin. On the primary screen the x axes
        // coincide and y converts as (screen height − Cocoa y).
        let screenHeight = screen.frame.height
        let barTop = screenHeight - TaskbarPanel.barHeight
        let menuBarBottom = screenHeight - screen.visibleFrame.maxY

        guard
            bounds.maxY > barTop + 1,          // reaches into the bar's strip…
            bounds.minY <= menuBarBottom + 5,  // …spanning from the top of the screen
            bounds.minX < screen.frame.maxX,   // and horizontally on the bar's screen
            bounds.maxX > screen.frame.minX
        else { return }

        // Apps may refuse or adjust the resize (enforced minimum sizes, a
        // terminal snapping to its character grid). Remember bounds that
        // didn't budge so a refusing window isn't re-asked 10× a second.
        guard clampDeclined[windowID] != bounds else { return }
        AX.setSize(element, CGSize(width: bounds.width, height: barTop - bounds.minY))
        if AX.size(of: element)?.height == bounds.height {
            clampDeclined[windowID] = bounds
        }
    }

    // MARK: - Chip clicks

    func handleClick(on window: TaskbarWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }

        if let element = window.axElement {
            if window.isMinimized {
                AX.setMinimized(element, false)
                AX.raise(element)
                app.activate()
            } else if window.isFocused {
                AX.setMinimized(element, true)
            } else {
                AX.raise(element)
                app.activate()
            }
        } else {
            // Degraded mode (no Accessibility permission): the best we can do
            // is bring the whole app forward.
            app.activate()
        }

        // Reflect the change quickly instead of waiting for the next timer tick.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            refresh()
        }
    }
}
