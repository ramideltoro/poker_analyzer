import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach
@MainActor final class AlwaysMoveTests: XCTestCase {
    func model() -> HandAnalysisModel {
        HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.5,samplingBound:0.01,samples:1000,exact:false) },calculateResponse:{ _,_,_ in EquityResult(equity:0.5,samplingBound:0.01,samples:1000,exact:false) })
    }
    func testAllStartingClassesProduceMoveWithoutPositionMoneyOrManualContext() {
        for h in 2...14 { for l in 2...h { for suited in [false,true] where !suited || h != l {
            let hole=[Card(rank:h,suit:.spades),Card(rank:l,suit:suited ? .spades : .diamonds)]
            let a=DefaultDecision.make(hole:hole,board:[],table:nil,confirmedControls:false,context:PreflopContext(),evidence:PreflopEvidence())
            XCTAssertNotNil(a?.kind); XCTAssertTrue(a?.provisional == true)
            XCTAssertEqual(a?.title,a?.kind?.rawValue.uppercased()); XCTAssertFalse(a!.reason.isEmpty)
        } } }
    }
    func testConfirmedCardsImmediatelyReplaceContextStatusWithDefaultMove() {
        let m=model(), helper=HandAnalysisTests(), h=helper.hand(["9s","8s"])
        m.update(h)
        XCTAssertNil(m.presentedAdvice.kind,"Strict analysis can still report missing input independently")
        XCTAssertEqual(m.decisionAdvice.kind,.raise); XCTAssertTrue(m.decisionAdvice.provisional)
        XCTAssertNil(m.callEstimate); XCTAssertNil(m.result)
        XCTAssertFalse(m.decisionAdvice.reason.contains("Waiting"))
        m.position = .early; XCTAssertEqual(m.decisionAdvice.kind,.fold)
        m.position = .cutoff; XCTAssertEqual(m.decisionAdvice.kind,.raise)
        m.reset(); XCTAssertNil(m.decisionAdvice.kind)
    }
    func testFreeCheckAndLegalControlsPreventInvalidFoldCallOrRaise() {
        let t=ContinuousAdviceTests().table(players:3,call:0), weak=[Card("7s")!,Card("2d")!], premium=[Card("Ks")!,Card("Kd")!]
        var free=t; free.controls=TableControls(canCheck:true,canBet:true)
        let a=DefaultDecision.make(hole:weak,board:[],table:free,confirmedControls:true,context:PreflopContext(),evidence:PreflopEvidence())
        XCTAssertEqual(a?.kind,.check)
        var paid=t; paid.callCents=100; paid.controls=TableControls(canCall:true,canRaise:false)
        XCTAssertEqual(DefaultDecision.make(hole:premium,board:[],table:paid,confirmedControls:true,context:PreflopContext(),evidence:PreflopEvidence())?.kind,.call)
        XCTAssertEqual(DefaultDecision.make(hole:weak,board:[],table:paid,confirmedControls:true,context:PreflopContext(),evidence:PreflopEvidence(heroCalled:true))?.kind,.fold,"A paid Call implies the legal option to fold even if its label was missed")
    }
    func testMissingAmountsSidePotsAndRunningCalculationsNeverBlankTheMove() {
        let m=model(), h=HandAnalysisTests().hand(["9s","6h"],board:["9d","6c","Ah"])
        for mode in 0..<6 {
            var t=DynamicDecisionTests().table()
            switch mode { case 0:t.potCents=nil; case 1:t.seats[0].stackCents=nil; case 2:t.sidePots=true; case 3:t.controls=nil; t.callCents=nil; case 4:t.seats[0].activity = .unknown; default:t.callCents=100; t.controls=TableControls(canFold:true,canCall:true) }
            m.update(h,table:t); m.update(h,table:t)
            XCTAssertNotNil(m.decisionAdvice.kind,"mode \(mode)")
            XCTAssertNotEqual(m.decisionAdvice.title,"WAIT"); XCTAssertNotEqual(m.decisionAdvice.title,"REVIEW")
            if mode<5 { XCTAssertNil(m.callEstimate,"A default move must not invent dollar EV") }
        }
        m.reset()
    }
    func testPartialBoardDoesNotBecomePreflopPremiumRaiseOrLoseTypedPlan() {
        let m=model(), h=HandAnalysisTests().hand(["Ks","Kd"])
        let reading=CardReadiness(faces:4,confirmedHole:h.hole,message:"Partial board",received:true)
        var t=DynamicDecisionTests().table(); t.controls=nil; t.callCents=nil
        m.update(nil,table:t,recognition:reading)
        XCTAssertNotNil(m.decisionAdvice.kind); XCTAssertNotEqual(m.decisionAdvice.kind,.raise)
        XCTAssertTrue(m.decisionAdvice.provisional); XCTAssertNil(m.callEstimate)
        m.reset()
    }
    func testFoldKeepsExactlyTheLastDisplayedMoveAndNewCardsRemoveIt() {
        let m=model(), helper=HandAnalysisTests(), h=helper.hand(["9s","8s"])
        m.update(h); let last=m.decisionAdvice
        XCTAssertEqual(last.kind,.raise)
        var review=h; review.isReview=true
        m.update(review)
        XCTAssertEqual(m.decisionAdvice,last); XCTAssertTrue(m.decisionIsHistory)
        m.update(nil); XCTAssertEqual(m.decisionAdvice,last)
        m.update(helper.hand(["7s","2d"]))
        XCTAssertEqual(m.decisionAdvice.kind,.fold); XCTAssertFalse(m.decisionIsHistory)
        m.reset(); XCTAssertNil(m.display.lastShownAdvice); XCTAssertNil(m.decisionAdvice.kind)
    }
    func testAllInHasNoInventedNewBettingActionAndKeepsRecordedPlan() {
        let m=model(), h=HandAnalysisTests().hand(["Ks","Kd"])
        m.update(h); let prior=m.decisionAdvice
        var t=DynamicDecisionTests().table(); t.seats[3].stackCents=0
        m.update(h,table:t)
        XCTAssertTrue(m.decisionIsHistory); XCTAssertEqual(m.decisionAdvice,prior)
        m.reset(); m.update(h,table:t)
        XCTAssertNil(m.decisionAdvice.kind,"An already all-in hero with no recorded move has no legal decision")
        m.reset(); let weak=HandAnalysisTests().hand(["7s","2d"],board:["Ah","Qc","9c"])
        m.update(weak,table:t); m.update(weak,table:t)
        XCTAssertNil(m.decisionAdvice.kind,"A conditional free-check forecast must not become an action for an all-in hero")
        m.reset()
    }
    func testSingleFreshPaidControlsRestrictConditionalPremiumPlan() {
        let m=model(), h=HandAnalysisTests().hand(["Ks","Kd"])
        var t=DynamicDecisionTests().table(call:100); t.controls=TableControls(canCall:true)
        m.update(h,table:t)
        XCTAssertFalse(m.actionControlsConfirmed)
        XCTAssertEqual(m.decisionAdvice.kind,.call); XCTAssertTrue(m.decisionAdvice.provisional)
        m.reset()
    }
}

