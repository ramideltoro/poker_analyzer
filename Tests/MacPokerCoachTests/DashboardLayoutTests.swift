import XCTest
import SwiftUI
import AppKit
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class DashboardLayoutTests: XCTestCase {
    func testDashboardGridUsesTheWholeAvailableWindow() {
        for size in [CGSize(width:1000,height:720),CGSize(width:1120,height:760),CGSize(width:1440,height:900),CGSize(width:1900,height:1020)] {
            let root = DashboardMetrics(size:size)
            let grid = AnalysisMetrics(size:CGSize(width:size.width-root.padding*2,height:root.analysis))
            XCTAssertEqual(root.header+root.cards+16+root.analysis+root.gap*3+root.padding*2,size.height,accuracy:0.01)
            XCTAssertEqual(grid.summary+grid.body+24+grid.gap*2,root.analysis,accuracy:0.01)
            XCTAssertEqual(grid.leftWidth+grid.middleWidth+grid.rightWidth+grid.gap*2,size.width-root.padding*2,accuracy:0.01)
            XCTAssertEqual(grid.outcome+grid.details+grid.gap,grid.body,accuracy:0.01)
            XCTAssertEqual(grid.threshold+grid.categories+grid.gap,grid.body,accuracy:0.01)
            XCTAssertGreaterThanOrEqual(grid.details,200)
            XCTAssertGreaterThanOrEqual(grid.categories,180)
        }
    }
    func testPanelsKeepTheirSizeAcrossLiveReviewManualAndNineSeatStates() async throws {
        let model = AppModel(log:.disabled), fixture = AutomaticAnalysisTests()
        let hand = HandAnalysisTests().hand(board:["2c","7s","Jd"])
        func check() {
            for size in [CGSize(width:1000,height:720),CGSize(width:1440,height:900),CGSize(width:1900,height:1020)] {
                let host = NSHostingView(rootView:RootView(model:model).frame(width:size.width,height:size.height).preferredColorScheme(.dark))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width,size.width,accuracy:1)
                XCTAssertEqual(host.fittingSize.height,size.height,accuracy:1)
            }
        }
        check()
        for _ in 0..<3 { model.acceptScan(CardScan(cards:hand.hole+hand.board,table:fixture.table())) }
        try await fixture.wait(model.analysis); check()
        var review = hand; review.isReview = true
        var table = fixture.table(); table.seats[2].activity = .folded
        model.analysis.update(review,table:table); model.analysis.update(review,table:table)
        try await fixture.wait(model.analysis); check()
        model.analysis.setAutomatic(false); model.analysis.potText = "100000.00"; model.analysis.callText = "10000.00"; check()
        for i in 4...9 { table.seats.append(TableSeat(id:i,bounds:UnitRect(x:Double(i)/10,y:0.3,width:0.1,height:0.05),isHero:false,stackCents:99999,activity:.folded)) }
        model.analysis.update(hand,table:table); model.analysis.update(hand,table:table); check()
        model.clear("Stopped"); check()
    }
    func testStatisticsPageFitsEmptyAndRecordedHistoryAtMinimumAndFullSize() {
        let model = AppModel(log:.disabled), f = PlayTrackingTests()
        for loaded in [false,true] {
            if loaded { f.feed(model.tracking,f.table(),f.hand()); f.feed(model.tracking,f.table(stack:1200),f.hand(["Qc","Qs"]),at:1) }
            for size in [CGSize(width:1000,height:720),CGSize(width:1440,height:900),CGSize(width:1900,height:1020)] {
                let host = NSHostingView(rootView:RootView(model:model,page:1).frame(width:size.width,height:size.height).preferredColorScheme(.dark))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width,size.width,accuracy:1)
                XCTAssertEqual(host.fittingSize.height,size.height,accuracy:1)
            }
        }
    }
}
