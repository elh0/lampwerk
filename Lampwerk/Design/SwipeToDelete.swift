import SwiftUI

/// iOS-style swipe to delete for the app's own ruled rows (they aren't Lists, so
/// `.swipeActions` isn't available). Swipe left to reveal a bin; tap it, or swipe all
/// the way, to call `action`. A swipe right, or another swipe,
/// closes it. Press and hold still works alongside.
struct SwipeToDelete: ViewModifier {
    var enabled = true
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var settled: CGFloat = 0
    private let reveal: CGFloat = 72
    private let fullSwipe: CGFloat = 180

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                // A plain word on a raised panel, no red block.
                Button {
                    close()
                    action()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .frame(width: max(reveal, -offset))
                        .frame(maxHeight: .infinity)
                        .background(Palette.p2)
                        .overlay(alignment: .leading) { Palette.rule.frame(width: 1) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            content
                .background(Palette.p0)
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { v in
                    // Only sideways drags; up and down stay with the scroll view.
                    guard enabled, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    offset = min(0, settled + v.translation.width)
                }
                .onEnded { v in
                    guard enabled, abs(v.translation.width) > abs(v.translation.height) * 1.5 else {
                        if offset != settled { withAnimation(.snappy(duration: 0.2)) { offset = settled } }
                        return
                    }
                    let end = settled + v.predictedEndTranslation.width
                    if -end > fullSwipe {
                        close()
                        action()
                    } else if -end > reveal / 2 {
                        withAnimation(.snappy(duration: 0.2)) { offset = -reveal }
                        settled = -reveal
                    } else {
                        close()
                    }
                },
            including: enabled ? .all : .subviews
        )
        .accessibilityAction(named: "Delete") { if enabled { action() } }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) { offset = 0 }
        settled = 0
    }
}

extension View {
    /// Swipe left to reveal a bin. `action` should offer an undo.
    func swipeToDelete(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(enabled: enabled, action: action))
    }
}
