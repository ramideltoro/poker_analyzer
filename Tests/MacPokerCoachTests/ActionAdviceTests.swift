import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class ActionAdviceTests: XCTestCase {
    func testCallFoldCheckAndMarginalReasonsMatchThePrice() throws {
        func advice(_ q: Double,_ call: Double = 1,bound: Double = 0) throws -> ActionAdvice {
            let result = EquityResult(equity:q,samplingBound:bound,samples:100000,exact:bound == 0)
            return ActionAdvice.priced(equity:q,estimate:try CallEstimate(equity:result,potBeforeCall:3,call:call),call:call)
        }
        XCTAssertEqual(try advice(0.5).title,"CALL")
        XCTAssertEqual(try advice(0.2).title,"FOLD")
        XCTAssertEqual(try advice(0,0).title,"CHECK")
        XCTAssertTrue(try advice(0.25,bound:0.01).marginal)
        XCTAssertEqual(try advice(0.25,bound:0.01).kind,.call)
        XCTAssertTrue(try advice(0.25,bound:0.01).reason.contains("low confidence"))
        XCTAssertEqual(try advice(0.249,bound:0.01).kind,.fold)
        XCTAssertTrue(try advice(0.2).reason.contains("-0.20"))
    }
    func testRaiseRequiresUnbeatableRiverHandLegalSizeAndCoveringStacks() throws {
        let hole = ["Ah","Kh"].compactMap(Card.init), board = ["Qh","Jh","Th","2c","3d"].compactMap(Card.init)
        let result = try EquityEngine.calculate(hole:hole,board:board,opponents:1)
        var table = TableObservation(potCents:300,callCents:100,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:1000,betCents:100,activity:.active),
            TableSeat(id:2,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:1000,betCents:0,activity:.active)],controls:TableControls(canFold:true,canCall:true,canRaise:true,raiseToCents:200))
        XCTAssertEqual(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table)?.title,"RAISE")
        table.seats[0].stackCents = 50
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table))
        table.seats[0].stackCents = 1000; table.controls?.raiseToCents = 2000
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table))
        table.controls?.raiseToCents = 200; table.sidePots = true
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:result,table:table))
        table.sidePots = false
        let sampled = EquityResult(equity:0.99,samplingBound:0.01,samples:100000,exact:false,outcomes:ShowdownProbabilities(win:0.99,tie:0,lose:0.01))
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:board,result:sampled,table:table))
        XCTAssertNil(ActionAdvice.riverRaise(hole:hole,board:Array(board.prefix(4)),result:result,table:table))
    }
    @MainActor func testStoppedAndReviewStatesCannotGiveLiveAdvice() {
        let model = HandAnalysisModel()
        XCTAssertEqual(model.actionAdvice.title,"WAIT")
        var hand = HandAnalysisTests().hand(board:["2c","7s","Jd"]); hand.isReview = true
        model.update(hand)
        XCTAssertNil(model.actionAdvice.kind)
        model.reset(); XCTAssertEqual(model.actionAdvice.title,"WAIT")
    }
}

