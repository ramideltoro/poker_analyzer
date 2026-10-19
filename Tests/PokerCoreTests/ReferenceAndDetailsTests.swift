import XCTest
import PokerCore

final class ReferenceAndDetailsTests: XCTestCase {
    func cards(_ text: String) -> [Card] { text.split(separator:" ").map { Card(String($0))! } }
    func testLookupEvaluatorAgreesWithIndependentOracleAndOrdering() {
        let deck = (2...14).flatMap { r in Suit.allCases.map { Card(rank:r,suit:$0) } }
        var state: UInt64 = 29343
        func draw(_ count: Int) -> [Card] {
            var pool = deck
            for i in 0..<count { state = state &* 6364136223846793005 &+ 1; pool.swapAt(i,i+Int((state>>16)%UInt64(52-i))) }
            return Array(pool.prefix(count))
        }
        for count in 5...7 { for _ in 0..<10_000 {
            let a = draw(count), b = draw(count)
            let actual = Evaluator.evaluate(a), expected = Evaluator.referenceEvaluate(a)
            XCTAssertEqual(actual.category,expected.category)
            XCTAssertEqual(actual < Evaluator.evaluate(b),expected < Evaluator.referenceEvaluate(b))
            XCTAssertEqual(actual == Evaluator.evaluate(b),expected == Evaluator.referenceEvaluate(b))
        } }
    }
    func testExactImprovementCountsFlushAndRiver() {
        let hole = cards("Ah Kh"), board = cards("2h 7h 9c Js")
        let details = RunoutDetails(hole:hole,board:board)!
        XCTAssertEqual(details.runouts,46)
        let independent = (2...14).flatMap { r in Suit.allCases.map { Card(rank:r,suit:$0) } }.filter { !(hole+board).contains($0) }
            .filter { Evaluator.referenceEvaluate(hole+board+[$0]).category > Evaluator.referenceEvaluate(hole+board).category }
        XCTAssertEqual(Set(details.improvingCards),Set(independent))
        XCTAssertEqual(details.nextCardImprovement,details.riverImprovement)
        XCTAssertEqual(RunoutDetails(hole:hole,board:cards("2h 7h 9c"))?.runouts,1081)
        XCTAssertNil(RunoutDetails(hole:hole,board:cards("Ah 7h 9c")))
        XCTAssertNil(RunoutDetails(hole:hole,board:cards("2h 7h 9c Js Qd"))?.riverImprovement)
    }
    func testCanonicalClassesAndBoardTexture() {
        XCTAssertEqual(HandDetails.startingClass(cards("Kh Ah")),"AKs")
        XCTAssertEqual(HandDetails.startingClass(cards("Kh Ad")),"AKo")
        XCTAssertEqual(HandDetails.startingClass(cards("Kh Kd")),"KK")
        XCTAssertTrue(HandDetails.texture(cards("Ah Ad 2h")).contains("Paired board"))
        XCTAssertTrue(HandDetails.texture(cards("Ah Ad Ac As 2h")).contains("Four of a kind"))
        XCTAssertTrue(HandDetails.texture(cards("Ah Ad Ac 2s 2h")).contains("Full house"))
    }
    func testBundledReferenceSummaryIsCompleteAndValidated() throws {
        let data = try XCTUnwrap(ReferenceData.shared)
        XCTAssertEqual(data.uciRows,1_025_010); XCTAssertEqual(data.uciMismatches,0)
        XCTAssertEqual(data.rawHandHQ,21_606_087)
        XCTAssertGreaterThan(data.sources["HandHQ 2009"] ?? 0,21_600_000)
        XCTAssertLessThan(data.sources["HandHQ 2009"] ?? Int.max,21_605_687)
        XCTAssertGreaterThan(data.quarantinedRecords,0)
        XCTAssertEqual(data.sources["Pluribus"],10_000)
        XCTAssertEqual(data.duplicateHandHQIDs,400)
        XCTAssertEqual(data.classes.count,169)
        for sample in data.classes.values {
            XCTAssertGreaterThanOrEqual(sample.known,sample.river)
            XCTAssertEqual(sample.categories.count,9)
            XCTAssertEqual(sample.categories.reduce(0,+),sample.river)
        }
    }
}

extension ReferenceAndDetailsTests {
    func testBestFiveSelectsTheMadeHandAndRejectsIncompleteOrDuplicateCards() {
        let all = cards("Ah Kh Qh Jh Th 2c 3d")
        let best = HandDetails.bestFive(all)
        XCTAssertEqual(Set(best),Set(cards("Ah Kh Qh Jh Th")))
        XCTAssertEqual(Evaluator.evaluate(best),Evaluator.evaluate(all))
        XCTAssertTrue(HandDetails.bestFive(cards("Ah Kh")).isEmpty)
        XCTAssertTrue(HandDetails.bestFive(cards("Ah Ah Qh Jh Th")).isEmpty)
        let boardOnly = cards("2c 3d As Ks Qs Js Ts")
        XCTAssertEqual(Set(HandDetails.bestFive(boardOnly)),Set(cards("As Ks Qs Js Ts")))
    }
}
