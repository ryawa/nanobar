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

    // A mouse's scroll wheel only produces *vertical* ticks, which the bar's
    // horizontal-only ScrollView ignores. Every event bound for this panel
    // passes through sendEvent before it's routed to a view, so rewrite
    // vertical wheel ticks as horizontal ones here. Trackpad and Magic Mouse
    // swipes (precise deltas, gesture phases) can already scroll sideways and
    // pass through untouched.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel,
              !event.hasPreciseScrollingDeltas,            // wheel ticks are coarse; trackpads are precise
              event.phase == [], event.momentumPhase == [], // not part of a swipe gesture
              event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let cgEvent = event.cgEvent?.copy()
        else {
            super.sendEvent(event)
            return
        }
        // NSEvent's deltas are read-only, so edit the underlying CGEvent:
        // wheel deltas live in numbered "axis" fields, axis 1 = vertical,
        // axis 2 = horizontal, each stored in three representations
        // (line-based, pixel-based, fixed-point). Move axis 1 to axis 2.
        let axes: [(vertical: CGEventField, horizontal: CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
        ]
        for axis in axes {
            cgEvent.setDoubleValueField(axis.horizontal, value: cgEvent.getDoubleValueField(axis.vertical))
            cgEvent.setDoubleValueField(axis.vertical, value: 0)
        }
        super.sendEvent(NSEvent(cgEvent: cgEvent) ?? event)
    }

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
