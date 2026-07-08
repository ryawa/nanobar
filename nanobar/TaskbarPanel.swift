//
//  TaskbarPanel.swift
//  nanobar
//
//  One desktop's taskbar: a borderless panel pinned to the bottom edge of
//  the screen that never takes keyboard focus. Each user desktop (Space)
//  gets its own panel, and each panel *belongs* to its desktop — so during
//  a Space-switch animation, macOS slides the old desktop out carrying its
//  bar and the new desktop in carrying its bar, with each showing exactly
//  its own windows.
//

import AppKit
import SwiftUI

final class TaskbarPanel: NSPanel {
    static let barHeight: CGFloat = 40

    /// The desktop this panel was created on and renders chips for.
    let spaceID: UInt64

    init(store: WindowStore, spaceID: UInt64) {
        self.spaceID = spaceID
        super.init(
            contentRect: .zero,
            // .nonactivatingPanel: clicking the bar must not activate our app,
            // otherwise every chip click would first steal focus from the very
            // window the user is trying to switch to.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar                     // float above normal windows
        // .managed = participate in Spaces like a normal window: the panel
        // belongs to the Space it was ordered onto and slides with it during
        // switch animations. Explicit, because floating panels otherwise get
        // special treatment.
        collectionBehavior = [.managed]
        backgroundColor = .clear               // BarView draws its own material background
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false           // ARC owns the panel, not close()

        contentView = FirstMouseHostingView(rootView: BarView(store: store, spaceID: spaceID))

        pinToBottomOfScreen()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // Refuse key/main status entirely — the bar is click-only, so it never
    // needs keyboard focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func screenLayoutChanged() {
        pinToBottomOfScreen()
    }

    private func pinToBottomOfScreen() {
        // screens.first is the primary screen (the one with the menu bar).
        // Using .frame rather than .visibleFrame means the bar sits at the
        // true bottom edge, in the same strip the Dock occupies.
        guard let screen = NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: Self.barHeight
        )
        setFrame(frame, display: true)
    }
}

/// In AppKit, the first click on a non-key window normally just focuses the
/// window and is swallowed. Our panel never becomes key, so without this
/// override every chip would need two clicks.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
