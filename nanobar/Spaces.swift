//
//  Spaces.swift
//  nanobar
//
//  Which Space (virtual desktop) is active, and which Space a window belongs
//  to. There is no public API for either, so this uses the same category of
//  private-but-stable CoreGraphics "CGS" calls that AltTab, yabai, and every
//  other Space-aware tool relies on.
//

import AppKit

private typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ connection: CGSConnectionID) -> UInt64

// "Copy" in the name means the caller owns the returned array, hence the
// Unmanaged return + takeRetainedValue at the call site. The mask selects
// which Spaces to consider; 7 = current | other | minimized (all of them).
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(
    _ connection: CGSConnectionID,
    _ mask: Int32,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

// Per-display configuration dictionaries, including which Space each display
// is currently showing. Also a "Copy" call, so the caller owns the result.
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> Unmanaged<CFArray>?

enum Spaces {
    private static let connection = CGSMainConnectionID()
    private static let allSpacesMask: Int32 = 7

    /// The Space currently being displayed, or 0 if it can't be determined.
    static var activeSpaceID: UInt64 {
        CGSGetActiveSpace(connection)
    }

    struct DisplayLayout {
        /// The Space each display is currently showing, in system order (the
        /// primary display comes first in practice). Unlike `activeSpaceID`,
        /// which follows keyboard focus between displays, this describes what
        /// is physically visible on each screen.
        let currentSpaceIDs: [UInt64]
        /// Every user desktop Space in left-to-right order (concatenated
        /// across displays). Fullscreen-app Spaces are excluded — they exist
        /// too, but a taskbar cares about desktops.
        let orderedUserSpaceIDs: [UInt64]
    }

    /// What each display is showing and how the desktops are arranged.
    static func displayLayout() -> DisplayLayout {
        guard let displays = CGSCopyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return DisplayLayout(currentSpaceIDs: [], orderedUserSpaceIDs: [])
        }

        var current: [UInt64] = []
        var ordered: [UInt64] = []
        for display in displays {
            if let space = display["Current Space"] as? [String: Any], let id = spaceID(from: space) {
                current.append(id)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                // type 0 = a normal user desktop; fullscreen apps get type 4.
                guard (space["type"] as? NSNumber)?.intValue == 0, let id = spaceID(from: space) else {
                    continue
                }
                ordered.append(id)
            }
        }
        return DisplayLayout(currentSpaceIDs: current, orderedUserSpaceIDs: ordered)
    }

    private static func spaceID(from dictionary: [String: Any]) -> UInt64? {
        ((dictionary["id64"] as? NSNumber) ?? (dictionary["ManagedSpaceID"] as? NSNumber))?.uint64Value
    }

    /// The Space(s) a window belongs to. Windows set to appear on every
    /// desktop return several; a normal window returns one. The association
    /// survives minimizing — that's how macOS knows to switch you back to the
    /// right Space when you restore a window from the Dock.
    static func spaceIDs(ofWindow windowID: CGWindowID) -> [UInt64] {
        guard let numbers = CGSCopySpacesForWindows(
            connection,
            allSpacesMask,
            [windowID] as CFArray
        )?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return numbers.map { $0.uint64Value }
    }
}
