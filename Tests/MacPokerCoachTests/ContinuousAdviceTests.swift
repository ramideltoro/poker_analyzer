import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class ContinuousAdviceTests: XCTestCase {
    func table(players: Int = 6,call: Int = 100) -> TableObservation {
        TableObservation(potCents:300,callCents:call,seats:(1..<players).map { i in
            TableSeat(id:i,bounds:UnitRect(x:Double(i)*0.08,y:0.3,width:0.07,height:0.05),isHero:false,stackCents:3000,betCents:i == 1 ? call : 0,activity:.active)
        }+[TableSeat(id:players,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:3000,betCents:0,activity:.active)],
        controls:TableControls(canFold:true,canCheck:call == 0,canCall:call > 0,canRaise:true,raiseToCents:200))
    }
    func testUnknownPreflopContextDoesNotTurnRandomHandPriceIntoStrategicFold() throws {
        for high in 2...14 { for low in 2...high {
            for suited in [false,true] where !suited || high != low {
                let hole=[Card(rank:high,suit:.spades),Card(rank:low,suit:suited ? .spades : .diamonds)]
                let result=EquityResult(equity:0.1,samplingBound:0.001,samples:1000000,exact:false)
                let estimate=try CallEstimate(equity:result,potBeforeCall:3,call:1)
                let advice=ActionAdvice.recommend(hole:hole,board:[],result:result,estimate:estimate,call:1,table:table())
                if high==low && high>=13 { XCTAssertEqual(advice.kind,.raise) }
                else { XCTAssertNil(advice.kind); XCTAssertEqual(advice.state,.preflop) }
                XCTAssertFalse(advice.reason.isEmpty)
            }
        } }
    }
    @MainActor func testEightyHandsResumeAdviceAfterFoldsBoardsMissingButtonsAndCaptureGaps() async throws {
        let analysis = HandAnalysisModel(calculate:{ hole,_,_,_ in
            let q = [0.2,0.25,0.7][hole[0].rank%3]
            return EquityResult(equity:q,samplingBound:0.01,samples:100000,exact:false)
        })
        let app = AppModel(log:.disabled,analysis:analysis), helper = HandAnalysisTests()
        let deck = Suit.allCases.flatMap { suit in (2...14).map { Card(rank:$0,suit:suit) } }
        var decisions = 0, foldedReviews = 0
        for n in 0..<80 {
            let hole = [deck[n%52],deck[(n+17)%52]], hand = helper.hand(hole.map(\.code),board:Array(deck.filter { !hole.contains($0) }.suffix(3)).map(\.code)), t = table(players:n%2 == 0 ? 6 : 9)
            let scan = CardScan(cards:hand.hole+hand.board,table:t)
            app.acceptScan(scan)
            XCTAssertNil(analysis.actionAdvice.kind,"A new pair cannot use the previous hand’s action")
            app.acceptScan(scan); app.acceptScan(scan)
            try await helper.waitForResult(analysis)
            XCTAssertNotNil(analysis.actionAdvice.kind,"Hand \(n): \(analysis.actionAdvice.reason)")
            XCTAssertFalse(analysis.actionAdvice.reason.isEmpty); decisions += 1
            if n%8 == 0 {
                var hidden = t; hidden.callCents = nil; hidden.controls = TableControls()
                for _ in 0..<2 { app.acceptScan(CardScan(cards:hand.hole+hand.board,table:hidden)) }
                XCTAssertNil(analysis.actionAdvice.kind)
                XCTAssertEqual(analysis.actionAdvice.state,.controls)
                for _ in 0..<3 { app.acceptScan(scan) }
                try await helper.waitForResult(analysis)
                XCTAssertNotNil(analysis.actionAdvice.kind)
            }
            var folded = t; folded.seats[folded.seats.count-1].activity = .folded
            folded.callCents = nil; folded.controls = TableControls()
            let last=analysis.presentedAdvice
            for _ in 0..<2 { app.acceptScan(CardScan(cards:hand.board,table:folded)) }
            XCTAssertNil(analysis.actionAdvice.kind); XCTAssertEqual(analysis.actionAdvice.state,.savedHand)
            XCTAssertEqual(analysis.presentedAdvice,last)
            foldedReviews += 1
            let board = hand.board.map(\.card)
            let review = helper.hand(hole.map(\.code),board:board.map(\.code))
            for _ in 0..<2 { app.acceptScan(CardScan(cards:review.board,table:folded)) }
            XCTAssertNil(analysis.actionAdvice.kind)
            for _ in 0..<2 { app.acceptScan(CardScan(cards:[],table:folded)) }
            if n%10 == 0 { app.clear("Synthetic capture gap"); XCTAssertNil(analysis.actionAdvice.kind) }
        }
        XCTAssertEqual(decisions,80); XCTAssertEqual(foldedReviews,80)
        app.clear("Stopped"); XCTAssertEqual(analysis.actionAdvice.state,.cards)
    }
    @MainActor func testFreeCheckDoesNotWaitForSimulationStacksPotOrRaiseSlider() async throws {
        let analysis = HandAnalysisModel(calculate:{ _,_,_,_ in
            Thread.sleep(forTimeInterval:0.15)
            return EquityResult(equity:0.2,samplingBound:0.01,samples:100000,exact:false)
        })
        let hand = HandAnalysisTests().hand(["7s","2d"])
        var t = table(call:0); t.seats[0].stackCents = nil
        analysis.update(hand,table:t); analysis.update(hand,table:t)
        XCTAssertTrue(analysis.calculating); XCTAssertNil(analysis.callEstimate)
        XCTAssertEqual(analysis.actionAdvice.kind,.check)
        for n in 1...6 {
            t.potCents = n*100; t.controls?.raiseToCents = n*37; t.seats[1].stackCents = n*113
            analysis.update(hand,table:t)
            XCTAssertFalse(analysis.tableConfirmed)
            XCTAssertTrue(analysis.actionControlsConfirmed); XCTAssertEqual(analysis.actionAdvice.kind,.check)
        }
        t.callCents = 100; t.controls?.canCall = true; t.controls?.canCheck = false
        analysis.update(hand,table:t)
        XCTAssertNil(analysis.actionAdvice.kind,"A changed price must clear the free-check suggestion immediately")
        t = table(call:0); t.seats[t.seats.count-1].stackCents = 0
        analysis.update(hand,table:t); analysis.update(hand,table:t)
        XCTAssertNil(analysis.actionAdvice.kind,"An all-in hero has no further action")
        analysis.reset()
    }
    @MainActor func testTransientCalculationFailureRetriesWithoutNewCards() async throws {
        final class Attempts: @unchecked Sendable {
            let lock = NSLock(); var value = 0
            func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        }
        let attempts = Attempts()
        let model = HandAnalysisModel(calculate:{ _,_,_,_ in
            if attempts.next() == 1 { throw EquityError.cancelled }
            return EquityResult(equity:0.7,samplingBound:0.01,samples:100000,exact:false)
        })
        let helper = HandAnalysisTests(), hand = helper.hand(["7s","2d"],board:["2c","8h","Qd"]), t = table()
        model.update(hand,table:t); model.update(hand,table:t)
        for _ in 0..<100 { if model.error != nil { break }; try await Task.sleep(nanoseconds:5_000_000) }
        XCTAssertEqual(model.actionAdvice.state,.calculationFailed)
        XCTAssertTrue(model.actionAdvice.reason.contains("Retrying automatically"))
        try await Task.sleep(nanoseconds:300_000_000)
        model.update(hand,table:t); try await helper.waitForResult(model)
        XCTAssertEqual(model.actionAdvice.kind,.call)
        XCTAssertEqual(attempts.value,2)
        model.reset(); XCTAssertNil(model.actionAdvice.kind)
    }
}
