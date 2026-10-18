import XCTest
import PokerCore

final class EquityTests: XCTestCase {
    func cards(_ text: String) -> [Card] { text.split(separator:" ").map { Card(String($0))! } }
    func testKnownShowdownWinsLossesAndMultiwaySplits() throws {
        let board = cards("2h 4d 7c 9s Jd")
        XCTAssertEqual(try EquityEngine.showdownShare(hole:cards("As Ah"),board:board,villains:[cards("Js Jh")]),0)
        XCTAssertEqual(try EquityEngine.showdownShare(hole:cards("Js Jh"),board:board,villains:[cards("As Ah")]),1)
        let royal = cards("As Ks Qs Js Ts")
        XCTAssertEqual(try EquityEngine.showdownShare(hole:cards("2c 3d"),board:royal,villains:[cards("4c 5d"),cards("6c 7d")]),1.0/3,accuracy:1e-12)
    }
    func testExactRiverEnumerationMatchesCountedCombinations() throws {
        // 45 choose 2 = 990. The remaining ace wins 44 combos; KcKs ties one.
        let result = try EquityEngine.calculate(hole:cards("Kh Kd"),board:cards("Ah Ad Ac 2s 3s"),opponents:1)
        XCTAssertTrue(result.exact); XCTAssertEqual(result.samples,990)
        XCTAssertEqual(result.equity,945.5/990,accuracy:1e-12)
        XCTAssertEqual(result.samplingBound,0)
        let nuts = try EquityEngine.calculate(hole:cards("Th 9h"),board:cards("Ah Kh Qh Jh 2c"),opponents:1)
        XCTAssertEqual(nuts.equity,1)
    }
    func testMonteCarloAgreesWithExactAndSplitsFractionalPots() throws {
        let hole = cards("Kh Kd"), board = cards("Ah Ad Ac 2s 3s")
        let exact = try EquityEngine.calculate(hole:hole,board:board,opponents:1)
        let simulated = try EquityEngine.calculate(hole:hole,board:board,opponents:1,seed:27,exactRiver:false)
        XCTAssertLessThanOrEqual(abs(exact.equity-simulated.equity),simulated.samplingBound)
        XCTAssertEqual(simulated.samplingBound,sqrt(log(40)/(2*12_000)),accuracy:1e-12)
        let split = try EquityEngine.calculate(hole:cards("2c 3d"),board:cards("As Ks Qs Js Ts"),opponents:2,samples:512,seed:7)
        XCTAssertFalse(split.exact); XCTAssertEqual(split.equity,1.0/3,accuracy:1e-12)
    }
    func testPreflopIsReproducibleAndEightOpponentsAreSupported() throws {
        let first = try EquityEngine.calculate(hole:cards("Ah Ad"),board:[],opponents:8,samples:512,seed:123)
        let second = try EquityEngine.calculate(hole:cards("Ah Ad"),board:[],opponents:8,samples:512,seed:123)
        XCTAssertEqual(first,second); XCTAssertTrue((0...1).contains(first.equity))
    }
    func testRejectsDuplicateCardsBadCountsAndCancellation() {
        XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("Ah Ah"),board:[],opponents:1))
        XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("Ah Kd"),board:cards("Ah 2s 3c"),opponents:1))
        XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("Ah Kd"),board:cards("2s 3c"),opponents:1))
        for opponents in [0,9] { XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("Ah Kd"),board:[],opponents:opponents)) }
        XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("Ah Kd"),board:[],opponents:1,samples:0))
        XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("Ah Kd"),board:[],opponents:1,cancelled:{ true }))
        XCTAssertThrowsError(try EquityEngine.calculate(hole:cards("2c 3d"),board:cards("As Ks Qs Js Ts"),opponents:1,cancelled:{ true }))
    }
    func testCallEVAndUncertaintyUsePotBeforeNewCall() throws {
        let equity = EquityResult(equity:0.5,samplingBound:0.1,samples:1000,exact:false)
        let ev = try CallEstimate(equity:equity,potBeforeCall:3,call:1)
        XCTAssertEqual(ev.value,1,accuracy:1e-12)
        XCTAssertEqual(ev.lower,0.6,accuracy:1e-12); XCTAssertEqual(ev.upper,1.4,accuracy:1e-12)
        XCTAssertEqual(ev.requiredEquity,0.25,accuracy:1e-12)
        XCTAssertEqual(try CallEstimate(equity:EquityResult(equity:0.25,samplingBound:0,samples:990,exact:true),potBeforeCall:3,call:1).value,0)
        XCTAssertEqual(try CallEstimate(equity:equity,potBeforeCall:3,call:0).value,1.5)
        for amount in [-1,Double.nan,Double.infinity] {
            XCTAssertThrowsError(try CallEstimate(equity:equity,potBeforeCall:amount,call:1))
            XCTAssertThrowsError(try CallEstimate(equity:equity,potBeforeCall:3,call:amount))
        }
        XCTAssertThrowsError(try CallEstimate(equity:equity,potBeforeCall:0,call:1))
    }
}
