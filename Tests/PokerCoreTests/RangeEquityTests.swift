import XCTest
import PokerCore
final class RangeEquityTests: XCTestCase {
    func c(_ text:String) -> [Card] { text.split(separator:" ").map { Card(String($0))! } }
    func testRangeComboCountsAndBlockersAreExplicit() throws {
        let deck=Suit.allCases.flatMap { s in (2...14).map { Card(rank:$0,suit:s) } }
        let expected:[OpponentRange:Int]=[.random:1326,.caller:266,.tightRaise:50,.balancedRaise:128,.looseRaise:318,.tightReraise:16,.balancedReraise:34,.looseReraise:50]
        for range in OpponentRange.allCases {
            var count=0
            for a in 0..<51 { for b in a+1..<52 { if range.contains([deck[a],deck[b]]) { count+=1 } } }
            XCTAssertEqual(count,expected[range],range.rawValue)
        }
        XCTAssertTrue(OpponentRange.balancedRaise.contains(c("As Jd")))
        XCTAssertFalse(OpponentRange.tightRaise.contains(c("As Qd")))
        XCTAssertFalse(OpponentRange.caller.contains(c("7s 2d")))
    }
    func testExactRangeRiverAgreesWithIndependentEnumeration() throws {
        let hole=c("Kh Kd"), board=c("Ah Ad Ac 2s 3s")
        let deck=Suit.allCases.flatMap { s in (2...14).map { Card(rank:$0,suit:s) } }.filter { !(hole+board).contains($0) }
        for range in [OpponentRange.random,.caller,.balancedRaise,.tightReraise] {
            var sum=0.0,count=0
            for a in 0..<deck.count-1 { for b in a+1..<deck.count {
                let hand=[deck[a],deck[b]]
                if range.contains(hand) { sum += try EquityEngine.showdownShare(hole:hole,board:board,villains:[hand]); count+=1 }
            } }
            let r=try RangeEquityEngine.calculate(hole:hole,board:board,ranges:[range])
            XCTAssertTrue(r.exact); XCTAssertEqual(r.samples,count); XCTAssertEqual(r.equity,sum/Double(count),accuracy:1e-12)
        }
    }
    func testMultiwayRangesRespectCollisionsSplitsAndReproducibleSeeds() throws {
        let first=try RangeEquityEngine.calculate(hole:c("9s 8s"),ranges:[.balancedRaise,.caller],samples:4000,seed:5)
        let repeated=try RangeEquityEngine.calculate(hole:c("9s 8s"),ranges:[.balancedRaise,.caller],samples:4000,seed:5)
        XCTAssertEqual(first,repeated); XCTAssertEqual(first.samples,4000)
        XCTAssertEqual(first.samplingBound,sqrt(log(40)/8000),accuracy:1e-12)
        let split=try RangeEquityEngine.calculate(hole:c("2c 3d"),board:c("As Ks Qs Js Ts"),ranges:[.tightReraise,.tightReraise],samples:1000,seed:9)
        XCTAssertEqual(split.equity,1.0/3,accuracy:1e-12); XCTAssertEqual(split.outcomes?.tie,1)
    }
    func testDefaultOneHundredThousandDealsAndRangeOrderAgreement() throws {
        let hole=c("Qs Qh"), ranges:[OpponentRange]=[.balancedRaise,.caller,.caller]
        let r=try RangeEquityEngine.calculate(hole:hole,ranges:ranges,seed:88)
        XCTAssertEqual(r.samples,100000); XCTAssertEqual(r.outcomes!.win+r.outcomes!.tie+r.outcomes!.lose,1,accuracy:1e-12)
        let reversed=try RangeEquityEngine.calculate(hole:hole,ranges:Array(ranges.reversed()),seed:89)
        XCTAssertLessThanOrEqual(abs(r.equity-reversed.equity),r.samplingBound+reversed.samplingBound)
        let nine=try RangeEquityEngine.calculate(hole:hole,ranges:[.balancedRaise]+Array(repeating:.caller,count:7),samples:2000,seed:90)
        XCTAssertEqual(nine.samples,2000)
    }
    func testRangesChangeEquityAndRejectBadOrImpossibleInputs() throws {
        let hole=c("Ts Th")
        let random=try RangeEquityEngine.calculate(hole:hole,ranges:[.random],samples:20000,seed:17)
        let tight=try RangeEquityEngine.calculate(hole:hole,ranges:[.tightReraise],samples:20000,seed:17)
        XCTAssertGreaterThan(random.equity-tight.equity,0.2)
        XCTAssertThrowsError(try RangeEquityEngine.calculate(hole:c("Ah Ah"),ranges:[.caller]))
        XCTAssertThrowsError(try RangeEquityEngine.calculate(hole:hole,ranges:[]))
        XCTAssertThrowsError(try RangeEquityEngine.calculate(hole:hole,ranges:[.caller],samples:0))
        XCTAssertThrowsError(try RangeEquityEngine.calculate(hole:hole,ranges:[.caller],cancelled:{ true }))
        XCTAssertThrowsError(try RangeEquityEngine.calculate(hole:c("Kh Kc"),board:c("Ah Ad Ac As Kd"),ranges:[.tightReraise]))
    }
}
