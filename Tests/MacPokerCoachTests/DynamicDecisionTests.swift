import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class DynamicDecisionTests: XCTestCase {
    func cards(_ codes: [String]) -> [Card] { codes.compactMap(Card.init) }
    func table(call: Int = 0) -> TableObservation {
        var t=ContinuousAdviceTests().table(players:4,call:call)
        t.potCents=400+call
        t.controls=TableControls(canFold:true,canCheck:call==0,canCall:call>0,canBet:call==0,canRaise:call>0)
        return t
    }
    func testPersonalTwoPairBetsForValueRatherThanAlwaysChecking() {
        let h=cards(["9s","6h"]), b=cards(["9d","6c","Ah"])
        let a=ActionAdvice.immediate(hole:h,board:b,table:table(),confirmedSize:true)
        XCTAssertEqual(a?.kind,.bet); XCTAssertTrue(a?.reason.contains("both hole cards") == true)
        XCTAssertFalse(a?.reason.contains("RAISE") == true)
        XCTAssertNil(ActionAdvice.immediate(hole:h,board:b,table:table(),confirmedSize:false))
    }
    func testLimpedCutoffTwoPairRaisesModestFirstBetButNotEveryWager() {
        let h=cards(["9s","6h"]), b=cards(["9d","6c","Ah"])
        let t=table(call:100)
        XCTAssertEqual(PostflopPolicy.aggressive(hole:h,board:b,table:t,confirmed:true,situation:.limped,position:.cutoff)?.kind,.raise)
        for mode in 0..<8 {
            var changed=t; var situation:PreflopSituation = .limped; var position:PokerPosition = .cutoff
            switch mode {
            case 0: situation = .raised
            case 1: position = .early
            case 2: changed.potCents=200
            case 3: changed.seats[3].betCents=20
            case 4: changed.seats[1].betCents=100
            case 5: changed.sidePots=true
            case 6: changed.controls?.canRaise=false
            default: changed.seats[0].stackCents=nil
            }
            XCTAssertNil(PostflopPolicy.aggressive(hole:h,board:b,table:changed,confirmed:true,situation:situation,position:position),"\(mode)")
        }
    }
    func testBoardThreatsAndBoardOnlyTwoPairDoNotTriggerValueRule() {
        for b in [["9d","6d","Ad"],["9d","6c","7h"],["9d","9c","Ah","2c","3d"]] {
            XCTAssertNil(PostflopPolicy.aggressive(hole:cards(["9s","6h"]),board:cards(b),table:table(),confirmed:true))
        }
        let h=cards(["Kh","2h"]), b=cards(["9d","9c","As","Ac","3d"])
        XCTAssertFalse(PostflopPolicy.features(hole:h,board:b)!.valueHand)
    }
    func testEquityConfirmationDoesNotDependOnMoneyOrControlsButDoesDependOnPlayers() {
        let t=table(); var changed=t
        changed.potCents=nil; changed.callCents=nil; changed.controls=nil; changed.seats[0].stackCents=nil
        XCTAssertTrue(t.agreesForEquity(with:changed)); XCTAssertFalse(t.agreesForAnalysis(with:changed))
        changed.seats[0].activity = .folded; XCTAssertFalse(t.agreesForEquity(with:changed))
        changed=t; changed.trackingUsable=false; XCTAssertFalse(t.agreesForEquity(with:changed))
    }
    func testForecastRetainsAllInsAndObservedActorChangesUpdateAssumedFolds() {
        var t=table(); t.controls=nil; t.callCents=nil; t.seats[0].isActing=true
        var f=TurnForecast.make(t,position:.cutoff,board:cards(["9d","6c","Ah"]))!
        XCTAssertEqual(f.assumedFoldIDs,[1,2,3]); XCTAssertEqual(f.opponents,0)
        XCTAssertEqual(t.activeOpponents.count,3,"Projection never mutates observed player activity")
        t.seats[1].stackCents=0
        f=TurnForecast.make(t,position:.cutoff,board:cards(["9d","6c","Ah"]))!
        XCTAssertEqual(f.assumedFoldIDs,[1,3]); XCTAssertEqual(f.opponents,1)
        t.seats[0].isActing=false; t.seats[2].isActing=true
        t.seats[0].betCents=100; t.seats[0].action = .call
        f=TurnForecast.make(t,position:.cutoff,board:cards(["9d","6c","Ah"]))!
        XCTAssertEqual(f.assumedFoldIDs,[3]); XCTAssertEqual(f.opponents,2); XCTAssertEqual(f.callCents,100)
        XCTAssertNil(f.issue)
        t.seats[2].isActing=false
        f=TurnForecast.make(t,position:.unknown,board:cards(["9d","6c","Ah"]))!
        XCTAssertFalse(f.orderKnown); XCTAssertTrue(f.assumedFoldIDs.isEmpty); XCTAssertEqual(f.opponents,3)
    }
    func testPreflopPositionForecastIncludesUnactedPlayersBehindHeroAndUsesConditionalContext() {
        var t=ContinuousAdviceTests().table(players:6,call:100)
        t.potCents=150; t.callCents=nil; t.controls=nil
        for i in t.seats.indices { t.seats[i].stackCents=10000; t.seats[i].betCents=i==1 ? 50 : i==2 ? 100 : 0 }
        // Hero CO: IDs1 BTN, 2 SB, 3 BB, 4 UTG, 5 HJ.
        let f=TurnForecast.make(t,position:.cutoff,board:[])!
        XCTAssertEqual(f.assumedFoldIDs,[4,5]); XCTAssertEqual(f.opponents,3)
        let context=PreflopContext(position:.cutoff,bigBlindCents:100)
        XCTAssertEqual(f.advice(hole:cards(["9s","8s"]),board:[],context:context).kind,.raise)
        XCTAssertTrue(f.advice(hole:cards(["9s","8s"]),board:[],context:context).reason.contains("Projected"))
        t.seats[3].betCents=100; t.seats[3].action = .call; t.potCents=250
        let next=TurnForecast.make(t,position:.cutoff,board:[])!
        XCTAssertEqual(next.assumedFoldIDs,[5]); XCTAssertEqual(next.opponents,4)
        XCTAssertNil(next.advice(hole:cards(["9s","8s"]),board:[],context:context).kind)
    }
func testForecastSuppressesPricedAdviceForKnownOpponentCardsAndMissingValueInputs() {
    let h=cards(["9s","6h"]), b=cards(["9d","6c","Ah"])
    var t=table(); t.callCents=nil; t.controls=nil
    t.seats[0].revealedCards=cards(["Kh","Kd"])
    var forecast=TurnForecast.make(t,position:.unknown,board:b)!
    XCTAssertNil(forecast.advice(hole:h,board:b,context:PreflopContext()).kind)
    t.seats[0].revealedCards=[]; t.potCents=nil
    forecast=TurnForecast.make(t,position:.unknown,board:b)!
    XCTAssertNil(forecast.advice(hole:h,board:b,context:PreflopContext()).kind)
    XCTAssertTrue(forecast.advice(hole:h,board:b,context:PreflopContext()).reason.contains("Strong made hand"))
}
    @MainActor func testBeforeTurnEquityRunsWithoutPricesAndProjectedMathDoesNotConfirmOneReading() async throws {
        let model=HandAnalysisModel(calculate:{ _,_,n,_ in EquityResult(equity:1/Double(n+1),samplingBound:0.01,samples:1000,exact:false) })
        let helper=HandAnalysisTests(), hand=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
        var t=table(); t.callCents=nil; t.controls=nil; t.potCents=nil
        model.update(hand,table:t); XCTAssertNil(model.result)
        model.update(hand,table:t); try await helper.waitForResult(model)
        XCTAssertEqual(model.result?.equity,0.25); XCTAssertTrue(model.isPlanning)
        XCTAssertNil(model.callEstimate); XCTAssertNil(model.forecast?.estimate)
        t.potCents=400; model.update(hand,table:t)
        XCTAssertFalse(model.forecastConfirmed,"A calculation callback cannot confirm a new single money reading")
        XCTAssertEqual(model.result?.equity,0.25)
        model.update(hand,table:t)
        XCTAssertTrue(model.forecastConfirmed); XCTAssertEqual(model.presentedAdvice.kind,.bet)
        XCTAssertNotNil(model.forecast?.estimate); XCTAssertNil(model.callEstimate)
        let plan=model.presentedAdvice
        var review=hand; review.isReview=true; t.seats[3].activity = .folded
        model.update(review,table:t)
        XCTAssertTrue(model.showsLastForecast); XCTAssertEqual(model.presentedAdvice,plan)
        model.reset(); XCTAssertNil(model.display.lastForecastAdvice)
    }
    @MainActor func testYourTurnValueBetNeedsFreshControlsAndIsPreservedAfterFold() async throws {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.8,samplingBound:0.01,samples:1000,exact:false) })
        let helper=HandAnalysisTests(), hand=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
        var t=table(); t.callCents=nil; t.controls=nil
        m.update(hand,table:t); m.update(hand,table:t); try await helper.waitForResult(m)
        XCTAssertEqual(m.presentedAdvice.kind,.bet); XCTAssertTrue(m.isPlanning)
        t=table(); m.update(hand,table:t)
        XCTAssertTrue(m.isPlanning); XCTAssertNil(m.actionAdvice.kind)
        m.update(hand,table:t); XCTAssertFalse(m.isPlanning); XCTAssertEqual(m.actionAdvice.kind,.bet)
        let last=m.presentedAdvice
        var review=hand; review.isReview=true; t.seats[3].activity = .folded; t.controls=nil; t.callCents=nil
        m.update(review,table:t); XCTAssertTrue(m.showsLastAdvice); XCTAssertFalse(m.showsLastForecast); XCTAssertEqual(m.presentedAdvice,last)
        let fresh=helper.hand(["Kc","Kd"]); m.update(fresh,table:table())
        XCTAssertNil(m.display.lastAdvice); XCTAssertNil(m.display.lastForecastAdvice)
    }
    @MainActor func testStrongValueHandDoesNotSilentlyBecomeCheckWhenBetReadingsAreMissing() async throws {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.8,samplingBound:0.01,samples:1000,exact:false) })
        let helper=HandAnalysisTests(), hand=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
        var t=table(); t.controls?.canBet=false
        m.update(hand,table:t); m.update(hand,table:t); try await helper.waitForResult(m)
        XCTAssertNil(m.actionAdvice.kind); XCTAssertTrue(m.actionAdvice.reason.contains("Bet button"))
        t.controls?.canBet=true; t.seats[0].stackCents=nil
        m.update(hand,table:t); m.update(hand,table:t)
        XCTAssertNil(m.actionAdvice.kind); XCTAssertTrue(m.actionAdvice.reason.contains("Strong made hand"))
    }
}
