import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class ActionAdviceTests: XCTestCase {
    func testCallFoldCheckAndMarginalReasonsMatchThePrice() throws {
        func advice(_ q: Double,_ call: Double = 1,bound: Double = 0) throws -> ActionAdvice {
            let result = EquityResult(equity:q,samplingBound:bound,samples:100000,exact:bound == 0)
            return ActionAdvice.priced(equity:q,estimate:try CallEstimate(equity:result,potBeforeCall:3,call:call),call:call)
        }
        XCTAssertEqual(try advice(0.5).title,"CALL")
        XCTAssertEqual(try advice(0.2).title,"FOLD")
        XCTAssertEqual(try advice(0,0).title,"CHECK")
        XCTAssertTrue(try advice(0.25,bound:0.01).marginal)
        XCTAssertTrue(try advice(0.2).reason.contains("-0.20"))
    }
    func testRaiseRequiresUnbeatableRiverHandLegalSizeAndCoveringStacks() throws {
        let hole = ["Ah","Kh"].compactMap(Card.init), board = ["Qh","Jh","Th","2c","3d"].compactMap(Card.init)
        let result = try EquityEngine.calculate(hole:hole,board:board,opponents:1)
        var table = TableObservation(potCents:300,callCents:100,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:1000,betCents:100,activity:.active),
            TableSeat(id:2,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:1000,betCents:0,activity:.active)],controls:TableControls(canFold:true,canCall:true,canRaise:true,raiseToCents:200))
        XCTAssertEqual(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table)?.title,"RAISE")
        table.seats[0].stackCents = 50
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table))
        table.seats[0].stackCents = 1000; table.controls?.raiseToCents = 2000
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table))
        table.controls?.raiseToCents = 200; table.sidePots = true
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table))
        table.sidePots = false
        let sampled = EquityResult(equity:0.99,samplingBound:0.01,samples:100000,exact:false,outcomes:ShowdownProbabilities(win:0.99,tie:0,lose:0.01))
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:sampled,table:table))
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:Array(board.prefix(4)),result:result,table:table))
    }
    @MainActor func testStoppedAndReviewStatesCannotGiveLiveAdvice() {
        let model = HandAnalysisModel()
        XCTAssertEqual(model.actionAdvice.title,"WAIT")
        var hand = HandAnalysisTests().hand(board:["2c","7s","Jd"]); hand.isReview = true
        model.update(hand)
        XCTAssertNil(model.actionAdvice.kind)
        model.reset(); XCTAssertEqual(model.actionAdvice.title,"WAIT")
    }
}
