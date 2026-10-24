import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach
@MainActor final class PreflopRaiseResponseTests: XCTestCase {
    func table(call:Int=100) -> TableObservation {
        var t=ContinuousAdviceTests().table(players:3,call:call)
        t.potCents=400+call; t.seats[0].betCents=100+call; t.seats[1].betCents=0
        t.seats[2].betCents=100; t.seats[2].stackCents=3000
        return t
    }
    func model(q:Double=0.5) -> HandAnalysisModel {
        HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.01,samples:1000,exact:false) },calculateResponse:{ _,_,_ in EquityResult(equity:q,samplingBound:0.005,samples:100000,exact:false) })
    }
    func settle(_ m:HandAnalysisModel) async throws {
        for _ in 0..<200 { if m.raiseResponseResult != nil { return }; try await Task.sleep(nanoseconds:5_000_000) }
        XCTFail("No range response")
    }
    func testAfterTrackedCallUsesRaisedPriceWithoutManualPositionOrBigBlind() async throws {
        let m=model(), h=HandAnalysisTests().hand(["Ts","Th"]), t=table(), e=PreflopEvidence(heroCalled:true)
        m.update(h,table:t,preflop:e); m.update(h,table:t,preflop:e); try await settle(m)
        XCTAssertEqual(m.position,.unknown); XCTAssertEqual(m.bigBlindText,"")
        XCTAssertEqual(m.actionAdvice.kind,.call); XCTAssertEqual(m.actionAdvice.basis,"RAISE RESPONSE")
        XCTAssertTrue(m.actionAdvice.reason.contains("After your tracked call"))
        XCTAssertTrue(m.actionAdvice.reason.contains("Earlier chips are sunk")); XCTAssertEqual(m.display.decisionEquity,0.5)
        m.reset()
    }
    func testStaleFirstInContextDoesNotBlockRaiseResponseAndPriceChangesReuseMath() async throws {
        let m=model(q:0.28), h=HandAnalysisTests().hand(["9s","8s"]), e=PreflopEvidence(heroCalled:true)
        m.update(h,table:table(),preflop:e); m.update(h,table:table(),preflop:e)
        m.position = .cutoff; m.preflopSituation = .firstIn; m.bigBlindText="1.00"
        try await settle(m); XCTAssertEqual(m.actionAdvice.kind,.call)
        m.update(h,table:table(call:500),preflop:e); XCTAssertNil(m.actionAdvice.kind)
        m.update(h,table:table(call:500),preflop:e)
        XCTAssertEqual(m.actionAdvice.kind,.fold); XCTAssertNotNil(m.raiseResponseResult,"Same cards / range reuse the completed calculation")
        m.reset()
    }
    func testVisibleRaiseInferenceAndManualRaiseWorkWithoutObservedCallButBlindsDoNot() async throws {
        var t=table(call:250); let h=HandAnalysisTests().hand(["Qs","Qh"])
        XCTAssertTrue(RaiseResponseRequest.detectsRaise(t,context:PreflopContext(),evidence:PreflopEvidence()))
        t=table(call:100)
        XCTAssertFalse(RaiseResponseRequest.detectsRaise(t,context:PreflopContext(),evidence:PreflopEvidence()))
        let m=model(); m.update(h,table:t); m.update(h,table:t)
        m.preflopSituation = .raised; try await settle(m)
        XCTAssertEqual(m.actionAdvice.kind,.call); XCTAssertTrue(m.actionAdvice.reason.contains("User-confirmed raise"))
        t.seats[2].betCents=nil
        m.update(h,table:t); m.update(h,table:t)
        XCTAssertEqual(m.actionAdvice.state,.amounts); XCTAssertNil(m.actionAdvice.kind)
        m.reset()
    }
    func testReraisePresetAndAllInRealizationAreSeparateFromSmallEffectiveStacks() throws {
        var t=table(); let h=[Card("Ts")!,Card("Th")!]
        let e=PreflopEvidence(heroCalled:true,heroRaised:true,opponentRaises:2)
        let r=try XCTUnwrap(RaiseResponseRequest.make(hole:h,table:t,context:PreflopContext(),evidence:e,preset:.tight))
        XCTAssertEqual(r.key.ranges.first,.tightReraise)
        t.seats[0].stackCents=50; t.seats[1].stackCents=500
        let small=try XCTUnwrap(RaiseResponseRequest.make(hole:h,table:t,context:PreflopContext(),evidence:e,preset:.balanced))
        XCTAssertFalse(small.callClosesBetting,"A remaining small stack can still bet")
        t.seats[2].stackCents=100
        let allin=try XCTUnwrap(RaiseResponseRequest.make(hole:h,table:t,context:PreflopContext(),evidence:e,preset:.balanced))
        XCTAssertTrue(allin.callClosesBetting)
        let q=EquityResult(equity:0.18,samplingBound:0,samples:100000,exact:false)
        XCTAssertEqual(small.advice(result:q,position:.unknown).kind,.fold)
        XCTAssertEqual(allin.advice(result:q,position:.unknown).kind,.call)
    }
    func testUnknownMoneyAndSidePotsDoNotProducePricedActionsOrGenericContextPrompt() async throws {
        let m=model(), h=HandAnalysisTests().hand(), e=PreflopEvidence(heroCalled:true)
        for mode in 0..<5 {
            var t=table()
            switch mode { case 0:t.seats[0].stackCents=nil; case 1:t.sidePots=true; case 2:t.callCents=101; case 3:t.potCents=100; default:t.seats[2].betCents=nil }
            m.update(h,table:t,preflop:e); m.update(h,table:t,preflop:e)
            XCTAssertNil(m.actionAdvice.kind); XCTAssertEqual(m.actionAdvice.state,.amounts)
            XCTAssertFalse(m.actionAdvice.reason.contains("Opening rule"))
        }
        m.reset()
    }
    func testOldResponseCannotOverwriteNewHandOrFoldedHandAndPreservesLastSuggestion() async throws {
        let m=model(), h=HandAnalysisTests().hand(["Ts","Th"]), e=PreflopEvidence(heroCalled:true)
        m.update(h,table:table(),preflop:e); m.update(h,table:table(),preflop:e); try await settle(m)
        let old=m.presentedAdvice
        var review=h; review.isReview=true; var t=table(); t.seats[2].activity = .folded; t.callCents=nil; t.controls=nil
        m.update(review,table:t)
        XCTAssertNil(m.raiseResponseResult); XCTAssertEqual(m.presentedAdvice,old)
        m.update(HandAnalysisTests().hand(["7s","2d"]),table:table())
        XCTAssertNil(m.raiseResponseResult); XCTAssertFalse(m.preflopEvidence.heroCalled); XCTAssertNil(m.display.lastAdvice)
        m.reset()
    }
    func testLateCancelledCalculationCannotRestoreAdviceAfterDifferentCardsOrStop() async throws {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.4,samplingBound:0.01,samples:1000,exact:false) },calculateResponse:{ hole,_,_ in
            if hole.contains(Card("Ts")!) { Thread.sleep(forTimeInterval:0.1) }
            return EquityResult(equity:hole.contains(Card("Ts")!) ? 0.9 : 0.1,samplingBound:0.01,samples:100000,exact:false)
        })
        let e=PreflopEvidence(heroCalled:true), helper=HandAnalysisTests(), old=helper.hand(["Ts","Th"]), fresh=helper.hand(["9s","8s"])
        m.update(old,table:table(),preflop:e); m.update(old,table:table(),preflop:e)
        m.update(fresh,table:table(),preflop:e); m.update(fresh,table:table(),preflop:e); try await settle(m)
        try await Task.sleep(nanoseconds:150_000_000)
        XCTAssertEqual(m.raiseResponseResult?.equity,0.1); XCTAssertEqual(m.actionAdvice.kind,.fold)
        m.update(old,table:table(),preflop:e); m.update(old,table:table(),preflop:e); m.reset()
        try await Task.sleep(nanoseconds:150_000_000)
        XCTAssertNil(m.raiseResponseResult); XCTAssertNil(m.responseKey); XCTAssertEqual(m.actionAdvice.state,.cards)
    }
    func testRangeChoiceChangesAssumptionAndIllegalFoldOrShortSidePotIsSuppressed() async throws {
        let m=model(q:0.05), h=HandAnalysisTests().hand(), e=PreflopEvidence(heroCalled:true)
        var t=table()
        m.update(h,table:t,preflop:e); m.update(h,table:t,preflop:e); try await settle(m)
        XCTAssertEqual(m.actionAdvice.kind,.fold)
        m.raiseRange = .tight; try await settle(m)
        XCTAssertEqual(m.responseKey?.ranges.first,.tightRaise)
        t.controls?.canFold=false; m.update(h,table:t,preflop:e); m.update(h,table:t,preflop:e); try await settle(m)
        XCTAssertNil(m.actionAdvice.kind); XCTAssertEqual(m.actionAdvice.state,.controls)
        t=table(); t.seats[1].stackCents=50
        m.update(h,table:t,preflop:e); m.update(h,table:t,preflop:e)
        XCTAssertNil(m.actionAdvice.kind); XCTAssertEqual(m.actionAdvice.state,.amounts)
        m.reset()
    }
    func testAppTracksCallThenRaiseAndAutomaticallyStartsResponse() async throws {
        let m=model(), app=AppModel(log:.disabled,analysis:m), h=HandAnalysisTests().hand(["Ts","Th"])
        var t=ContinuousAdviceTests().table(players:3,call:100); t.potCents=150; t.seats[1].betCents=50
        func scan(_ t:TableObservation) { for _ in 0..<3 { app.acceptScan(CardScan(cards:h.hole,table:t)) } }
        scan(t)
        t.seats[2].stackCents=2900; t.seats[2].betCents=100; t.seats[2].action = .call
        t.potCents=250; t.callCents=nil; t.controls=nil
        scan(t); XCTAssertTrue(app.tracking.decisionPreflopEvidence.heroCalled)
        t.seats[2].action=nil; t.seats[0].stackCents=2800; t.seats[0].betCents=300; t.seats[0].action = .raise
        t.potCents=450; t.callCents=200; t.controls=TableControls(canFold:true,canCall:true,canRaise:true)
        scan(t); try await settle(m)
        XCTAssertTrue(m.preflopEvidence.heroCalled); XCTAssertEqual(m.actionAdvice.kind,.call)
        XCTAssertEqual(m.actionAdvice.basis,"RAISE RESPONSE"); app.clear("synthetic end")
    }
}
