import XCTest
@testable import PokerCore

final class DecisionPriceTests: XCTestCase {
    func testMinimumPotAndMaximumCallSolveBreakEvenEquation() throws {
        for (equity,call,minimum) in [(0.25,1.0,3.0),(0.5,2.0,2.0),(0.1,0.5,4.5),(1.0,3.0,0.0)] {
            let value = try DecisionPrice(equity:equity,pot:max(0.01,minimum),call:call)
            XCTAssertEqual(try XCTUnwrap(value.minimumPot),minimum,accuracy:1e-10)
            if minimum > 0 { XCTAssertEqual(value.callEV,0,accuracy:1e-10); XCTAssertEqual(try XCTUnwrap(value.maximumCall),call,accuracy:1e-10) }
        }
        XCTAssertNil(try DecisionPrice(equity:0,pot:3,call:1).minimumPot)
        XCTAssertEqual(try DecisionPrice(equity:0,pot:3,call:0).minimumPot,0)
        XCTAssertNil(try DecisionPrice(equity:1,pot:3,call:1).maximumCall)
        XCTAssertEqual(try DecisionPrice(equity:0.2,pot:3,call:1).callEV,-0.2,accuracy:1e-10)
        XCTAssertThrowsError(try DecisionPrice(equity:.nan,pot:3,call:1))
        XCTAssertThrowsError(try DecisionPrice(equity:0.5,pot:3,call:-1))
    }
    func testRaiseScenarioAccountsForCalledAndFoldedOutcomes() throws {
        let bluff = try RaiseScenario(pot:3,risk:2,opponentAdds:1,equityWhenCalled:0,foldFrequency:0.4)
        XCTAssertEqual(bluff.ev,0,accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(bluff.minimumPot),3,accuracy:1e-10)
        XCTAssertEqual(bluff.requiredFoldFrequency,0.4)
        let value = try RaiseScenario(pot:10,risk:5,opponentAdds:3,equityWhenCalled:0.5,foldFrequency:0.25)
        XCTAssertEqual(value.calledEV,4)
        XCTAssertEqual(value.ev,5.5)
        XCTAssertEqual(try XCTUnwrap(value.minimumPot),1.2,accuracy:1e-10)
        XCTAssertNil(try RaiseScenario(pot:3,risk:2,opponentAdds:1,equityWhenCalled:0,foldFrequency:0).minimumPot)
        XCTAssertThrowsError(try RaiseScenario(pot:3,risk:2,opponentAdds:1,equityWhenCalled:1.1,foldFrequency:0))
    }
}
