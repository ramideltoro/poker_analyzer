import XCTest
import PokerCore
@testable import TableRecognition

final class FoldReviewTests: XCTestCase {
    func face(_ code: String,_ x: Double,_ y: Double) -> DetectedCard {
        DetectedCard(card:Card(code)!,bounds:UnitRect(x:x,y:y,width:0.07,height:0.12))
    }
    var hole: [DetectedCard] { [face("Ah",0.4,0.7),face("Kd",0.48,0.7)] }
    func board(_ codes: [String]) -> [DetectedCard] { codes.enumerated().map { face($0.element,0.25+Double($0.offset)*0.08,0.4) } }
    func testFoldContinuesFlopTurnRiverAndStopsOnBoardClear() {
        var tracker = FoldReviewTracker()
        let flop = board(["2c","7s","Jd"])
        let live = LiveHand(hole:hole,board:flop,timestamp:Date())
        XCTAssertFalse(tracker.accept(live:live,scan:CardScan(cards:hole+flop))!.isReview)
        XCTAssertNil(tracker.accept(live:nil,scan:CardScan(cards:flop)))
        XCTAssertTrue(tracker.accept(live:nil,scan:CardScan(cards:flop))!.isReview)
        for codes in [["2c","7s","Jd","Qs"],["2c","7s","Jd","Qs","3s"]] {
            let scan = CardScan(cards:board(codes))
            XCTAssertNil(tracker.accept(live:nil,scan:scan))
            let review = tracker.accept(live:nil,scan:scan)!
            XCTAssertEqual(review.hole.map(\.card),hole.map(\.card)); XCTAssertEqual(review.board.count,codes.count)
        }
        let empty = CardScan(cards:[],table:TableObservation(potCents:15,callCents:nil,seats:[TableSeat(id:1,bounds:hole[0].bounds,isHero:true,stackCents:300,activity:.folded)]))
        XCTAssertNil(tracker.accept(live:nil,scan:empty)); XCTAssertNil(tracker.accept(live:nil,scan:empty))
        XCTAssertNil(tracker.accept(live:nil,scan:CardScan(cards:flop)),"Ended hand cannot resume an old board")
    }
    func testPreflopFoldKeepsSavedCardsAndCanFollowFirstVisibleFlop() {
        var tracker = FoldReviewTracker()
        let live = LiveHand(hole:hole,board:[],timestamp:Date())
        _ = tracker.accept(live:live,scan:CardScan(cards:hole))
        let folded = TableObservation(potCents:30,callCents:nil,seats:[TableSeat(id:1,bounds:hole[0].bounds,isHero:true,stackCents:300,activity:.folded)])
        let empty = CardScan(cards:[],table:folded)
        XCTAssertNil(tracker.accept(live:nil,scan:empty))
        XCTAssertTrue(tracker.accept(live:nil,scan:empty)?.isReview == true)
        let flop = CardScan(cards:board(["2c","7s","Jd"]),table:folded)
        XCTAssertNil(tracker.accept(live:nil,scan:flop))
        XCTAssertEqual(tracker.accept(live:nil,scan:flop)?.board.count,3)
    }
    func testReplacementCollisionNewHandAndReset() {
        var tracker = FoldReviewTracker()
        let flop = board(["2c","7s","Jd"]), live = LiveHand(hole:hole,board:flop,timestamp:Date())
        _ = tracker.accept(live:live,scan:CardScan(cards:hole+flop))
        for _ in 0..<2 { XCTAssertNil(tracker.accept(live:nil,scan:CardScan(cards:board(["2c","7s","Ah"])))) }
        let new = LiveHand(hole:[face("Qc",0.4,0.7),face("5c",0.48,0.7)],board:[],timestamp:Date())
        XCTAssertEqual(tracker.accept(live:new,scan:CardScan(cards:new.hole))?.hole.map(\.card),new.hole.map(\.card))
        tracker.reset(); XCTAssertNil(tracker.accept(live:nil,scan:CardScan(cards:flop)))
    }
    func testOneMissingFrameOrPartialHeroCardDoesNotStartReview() {
        var tracker = FoldReviewTracker(), live = LiveHand(hole:hole,board:board(["2c","7s","Jd"]),timestamp:Date())
        _ = tracker.accept(live:live,scan:CardScan(cards:live.hole+live.board))
        XCTAssertNil(tracker.accept(live:nil,scan:CardScan(cards:live.board)))
        XCTAssertNil(tracker.accept(live:nil,scan:CardScan(cards:[hole[0]]+live.board)))
        live.timestamp = Date(); XCTAssertFalse(tracker.accept(live:live,scan:CardScan(cards:live.hole+live.board))!.isReview)
    }
}