final class PremiumAdviceTests: XCTestCase {
    private func cards(_ codes: [String]) -> [Card] { codes.map { Card($0)! } }
    private func table(opponents: Int = 1) -> TableObservation {
        let foes = (1...opponents).map { i in
            TableSeat(id:i,bounds:UnitRect(x:Double(i)*0.07,y:0.3,width:0.06,height:0.05),isHero:false,
                      stackCents:10000,betCents:i == 1 ? 110 : 0,activity:.active)
        }
        return TableObservation(potCents:120,callCents:100,seats:foes+[
            TableSeat(id:9,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:10000,betCents:10,activity:.active)
        ],controls:TableControls(canFold:true,canCall:true,canRaise:true,raiseToCents:330))
    }
    private func advice(_ hole: [Card],board: [Card] = [],q: Double = 0.35,bound: Double = 0.005,table: TableObservation?) throws -> ActionAdvice {
        let result = EquityResult(equity:q,samplingBound:bound,samples:100000,exact:bound == 0)
        let call = Double(table?.callCents ?? 100)/100
        let estimate = try CallEstimate(equity:result,potBeforeCall:Double(table?.potCents ?? 120)/100,call:call)
        return ActionAdvice.recommend(hole:hole,board:board,result:result,estimate:estimate,call:call,table:table)
    }
    func testKingsActualEquityAndValueRaiseAgainstOneThroughEightRandomOpponents() throws {
        let hole = cards(["Ks","Kd"])
        for count in 1...8 {
            let result = try EquityEngine.calculate(hole:hole,board:[],opponents:count,samples:100000,seed:UInt64(4821+count))
            if count == 1 { XCTAssertEqual(result.equity,0.824,accuracy:0.012) }
            let t = table(opponents:count)
            let estimate = try CallEstimate(equity:result,potBeforeCall:1.2,call:1)
            let decision = ActionAdvice.recommend(hole:hole,board:[],result:result,estimate:estimate,call:1,table:t)
            XCTAssertEqual(decision.kind,.raise,"\(count) opponents: \(decision.reason)")
            XCTAssertTrue(decision.reason.contains("$3.30")); XCTAssertEqual(decision.basis,"PREFLOP RULE")
            if count == 8 {
                XCTAssertLessThan(estimate.upper,0,"Reproduce the old negative check-down EV with KK")
                XCTAssertEqual(ActionAdvice.priced(equity:result.equity,estimate:estimate,call:1).kind,.fold,"Old price-only policy folded KK")
            }
        }
    }
    func testAllSuitPairsOfAcesAndKingsUseThePremiumRuleAtSixAndNineSeatTables() throws {
        for rank in [13,14] { for i in 0..<3 { for j in (i+1)..<4 { for count in [5,8] {
            let hole = [Card(rank:rank,suit:Suit.allCases[i]),Card(rank:rank,suit:Suit.allCases[j])]
            XCTAssertEqual(try advice(hole,table:table(opponents:count)).kind,.raise)
        } } } }
    }
    func testUnverifiedRaiseSizesStillGiveAnActionWithoutInventingAnAmount() throws {
        let hole = cards(["Kc","Kh"])
        var t = table(opponents:8)
        for target: Int? in [nil,-1,110,219,100000001] {
            t.controls?.raiseToCents = target
            let decision = try advice(hole,table:t)
            XCTAssertEqual(decision.kind,.raise,"The confirmed Raise button offers an action even if sizing OCR fails")
            XCTAssertTrue(decision.reason.contains("Size is not confirmed"))
            XCTAssertFalse(decision.reason.contains("$"),"No unverified amount may be suggested")
        }
        t = table(); t.seats[t.seats.count-1].betCents = nil
        XCTAssertEqual(try advice(hole,table:t).kind,.raise)
        t = table(); t.seats[t.seats.count-1].stackCents = 200
        XCTAssertEqual(try advice(hole,table:t).kind,.raise)
        t = table(); t.seats[0].stackCents = 0
        XCTAssertEqual(try advice(hole,table:t).kind,.call,"Cannot add a raise against the only all-in opponent")
        t = table(); t.controls?.canRaise = false
        XCTAssertEqual(try advice(hole,q:0.82,table:t).kind,.call)
        XCTAssertEqual(try advice(hole,table:t).kind,.call)
        XCTAssertEqual(try advice(hole,table:nil).kind,.call,"Premium starting-hand rule is separate from random-hand EV")
    }
    func testPreflopRuleDoesNotOverridePostflopKingsPriceDecision() throws {
        let hole = cards(["Ks","Kd"]), board = cards(["Ah","Qh","Jh","Th","2h"])
        let result = try EquityEngine.calculate(hole:hole,board:board,opponents:1)
        let estimate = try CallEstimate(equity:result,potBeforeCall:1.2,call:1)
        XCTAssertLessThan(estimate.upper,0)
        XCTAssertEqual(ActionAdvice.recommend(hole:hole,board:board,result:result,estimate:estimate,call:1,table:table()).kind,.fold)
        XCTAssertEqual(try advice(hole,board:cards(["2c","4d","7h"]),q:0.8,table:table()).kind,.call)
        XCTAssertEqual(try advice(cards(["7s","2d"]),q:0.15,table:table()).kind,.fold)
    }
    func testFreeCheckKnownOpponentCardsAndConflictingControls() throws {
        let hole = cards(["Ks","Kd"])
        var t = table(); t.controls = TableControls(canFold:true,canCheck:true); t.callCents = 0; t.seats[0].betCents = 10
        XCTAssertEqual(try advice(hole,table:t).kind,.check)
        t.controls?.canCheck = false
        XCTAssertEqual(try advice(hole,table:t).title,"WAIT")
        t = table(); t.controls?.canCall = false
        XCTAssertEqual(try advice(hole,table:t).title,"WAIT")
        t = table(); t.seats[0].revealedCards = cards(["As","Ad"])
        XCTAssertNil(try advice(hole,table:t).kind,"Random-hand equity must not ignore known aces")
        t = table(); t.seats[t.seats.count-1].activity = .folded
        XCTAssertEqual(try advice(hole,table:t).title,"WAIT")
        XCTAssertEqual(try advice(cards(["Ks","Ks"]),table:table()).title,"WAIT")
    }
    @MainActor func testLiveKingsNewBoardAmountsReviewAndNextHandNeverReuseOldAdvice() async throws {
        let model = HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.35,samplingBound:0.005,samples:100000,exact:false) })
        let helper = HandAnalysisTests(), hand = helper.hand(["Ks","Kd"])
        let t = table(opponents:8)
        model.update(hand,table:t); model.update(hand,table:t); try await helper.waitForResult(model)
        XCTAssertEqual(model.actionAdvice.kind,.raise)
        var changed = t; changed.callCents = 150
        model.update(hand,table:changed)
        XCTAssertEqual(model.actionAdvice.title,"WAIT","One changed frame cannot retain a raise")
        var review = hand; review.isReview = true
        model.update(review,table:t)
        XCTAssertEqual(model.actionAdvice.title,"REVIEW"); XCTAssertNil(model.actionAdvice.kind)
        XCTAssertFalse(model.actionAdvice.title.contains("FOLD"),"Review is not a Fold recommendation")
        let river = helper.hand(["Ks","Kd"],board:["Ah","Qh","Jh","Th","2h"])
        model.update(river,table:t); model.update(river,table:t); try await helper.waitForResult(model)
        XCTAssertEqual(model.actionAdvice.kind,.fold,"Preflop rule must stop when the board arrives")
        let next = helper.hand(["2s","7d"])
        model.update(next,table:t)
        XCTAssertNil(model.actionAdvice.kind,"New cards must not reuse old advice")
        model.reset(); XCTAssertEqual(model.actionAdvice.title,"WAIT")
    }
    @MainActor func testInconsistentCallPotAndVisibleBetsCannotGiveAdvice() async throws {
        let model = HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.35,samplingBound:0.005,samples:100000,exact:false) })
        let helper = HandAnalysisTests(), hand = helper.hand(["Ks","Kd"])
        for reading in [table(),table()] { model.update(hand,table:reading) }
        try await helper.waitForResult(model)
        XCTAssertEqual(model.actionAdvice.kind,.raise)
        var invalids = [TableObservation]()
        var t = table(); t.callCents = 110; invalids.append(t) // raise-to mistaken for extra call
        t = table(); t.callCents = 50; invalids.append(t)
        t = table(); t.callCents = 0; invalids.append(t)
        t = table(); t.potCents = 99; invalids.append(t)
        t = table(); t.potCents = 110; invalids.append(t) // includes foe wager, but misses hero's visible bet
        t = table(); t.seats[0].betCents = -1; invalids.append(t)
        for reading in invalids {
            model.update(hand,table:reading); model.update(hand,table:reading)
            XCTAssertNil(model.callEstimate)
            XCTAssertEqual(model.actionAdvice.title,"WAIT")
        }
        model.update(hand,table:table()); model.update(hand,table:table())
        XCTAssertEqual(model.actionAdvice.kind,.raise)
    }
}
