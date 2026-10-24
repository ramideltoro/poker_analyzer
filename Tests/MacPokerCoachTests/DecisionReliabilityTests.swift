import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class DecisionReliabilityTests:XCTestCase {
    func model() -> HandAnalysisModel { PreflopRaiseResponseTests().model(q:0.43) }
    func blindTable(hero: Int=6,dealer: Int=4,stack:Int=290) -> TableObservation {
        var t=AutomaticPositionTests().table(hero:hero,dealer:dealer,firstIn:false)
        t.bigBlindCents=10;t.potCents=15;t.callCents=0;t.controls=TableControls(canCheck:true,canRaise:true)
        for i in t.seats.indices { t.seats[i].betCents=nil;t.seats[i].stackCents=1000;t.seats[i].activity = .folded }
        t.seats[hero-1].stackCents=stack;t.seats[hero-1].activity = .active
        let bb=(dealer+1)%6+1
        t.seats[bb-1].activity = .active
        return t
    }
    func testVerifiedFreeCheckSurvivesRepeatedUnreadableButtonsWithoutNewFoldOrEV() {
        let m=model(),h=HandAnalysisTests().hand(["As","7d"]);var t=blindTable();t.seats[2].activity = .active;t.potCents=25
        m.update(h,table:t);m.update(h,table:t)
        let prior=m.decisionAdvice;XCTAssertEqual(prior.kind,.check)
        t.controls=nil;t.callCents=nil
        for _ in 0..<8 {
            m.update(h,table:t)
            XCTAssertEqual(m.decisionAdvice.kind,.check);XCTAssertEqual(m.decisionAdvice.reason,prior.reason)
            XCTAssertTrue(m.decisionAdvice.retained);XCTAssertNil(m.actionAdvice.kind);XCTAssertNil(m.callEstimate)
        }
        t.controls=TableControls(canCheck:true,canRaise:true);t.callCents=0
        m.update(h,table:t);XCTAssertTrue(m.decisionAdvice.retained)
        m.update(h,table:t);XCTAssertFalse(m.decisionAdvice.retained);XCTAssertEqual(m.decisionAdvice.kind,.check)
        m.reset();XCTAssertNil(m.display.lastVerifiedTurn)
    }
    func testFreshPaidPriceImmediatelyInvalidatesOldFreeCheckEvenBeforeConfirmation() {
        let m=model(),h=HandAnalysisTests().hand(["As","7d"]);var t=blindTable();t.seats[2].activity = .active;t.potCents=25
        m.update(h,table:t);m.update(h,table:t);XCTAssertEqual(m.decisionAdvice.kind,.check)
        t.callCents=50;t.potCents=65;t.controls=TableControls(canCall:true,canRaise:true)
        m.update(h,table:t)
        XCTAssertFalse(m.decisionAdvice.retained);XCTAssertNotEqual(m.decisionAdvice.kind,.check)
        XCTAssertTrue([SeatAction.fold,.call,.raise].contains(m.decisionAdvice.kind!));m.reset()
    }
    func testNewStreetNewCardsAndCaptureResetNeverReuseAnOldTurnAsCurrent() {
        let m=model(),helper=HandAnalysisTests(),h=helper.hand(["As","7d"]);var t=blindTable();t.seats[2].activity = .active;t.potCents=25
        m.update(h,table:t);m.update(h,table:t)
        t.callCents=nil;t.controls=nil
        m.update(helper.hand(["As","7d"],board:["Ac","4s","Qd"]),table:t)
        XCTAssertFalse(m.decisionAdvice.retained)
        XCTAssertTrue(m.decisionAdvice.reason.contains("If checked") || m.decisionAdvice.reason.contains("if checked"))
        m.update(helper.hand(["Ks","5d"]),table:t)
        XCTAssertFalse(m.decisionAdvice.retained);XCTAssertNil(m.display.lastVerifiedTurn)
        m.reset();XCTAssertNil(m.decisionAdvice.kind)
    }
    func testBigBlindBeforeTurnPlansFreeOptionWithoutClaimingAReadableFreePrice() {
        let m=model(),h=HandAnalysisTests().hand(["As","7d"]);var t=blindTable()
        t.controls=nil;t.callCents=nil;t.potCents=25
        m.update(h,table:t);m.update(h,table:t)
        XCTAssertEqual(m.effectivePosition,.bigBlind);XCTAssertEqual(m.decisionAdvice.kind,.check)
        XCTAssertTrue(m.decisionAdvice.provisional);XCTAssertTrue(m.decisionAdvice.reason.contains("If no raise"))
        XCTAssertNil(m.callEstimate);m.reset()
    }
    func testSmallBlindKFiveOpenAndCutoffSevenSixUseShortCashPolicyAtRealisticDepth() {
        let m=model(),helper=HandAnalysisTests()
        for (hole,dealer,call) in [(["Ks","5d"],5,5),(["7h","6h"],1,10),(["9s","8s"],1,10)] {
            let h=helper.hand(hole);var t=blindTable(dealer:dealer,stack:285)
            // Both blinds/button remain eligible; all seats before hero folded.
            for i in t.seats.indices where dealer != 5 && (t.seats[i].id==dealer || t.seats[i].id==dealer%6+1 || t.seats[i].id==(dealer+1)%6+1) { t.seats[i].activity = .active }
            t.callCents=call;t.controls=TableControls(canFold:true,canCall:true,canRaise:true)
            m.update(h,table:t);m.update(h,table:t)
            XCTAssertEqual(m.effectiveSituation,.firstIn,"\(hole)")
            XCTAssertEqual(m.decisionAdvice.kind,.raise,"\(hole)")
            XCTAssertEqual(m.decisionAdvice.basis,"SHORT CASH OPEN");XCTAssertTrue(m.decisionAdvice.reason.contains("20–49"))
            m.reset()
        }
    }
    func testShortOpeningDoesNotApplyToRaisedLimpedUnsupportedDepthOrSidePots() {
        let hole=[Card("7h")!,Card("6h")!],context=PreflopContext(position:.cutoff,situation:.firstIn,bigBlindCents:10)
        var base=blindTable(dealer:1);base.callCents=10;base.controls=TableControls(canFold:true,canCall:true,canRaise:true)
        for mode in 0..<7 {
            var t=base,c=context
            switch mode {
            case 0:t.seats[5].stackCents=199
            case 1:t.seats[5].stackCents=500
            case 2:c.situation = .limped
            case 3:c.situation = .raised
            case 4:t.potCents=25
            case 5:t.sidePots=true
            default:t.seats[2].stackCents=nil
            }
            XCTAssertNil(ShortCashPolicy.suggestion(hole:hole,table:t,context:c),"\(mode)")
        }
        base.seats[5].stackCents=200
        XCTAssertEqual(ShortCashPolicy.suggestion(hole:hole,table:base,context:context)?.kind,.raise)
    }
    func testConfirmedQuoteStartsBlindDefenseRangeCalculationWithoutInventingWagers() async throws {
        let m=model(),h=HandAnalysisTests().hand(["Js","7c"]);var t=blindTable(dealer:4)
        t.potCents=35;t.callCents=10;t.controls=TableControls(canFold:true,canCall:true,canRaise:true)
        t.seats[2].activity = .active;t.seats[2].action = .raise // CO at dealer/button=4.
        m.update(h,table:t);XCTAssertNil(m.raiseResponseResult)
        m.update(h,table:t);try await PreflopRaiseResponseTests().settle(m)
        XCTAssertEqual(m.actionAdvice.basis,"RAISE RESPONSE");XCTAssertEqual(m.actionAdvice.kind,.call)
        XCTAssertEqual(m.responseKey?.ranges.first,.shortCutoffOpen);XCTAssertTrue(m.responseUsesQuotedPrice)
        XCTAssertTrue(m.actionAdvice.provisional);XCTAssertTrue(m.actionAdvice.reason.contains("Confirmed additional-call"))
        XCTAssertTrue(m.table!.seats.allSatisfy { $0.betCents==nil },"Unknown commitments must remain unknown")
        m.reset()
    }
    func testQuoteScenarioRejectsUnconfirmedCallAllInsMissingStacksAndContradictions() {
        let h=[Card("Js")!,Card("7c")!],c=PreflopContext(position:.bigBlind,bigBlindCents:10)
        var base=blindTable();base.seats[0].activity = .active;base.callCents=10;base.potCents=35;base.controls=TableControls(canCall:true)
        XCTAssertNil(RaiseResponseRequest.make(hole:h,table:base,context:c,evidence:PreflopEvidence(),preset:.balanced))
        XCTAssertNotNil(RaiseResponseRequest.make(hole:h,table:base,context:c,evidence:PreflopEvidence(),preset:.balanced,allowQuotedPrice:true))
        for mode in 0..<10 {
            var t=base,context=c
            switch mode {
            case 0:t.controls=nil
            case 1:t.controls?.canCheck=true
            case 2:t.seats[5].stackCents=10
            case 3:t.seats[0].stackCents=5
            case 4:t.seats[0].stackCents=nil
            case 5:t.sidePots=true
            case 6:t.potCents=5
            case 7:context.bigBlindCents=nil
            case 8:t.seats[5].betCents=0;t.seats[0].betCents=30
            default:t.issue="Conflicting OCR amounts"
            }
            XCTAssertNil(RaiseResponseRequest.make(hole:h,table:t,context:context,evidence:PreflopEvidence(heroCalled:true),preset:.balanced,allowQuotedPrice:true),"\(mode)")
        }
    }
    func testPositionRangeNeverOverridesTightPresetOrAssumesAnUnopenedPotAfterLimp() throws {
        let h=[Card("Js")!,Card("7c")!];var t=blindTable(dealer:4)
        t.seats[2].activity = .active;t.seats[2].action = .raise;t.callCents=10;t.potCents=35;t.controls=TableControls(canCall:true)
        let c=PreflopContext(position:.bigBlind,bigBlindCents:10,recognizedDealerID:4)
        let tight=try XCTUnwrap(RaiseResponseRequest.make(hole:h,table:t,context:c,evidence:PreflopEvidence(),preset:.tight,allowQuotedPrice:true))
        XCTAssertEqual(tight.key.ranges.first,.tightRaise)
        t.potCents=45
        let extra=try XCTUnwrap(RaiseResponseRequest.make(hole:h,table:t,context:c,evidence:PreflopEvidence(),preset:.balanced,allowQuotedPrice:true))
        XCTAssertEqual(extra.key.ranges.first,.balancedRaise)
    }
    func testBigBlindDefenseUsesRealRangeSimulationFromConfirmedQuote() async throws {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.01,samples:1000,exact:false) })
        let h=HandAnalysisTests().hand(["Js","7c"]);var t=blindTable(dealer:4)
        t.seats[2].activity = .active;t.seats[2].action = .raise;t.potCents=35;t.callCents=10
        t.controls=TableControls(canFold:true,canCall:true,canRaise:true)
        m.update(h,table:t);m.update(h,table:t);try await PreflopRaiseResponseTests().settle(m)
        XCTAssertEqual(m.raiseResponseResult?.samples,100000);XCTAssertEqual(m.responseKey?.ranges.first,.shortCutoffOpen)
        XCTAssertEqual(m.actionAdvice.kind,.call,"A priced blind-defense scenario must not always default-fold J7o")
        XCTAssertTrue(m.responseUsesQuotedPrice);m.reset()
    }
    func testUnreadableDealerDoesNotConvertConfirmedSmallBlindOpenIntoGenericFold() {
        let m=model(),h=HandAnalysisTests().hand(["Ks","5d"]);var t=blindTable(dealer:5,stack:285)
        t.callCents=5;t.controls=TableControls(canFold:true,canCall:true,canRaise:true)
        m.update(h,table:t);m.update(h,table:t)
        XCTAssertEqual(m.decisionAdvice.kind,.raise);XCTAssertEqual(m.decisionAdvice.basis,"SHORT CASH OPEN")
        let reason=m.decisionAdvice.reason
        t.dealerSeatID=nil;m.update(h,table:t)
        XCTAssertTrue(m.actionControlsConfirmed);XCTAssertTrue(m.decisionAdvice.retained)
        XCTAssertEqual(m.decisionAdvice.kind,.raise);XCTAssertEqual(m.decisionAdvice.reason,reason)
        t.controls?.canRaise=false;m.update(h,table:t)
        XCTAssertNotEqual(m.decisionAdvice.kind,.raise,"A newly readable legal restriction overrides old history")
        m.reset()
    }
    func testSmallBlindBeforeTurnUsesShortRangeAndDoesNotTreatForcedBlindAsVoluntaryCall() {
        let m=model(),h=HandAnalysisTests().hand(["Ks","5d"]);var t=blindTable(dealer:5,stack:285)
        t.seats[2].activity = .active;t.controls=nil;t.callCents=nil;t.seats[5].betCents=5
        m.update(h,table:t);m.update(h,table:t)
        XCTAssertEqual(m.effectivePosition,.smallBlind);XCTAssertTrue(m.isPlanning)
        XCTAssertEqual(m.decisionAdvice.kind,.raise);XCTAssertTrue(m.decisionAdvice.provisional)
        XCTAssertTrue(m.decisionAdvice.reason.contains("20–49 BB"));XCTAssertTrue(m.decisionAdvice.reason.contains("Assume an unopened"))
        t.potCents=25;t.seats[2].action = .call
        m.update(h,table:t);m.update(h,table:t)
        XCTAssertNotEqual(m.decisionAdvice.kind,.raise,"A limper invalidates the assumed unopened plan")
        m.reset()
    }
}
