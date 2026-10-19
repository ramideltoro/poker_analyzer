import XCTest
import SwiftUI
import AppKit
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class DashboardLayoutTests: XCTestCase {
    func host(_ model: HandAnalysisModel,width: CGFloat) -> NSHostingView<some View> {
        let view = HandAnalysisView(analysis:model).frame(width:width).fixedSize(horizontal:false,vertical:true).preferredColorScheme(.dark)
        return NSHostingView(rootView:view)
    }
    func testPanelHeightIsIdenticalForEmptyReadyUpdatingAndManualStates() async throws {
        let fixture = AutomaticAnalysisTests(), model = fixture.model()
        for width: CGFloat in [794,924] {
            let view = host(model,width:width)
            view.layoutSubtreeIfNeeded()
            let empty = view.fittingSize.height
            try await fixture.confirm(model,fixture.table())
            try await Task.sleep(nanoseconds:20_000_000)
            view.layoutSubtreeIfNeeded(); XCTAssertEqual(view.fittingSize.height,empty,accuracy:1)
            model.update(fixture.hand(),table:nil)
            try await Task.sleep(nanoseconds:20_000_000)
            view.layoutSubtreeIfNeeded(); XCTAssertEqual(view.fittingSize.height,empty,accuracy:1)
            model.setAutomatic(false)
            try await Task.sleep(nanoseconds:20_000_000)
            view.layoutSubtreeIfNeeded(); XCTAssertEqual(view.fittingSize.height,empty,accuracy:1)
            model.reset(); model.setAutomatic(true)
            XCTAssertGreaterThan(empty,1000)
        }
    }
}
