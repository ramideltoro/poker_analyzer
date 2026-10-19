import XCTest
import AppKit
@testable import MacPokerCoach

@MainActor final class WindowSizingTests: XCTestCase {
    func testHiddenWindowFillsUsableDesktopOnceAndAllowsManualResizing() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No desktop screen is attached") }
        let window = NSWindow(contentRect:NSRect(x:40,y:40,width:1000,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sizing = MaximizedWindow.WindowSizingView()
        window.contentView = sizing
        try await Task.sleep(nanoseconds:50_000_000)
        XCTAssertEqual(window.frame.width,screen.visibleFrame.width,accuracy:1)
        XCTAssertEqual(window.frame.height,screen.visibleFrame.height,accuracy:1)
        XCTAssertEqual(window.frame.minX,screen.visibleFrame.minX,accuracy:1)
        XCTAssertEqual(window.frame.minY,screen.visibleFrame.minY,accuracy:1)
        XCTAssertFalse(window.isVisible,"This metadata-only integration test must not show a desktop window")
        let smaller = NSRect(x:screen.visibleFrame.minX+20,y:screen.visibleFrame.minY+20,width:1000,height:720)
        window.setFrame(smaller,display:false)
        try await Task.sleep(nanoseconds:50_000_000)
        XCTAssertEqual(window.frame.width,smaller.width,accuracy:1)
        XCTAssertEqual(window.frame.height,smaller.height,accuracy:1)
        XCTAssertNil(sizing.hitTest(.zero))
    }
}
