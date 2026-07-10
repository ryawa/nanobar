//
//  BarView.swift
//  nanobar
//
//  The SwiftUI content of the taskbar panel: a horizontally scrolling row of
//  window chips on a translucent material background.
//

import SwiftUI

struct BarView: View {
    @ObservedObject var store: WindowStore
    /// The desktop whose windows this bar shows.
    let spaceID: UInt64

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.windowsBySpace[spaceID] ?? []) { window in
                    WindowChipView(window: window) {
                        store.handleClick(on: window)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: TaskbarPanel.barHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
