//
//  AppDelegate.swift
//  nanobar
//
//  App startup: ask for the Accessibility permission, put an icon in the
//  menu bar, create the taskbar panel, and start watching windows.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = WindowStore()
    private var panels: [UInt64: TaskbarPanel] = [:]
    private var statusItem: NSStatusItem?
    private var permissionItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without this permission we can still list windows, but we can't read
        // their titles or focus/minimize them. The system dialog sends the user
        // to System Settings → Privacy & Security → Accessibility.
        if !AX.isTrusted {
            AX.promptForTrust()
        }

        makeStatusItem()

        // Panels are created lazily by syncPanels(), which runs after every
        // store refresh — the first one puts a bar on the current desktop.
        store.onRefresh = { [weak self] in self?.syncPanels() }
        store.start()
    }

    // MARK: - Per-desktop bar panels

    /// Each user desktop gets its own bar, created the first time that
    /// desktop is visited — a window can only be placed onto the *active*
    /// Space with public API, so bars for not-yet-visited desktops appear
    /// as soon as you first switch to them.
    private func syncPanels() {
        let layout = Spaces.displayLayout()
        let desktops = Set(layout.orderedUserSpaceIDs)

        // Retire panels whose desktop is gone, or that macOS quietly moved to
        // another Space (that happens when a desktop is deleted — its windows
        // get adopted by a neighbor, which already has its own bar).
        for (space, panel) in panels {
            var actualSpace: UInt64?
            if panel.windowNumber > 0 {
                actualSpace = Spaces.spaceIDs(ofWindow: CGWindowID(panel.windowNumber)).first
            }
            if !desktops.contains(space) || (actualSpace != nil && actualSpace != space) {
                panel.close()
                panels[space] = nil
            }
        }

        // A new panel ordered onto the screen lands on the active Space.
        // orderFrontRegardless is needed because our background "accessory"
        // app never becomes active itself.
        if let current = layout.currentSpaceIDs.first,
           desktops.contains(current),
           panels[current] == nil {
            let panel = TaskbarPanel(store: store, spaceID: current)
            panel.orderFrontRegardless()
            panels[current] = panel
        }
    }

    // MARK: - Menu bar item

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "dock.rectangle",
            accessibilityDescription: "nanobar"
        )

        let menu = NSMenu()
        menu.delegate = self

        let about = NSMenuItem(title: "About nanobar", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        // Title is filled in by menuWillOpen so it always reflects the live
        // permission state. macOS silently revokes the Accessibility grant
        // when an ad-hoc-signed binary is rebuilt, and without this line the
        // only symptom is titles/clicks mysteriously degrading.
        let permissions = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        permissionItem = permissions

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit nanobar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    /// NSMenuDelegate — runs each time the menu is about to open.
    func menuWillOpen(_ menu: NSMenu) {
        permissionItem?.title = AX.isTrusted
            ? "Accessibility: granted ✓"
            : "⚠️ Accessibility not granted — open Settings…"
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
