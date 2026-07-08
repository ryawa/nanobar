//
//  nanobarApp.swift
//  nanobar
//

import SwiftUI

@main
struct nanobarApp: App {
    // All real setup happens in AppDelegate: SwiftUI scenes can't create the
    // kind of borderless, always-on-top, non-focus-stealing panel the taskbar
    // needs, so we drop down to AppKit for that part.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No regular windows. The empty Settings scene is a placeholder because
        // a SwiftUI App must declare at least one scene.
        Settings {
            EmptyView()
        }
    }
}
