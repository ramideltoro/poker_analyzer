import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach
final class PositionAndSavedAdviceTests: XCTestCase {
    func table() -> TableObservation {
        var t=ContinuousAdviceTests().table(players:4)
        t.potCents=150; t.callCents=100
        for i in t.seats.indices { t.seats[i].stackCents=10000; t.seats[i].betCents=i==0 ? 100 : i==1 ? 50 : 0 }
        t.controls=TableControls(canFold:true,canCall:true,canRaise:true,raiseToCents:200)
        return t
    }
    func testUnopenedCutoffNinetyEightSuitedRaisesButEarlyPositionRuleDiffers() {
        let hole=["9s","8s"].compactMap(Card.init), t=table()
        var context=PreflopContext(position:.cutoff,situation:.firstIn,bigBlindCents:100)
        let raise=context.suggestion(hole:hole,table:t)
        XCTAssertEqual(raise?.kind,.raise); XCTAssertTrue(raise?.reason.contains("folded to you") == true)
        XCTAssertFalse(raise?.reason.contains("$2.00") == true,"No guessed open size")
        context.position = .early; XCTAssertEqual(context.suggestion(hole:hole,table:t)?.kind,.fold)
        context.position = .button; XCTAssertEqual(context.suggestion(hole:hole,table:t)?.kind,.raise)
    }
    func testOpeningRuleDoesNotExtendToUnknownRaisedLimpedShortOrContradictoryPots() {
        let hole=["9s","8s"].compactMap(Card.init), context=PreflopContext(position:.cutoff,situation:.firstIn,bigBlindCents:100)
        for mode in 0..<9 {
            var c=context, t=table()
            switch mode {
            case 0: c.position = .unknown
            case 1: c.situation = .limped
            case 2: c.situation = .raised
            case 3: c.bigBlindCents = nil
            case 4: t.seats[0].stackCents=2000
            case 5: t.potCents=450
            case 6: t.seats[0].betCents=300
            case 7: t.controls?.canRaise=false
            default: t.sidePots=true
            }
            XCTAssertNil(c.suggestion(hole:hole,table:t),"mode \(mode)")
        }
    }
    @MainActor func testPositionChangesPreflopPolicyWithoutChangingRawEquityAndResetsPerHand() async throws {
        let model=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.001,samples:1000000,exact:false) }), helper=HandAnalysisTests()
        let hand=helper.hand(["9s","8s"]), t=table()
        model.update(hand,table:t); model.update(hand,table:t); try await helper.waitForResult(model)
        XCTAssertLessThan(model.callEstimate!.value,0); XCTAssertNil(model.actionAdvice.kind)
        model.position = .cutoff; model.preflopSituation = .firstIn; model.bigBlindText="1.00"
        XCTAssertEqual(model.actionAdvice.kind,.raise); XCTAssertEqual(model.result?.equity,0.1)
        var changed=t; changed.seats[0].stackCents=9900
        model.update(hand,table:changed); XCTAssertNil(model.actionAdvice.kind,"A changed stack needs a fresh full-table confirmation for the opening rule")
        model.update(hand,table:changed); XCTAssertEqual(model.actionAdvice.kind,.raise)
        model.position = .early; XCTAssertEqual(model.actionAdvice.kind,.fold)
        model.update(helper.hand(["Ah","Kd"]),table:t)
        XCTAssertEqual(model.position,.unknown); XCTAssertEqual(model.preflopSituation,.unknown)
        XCTAssertEqual(model.bigBlindText,"1.00"); XCTAssertNil(model.display.lastAdvice)
        model.reset(); XCTAssertEqual(model.bigBlindText,"")
    }
    @MainActor func testFoldPreservesActionReasonAndBasisAcrossMissingCardsAndLaterBoards() async throws {
        let model=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.001,samples:1000000,exact:false) }), helper=HandAnalysisTests()
        let hand=helper.hand(["9s","8s"]); var t=table()
        model.update(hand,table:t); model.update(hand,table:t); try await helper.waitForResult(model)
        model.position = .cutoff; model.preflopSituation = .firstIn; model.bigBlindText="1.00"
        let last=model.presentedAdvice; XCTAssertEqual(last.kind,.raise)
        t.seats[t.seats.count-1].activity = .folded; t.callCents=nil; t.controls=TableControls()
        model.update(nil,table:t)
        XCTAssertEqual(model.presentedAdvice,last); XCTAssertTrue(model.showsLastAdvice); XCTAssertNil(model.actionAdvice.kind)
        var review=hand; review.isReview=true
        model.update(review,table:t); model.update(review,table:t)
        XCTAssertEqual(model.presentedAdvice,last)
        review=helper.hand(["9s","8s"],board:["2c","7s","Jd"]); review.isReview=true
        model.update(review,table:t); model.update(review,table:t); try await helper.waitForResult(model)
        XCTAssertEqual(model.presentedAdvice,last); XCTAssertNil(model.callEstimate)
        XCTAssertNil(model.actionAdvice.kind,"A saved action must never become a live recommendation")
        model.reset(); XCTAssertNil(model.display.lastAdvice); XCTAssertFalse(model.showsLastAdvice)
    }
    @MainActor func testSameHandStreetChangeRetainsLastSuggestionUntilAFreshOneExists() async throws {
        let model=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.8,samplingBound:0.001,samples:1000000,exact:false) }), helper=HandAnalysisTests()
        let h=helper.hand(["Ks","Kd"]); var t=table()
        model.update(h,table:t); model.update(h,table:t)
        let last=model.presentedAdvice; XCTAssertEqual(last.kind,.raise)
        t.callCents=nil; t.controls=TableControls()
        model.update(helper.hand(["Ks","Kd"],board:["2c","7s","Jd"]),table:t)
        XCTAssertEqual(model.display.lastAdvice,last)
        model.update(nil,table:t); XCTAssertEqual(model.presentedAdvice,last)
        let next=helper.hand(["Ah","Qd"])
        model.update(next,table:t); XCTAssertNil(model.display.lastAdvice)
    }
}
