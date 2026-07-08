//
//  Accessibility.swift
//  nanobar
//
//  Thin wrappers around the macOS Accessibility (AX) API. This is the layer
//  that lets one app inspect and control another app's windows: read titles,
//  raise, focus, minimize. It requires the user to grant the Accessibility
//  permission in System Settings.
//

import AppKit
import ApplicationServices

// Private (but stable and used by every taskbar/window-switcher app) function
// that maps an AX window element to the CGWindowID that CoreGraphics uses.
// There is no public API for this; @_silgen_name binds directly to the symbol.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

enum AX {
    /// An app's window as seen by the AX API, paired with its CoreGraphics ID
    /// so it can be matched against the CGWindowList entries in WindowStore.
    struct WindowHandle {
        let element: AXUIElement
        let windowID: CGWindowID?
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that points the user at
    /// System Settings → Privacy & Security → Accessibility.
    static func promptForTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// All AX windows of the app with the given process ID.
    static func windows(inAppWithPID pid: pid_t) -> [WindowHandle] {
        let app = AXUIElementCreateApplication(pid)
        // If an app is hung, AX calls to it block. Cap the wait so one frozen
        // app can't freeze the whole bar.
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let elements: [AXUIElement] = copyAttribute(app, kAXWindowsAttribute) else { return [] }
        return elements.map { WindowHandle(element: $0, windowID: windowID(of: $0)) }
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    /// The CGWindowID of the window that currently has keyboard focus in the
    /// given app, or nil if it can't be determined.
    static func focusedWindowID(inAppWithPID pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let focused: AXUIElement = copyAttribute(app, kAXFocusedWindowAttribute) else { return nil }
        return windowID(of: focused)
    }

    static func title(of element: AXUIElement) -> String? {
        let title: String? = copyAttribute(element, kAXTitleAttribute)
        return title?.isEmpty == false ? title : nil
    }

    /// "AXStandardWindow" for real windows; tooltips, popovers, and other
    /// helper windows report something else (or nothing).
    static func subrole(of element: AXUIElement) -> String? {
        copyAttribute(element, kAXSubroleAttribute)
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        let minimized: Bool? = copyAttribute(element, kAXMinimizedAttribute)
        return minimized ?? false
    }

    static func setMinimized(_ element: AXUIElement, _ minimized: Bool) {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, minimized as CFTypeRef)
    }

    /// Bring a window to the front of its app and make it the main window.
    /// (The app itself still has to be activated separately — see WindowStore.)
    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// Reads one AX attribute and casts it to the type the caller asks for.
    /// Returns nil on any failure (no permission, attribute missing, hung app…).
    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
