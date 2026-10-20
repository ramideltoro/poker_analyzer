import XCTest
import PokerCore
final class StackCallTests: XCTestCase {
    let half = EquityResult(equity:0.5,samplingBound:0.01,samples:12000,exact:false)
    func testCallLimitAndUnmatchedHeadsUpWager() throws {
        let context = try StackCallContext(potCents:1000,uncappedCallCents:500,heroStackCents:200,opponentStackCents:[0])
        XCTAssertEqual(context.callCents,200); XCTAssertEqual(context.unmatchedCents,300)
        XCTAssertEqual(context.potCents,700); XCTAssertEqual(context.effectiveStacks,[0])
        let ev = try context.estimate(half)
        XCTAssertEqual(ev.value,2.5,accuracy:0.0001)
        XCTAssertEqual(ev.requiredEquity,2.0/9,accuracy:0.0001)
    }
    func testRemainingStacksAffectExposureRatherThanCurrentPotShare() throws {
        let a = try StackCallContext(potCents:300,uncappedCallCents:100,heroStackCents:2000,opponentStackCents:[500,3000])
        let b = try StackCallContext(potCents:300,uncappedCallCents:100,heroStackCents:2000,opponentStackCents:[100,4000])
        XCTAssertEqual(a.effectiveStacks,[500,2000]); XCTAssertEqual(b.effectiveStacks,[100,2000])
        XCTAssertEqual(try a.estimate(half).value,try b.estimate(half).value)
        XCTAssertEqual(try a.estimate(half).value,1)
    }
    func testUnsupportedPotsAndInvalidAmountsDoNotProduceEV() {
        XCTAssertThrowsError(try StackCallContext(potCents:50,uncappedCallCents:100,heroStackCents:2000,opponentStackCents:[1000]),"The displayed total pot must already contain at least the wager to match")
        XCTAssertThrowsError(try StackCallContext(potCents:1000,uncappedCallCents:500,heroStackCents:200,opponentStackCents:[0,300]))
        XCTAssertThrowsError(try StackCallContext(potCents:300,uncappedCallCents:100,heroStackCents:2000,opponentStackCents:[1000],sidePots:true))
        for stack in [-1,0,Int.max] { XCTAssertThrowsError(try StackCallContext(potCents:300,uncappedCallCents:100,heroStackCents:stack,opponentStackCents:[1000])) }
        XCTAssertThrowsError(try StackCallContext(potCents:300,uncappedCallCents:1000,heroStackCents:200,opponentStackCents:[1000]))
        XCTAssertThrowsError(try StackCallContext(potCents:300,uncappedCallCents:100,heroStackCents:2000,opponentStackCents:[]))
    }
}
