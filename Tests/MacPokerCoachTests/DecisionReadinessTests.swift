import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class DecisionReadinessTests: XCTestCase {
    func testConfirmedCardsWithoutTableDoNotClaimCardsAreMissing() {
        let m=HandAnalysisModel(), helper=HandAnalysisTests()
        m.update(helper.hand())
        XCTAssertTrue(m.hasCards); XCTAssertEqual(m.presentedAdvice.state,.tableReading)
        XCTAssertTrue(m.simulationSummary.contains("Cards confirmed"))
        XCTAssertTrue(m.presentedAdvice.reason.contains("Your cards are confirmed"))
        XCTAssertFalse(m.presentedAdvice.reason.contains("No current cards"))
        m.reset()
    }
    func testPartialBoardKeepsFreshHoleCardsSeparateFromUnsupportedPokerMath() async throws {
        let app=AppModel(log:.disabled,analysis:HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.7,samplingBound:0.01,samples:1000,exact:false) })), helper=HandAnalysisTests()
        let h=helper.hand(["9s","6h"]), t=DynamicDecisionTests().table()
        for _ in 0..<3 { app.acceptScan(CardScan(cards:h.hole,table:t)) }
        XCTAssertNotNil(app.hand); XCTAssertEqual(app.confirmedHole.count,2)
        let flop=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
        let partial=flop.hole+Array(flop.board.prefix(2))
        for _ in 0..<3 { app.acceptScan(CardScan(cards:partial,table:t)) }
        XCTAssertNil(app.hand); XCTAssertEqual(app.confirmedHole.map(\.card),h.hole.map(\.card))
        XCTAssertNil(app.analysis.callEstimate); XCTAssertNil(app.analysis.result)
        XCTAssertEqual(app.analysis.actionAdvice.state,.boardReading)
        XCTAssertTrue(app.analysis.actionAdvice.reason.contains("Your two hole cards are read"))
        for _ in 0..<3 { app.acceptScan(CardScan(cards:flop.hole+flop.board,table:t)) }
        XCTAssertEqual(app.hand?.board.count,3)
        try await helper.waitForResult(app.analysis)
        XCTAssertEqual(app.analysis.actionAdvice.kind,.bet)
        app.clear("synthetic stop"); XCTAssertTrue(app.confirmedHole.isEmpty); XCTAssertEqual(app.analysis.presentedAdvice.state,.cards)
    }
func testDisappearingBoardCannotTurnSameHoleCardsBackIntoPreflopAdvice() {
    let app=AppModel(log:.disabled), helper=HandAnalysisTests()
    let h=helper.hand(["Ks","Kd"],board:["Ah","7d","2c"]), t=DynamicDecisionTests().table()
    for _ in 0..<3 { app.acceptScan(CardScan(cards:h.hole+h.board,table:t)) }
    XCTAssertEqual(app.hand?.board.count,3)
    for _ in 0..<3 { app.acceptScan(CardScan(cards:h.hole,table:t)) }
    XCTAssertNil(app.hand); XCTAssertNil(app.analysis.actionAdvice.kind)
    XCTAssertEqual(app.analysis.actionAdvice.state,.boardReading)
    XCTAssertEqual(app.confirmedHole.count,2)
    let corrected=helper.hand(["Ks","Kd"],board:["Ah","8d","2c"])
    for _ in 0..<3 { app.acceptScan(CardScan(cards:corrected.hole+corrected.board,table:t)) }
    XCTAssertEqual(app.hand?.board.map(\.card),corrected.board.map(\.card),"Consistent full readings can correct prior recognition")
    app.clear("synthetic end")
}
func testNewHoleCardsWithIncompleteBoardCannotDisplayPreviousHandsSuggestion() {
    let app=AppModel(log:.disabled), helper=HandAnalysisTests(), t=PositionAndSavedAdviceTests().table()
    let first=helper.hand(["Ks","Kd"])
    for _ in 0..<3 { app.acceptScan(CardScan(cards:first.hole,table:t)) }
    XCTAssertEqual(app.analysis.presentedAdvice.kind,.raise)
    let next=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
    for _ in 0..<3 { app.acceptScan(CardScan(cards:next.hole+Array(next.board.prefix(2)),table:t)) }
    XCTAssertNil(app.hand); XCTAssertEqual(app.confirmedHole.map(\.card),next.hole.map(\.card))
    XCTAssertFalse(app.analysis.showsLastAdvice); XCTAssertNil(app.analysis.presentedAdvice.kind)
    XCTAssertEqual(app.analysis.presentedAdvice.state,.boardReading)
    app.clear("synthetic end")
}
    func testFreshBlankOrPartialPairDoesNotShowConfirmedCurrentHoleCards() {
        let app=AppModel(log:.disabled), pair=HandAnalysisTests().hand().hole
        app.acceptScan(CardScan(cards:pair))
        XCTAssertTrue(app.confirmedHole.isEmpty); XCTAssertEqual(app.analysis.presentedAdvice.state,.cardConfirmation)
        app.acceptScan(CardScan(cards:pair)); XCTAssertEqual(app.confirmedHole.count,2)
        app.acceptScan(CardScan(cards:[pair[0]]))
        XCTAssertTrue(app.confirmedHole.isEmpty); XCTAssertEqual(app.analysis.actionAdvice.state,.cardConfirmation)
        app.acceptScan(CardScan(cards:[]))
        XCTAssertTrue(app.confirmedHole.isEmpty); XCTAssertEqual(app.analysis.actionAdvice.state,.cardRecognition)
        XCTAssertTrue(app.analysis.actionAdvice.reason.contains("no accepted card faces"))
    }
    func testUnstableOpponentAmountsNameTableInputRatherThanWaitingForHand() {
        let m=HandAnalysisModel(), hand=HandAnalysisTests().hand()
        var t=DynamicDecisionTests().table(); t.callCents=nil; t.controls=nil; t.seats[0].activity = .unknown
        m.update(hand,table:t); m.update(hand,table:t)
        XCTAssertEqual(m.presentedAdvice.state,.tableReading)
        XCTAssertTrue(m.presentedAdvice.reason.contains("which players")); XCTAssertTrue(m.presentedAdvice.reason.contains("cards are confirmed"))
        m.reset()
    }
}
