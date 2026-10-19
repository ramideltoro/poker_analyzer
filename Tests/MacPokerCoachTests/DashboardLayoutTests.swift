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
        for width: CGFloat in [972,1092] {
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
            XCTAssertEqual(empty,DashboardStyle.analysisHeight,accuracy:1)
        }
    }
}

extension DashboardLayoutTests {
    func testWholeDashboardFitsOneScreenAcrossReadingStates() async throws {
        let app = AppModel(log:.disabled), fixture = AutomaticAnalysisTests()
        let hand = HandAnalysisTests().hand(board:["2c","7s","Jd"])
        func check() {
            for width: CGFloat in [1000,1120] {
                let content = RootView(model:app).frame(width:width).fixedSize(horizontal:false,vertical:true).preferredColorScheme(.dark)
                let host = NSHostingView(rootView:content); host.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.height,720,"Dashboard must fit the minimum window without scrolling")
                XCTAssertEqual(host.fittingSize.width,width,accuracy:1)
            }
        }
        check()
        for _ in 0..<3 { app.acceptScan(CardScan(cards:hand.hole+hand.board,table:fixture.table())) }
        try await fixture.wait(app.analysis); check()
        var review = hand; review.isReview = true
        var table = fixture.table(); table.seats[2].activity = .folded
        app.analysis.update(review,table:table); app.analysis.update(review,table:table)
        try await fixture.wait(app.analysis); check()
        app.analysis.setAutomatic(false); check()
        app.analysis.potText = "100000.00"; app.analysis.callText = "10000.00"; check()
        var nine = fixture.table()
        for i in 4...9 { nine.seats.append(TableSeat(id:i,bounds:UnitRect(x:Double(i)/10,y:0.3,width:0.1,height:0.05),isHero:false,stackCents:99999,activity:.folded)) }
        app.analysis.update(hand,table:nine); app.analysis.update(hand,table:nine); check()
        app.clear("Stopped"); check()
    }
}