extension AlwaysMoveTests {
    func testEveryBaselineActionFitsFreshReadableControlsAcrossStartingClasses() {
        for h in 2...14 { for l in 2...h {
            let hole=[Card(rank:h,suit:.spades),Card(rank:l,suit:.diamonds)]
            for mode in 0..<3 {
                var table=DynamicDecisionTests().table(call:mode==0 ? 0 : 100)
                table.controls=mode==0 ? TableControls(canCheck:true,canBet:true) : TableControls(canCall:true,canRaise:mode==2)
                let allowed=DefaultDecision.available(table,confirmed:true)!
                let plan=DefaultDecision.make(hole:hole,board:[],table:table,confirmedControls:false,context:PreflopContext(),evidence:PreflopEvidence(heroCalled:mode>0))!
                XCTAssertTrue(allowed.contains(plan.kind!),"\(h),\(l), mode \(mode)")
            }
        } }
    }
    func testDetailedSupportedRecommendationTakesPriorityOverDefaults() async throws {
        let m=model(), h=HandAnalysisTests().hand(["9s","6h"],board:["9d","6c","Ah"])
        let t=DynamicDecisionTests().table()
        m.update(h,table:t); m.update(h,table:t)
        try await HandAnalysisTests().waitForResult(m)
        XCTAssertEqual(m.actionAdvice.kind,.bet); XCTAssertEqual(m.decisionAdvice,m.presentedAdvice)
        XCTAssertFalse(m.decisionAdvice.provisional)
        m.reset()
    }
    func testMissingReadingGapKeepsHistoryAndNeverRecordsDefaultAsActualAction() {
        let m=model(), h=HandAnalysisTests().hand(["9s","8s"])
        m.update(h)
        XCTAssertNotNil(m.decisionAdvice.kind); XCTAssertNil(m.actionAdvice.kind); XCTAssertNil(m.display.lastAdvice)
        let last=m.decisionAdvice
        m.update(nil,recognition:CardReadiness(faces:0,message:"No glyphs",received:true))
        XCTAssertEqual(m.decisionAdvice,last); XCTAssertTrue(m.decisionIsHistory); XCTAssertNil(m.actionAdvice.kind)
        m.reset()
    }
    func testKnownFoldedHeroKeepsPreviousMoveAsHistory() {
        let m=model(), h=HandAnalysisTests().hand(["9s","8s"])
        m.update(h); let prior=m.decisionAdvice
        var t=DynamicDecisionTests().table(); t.seats[3].activity = .folded
        m.update(h,table:t)
        XCTAssertEqual(m.decisionAdvice,prior); XCTAssertTrue(m.decisionIsHistory)
        m.reset()
    }
}
