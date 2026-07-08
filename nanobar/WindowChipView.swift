//
//  WindowChipView.swift
//  nanobar
//
//  One taskbar chip: app icon + window title. Highlighted when its window is
//  focused, subtly highlighted on hover, dimmed when minimized.
//

import SwiftUI

struct WindowChipView: View {
    let window: TaskbarWindow
    let onClick: () -> Void

    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        HStack(spacing: 6) {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            Text(window.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // Fixed-width chips, Windows-style, so the row doesn't reflow as
        // titles change.
        .frame(width: 170, alignment: .leading)
        .background(shape.fill(backgroundColor))
        .opacity(window.isMinimized ? 0.55 : 1)
        // Make the whole chip clickable, not just the icon and text.
        .contentShape(shape)
        .onTapGesture(perform: onClick)
        .onHover { isHovering = $0 }
        .help(window.title)
    }

    private var backgroundColor: Color {
        if window.isFocused { return Color.primary.opacity(0.22) }
        if isHovering { return Color.primary.opacity(0.12) }
        return Color.primary.opacity(0.05)
    }
}
