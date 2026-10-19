import AppKit
import SwiftUI

/// Uses the desktop's usable frame, preserving the menu bar, Dock and native window controls.
struct MaximizedWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowSizingView { WindowSizingView() }
    func updateNSView(_ nsView: WindowSizingView,context: Context) {}
    final class WindowSizingView: NSView {
        private var scheduled = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !scheduled, let window else { return }
            scheduled = true
            DispatchQueue.main.async { [weak window] in
                guard let window, !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main else { return }
                window.setFrame(screen.visibleFrame,display:true,animate:false)
            }
        }
    }
}
