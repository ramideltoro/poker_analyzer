import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class HandAnalysisTests: XCTestCase {
    func hand(_ codes: [String] = ["Ah","Kd"],board: [String] = []) -> LiveHand {
        LiveHand(hole:codes.enumerated().map { DetectedCard(card:Card($0.element)!,bounds:UnitRect(x:0.4+Double($0.offset)*0.08,y:0.7,width:0.07,height:0.12)) },board:board.enumerated().map { DetectedCard(card:Card($0.element)!,bounds:UnitRect(x:0.3+Double($0.offset)*0.08,y:0.35,width:0.07,height:0.12)) },timestamp:Date())
    }
    func waitForResult(_ model: HandAnalysisModel) async throws {
        for _ in 0..<200 {
            if model.result != nil { return }
            try await Task.sleep(nanoseconds:5_000_000)
        }
        XCTFail("Analysis did not complete")
    }
    func testSameCardsKeepAmountsButBoardAndOpponentChangesResetThem() async throws {
        let model = HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.5,samplingBound:0.01,samples:1000,exact:false) })
        model.setAutomatic(false)
        model.update(hand()); try await waitForResult(model)
        model.potText = "3.00"; model.callText = "1.00"
        XCTAssertEqual(model.callEstimate?.value,1)
        model.update(hand()); XCTAssertEqual(model.potText,"3.00"); XCTAssertNotNil(model.result)
        model.setOpponents(2); XCTAssertNil(model.result); XCTAssertEqual(model.potText,""); XCTAssertEqual(model.callText,"")
        try await waitForResult(model)
        model.potText = "3"; model.callText = "1"
        model.update(hand(board:["2c","7s","Jd"]))
        XCTAssertNil(model.result); XCTAssertEqual(model.potText,"")
        try await waitForResult(model)
        model.update(nil); XCTAssertNil(model.result); XCTAssertNil(model.callEstimate); XCTAssertFalse(model.hasCards)
    }
    func testLateOldHandResultCannotOverwriteNewCardsOrRepopulateClearedHand() async throws {
        let model = HandAnalysisModel(calculate:{ hole,_,_,_ in
            if hole.contains(Card("Ah")!) { Thread.sleep(forTimeInterval:0.15) }
            return EquityResult(equity:hole.contains(Card("Ah")!) ? 0.9 : 0.2,samplingBound:0.01,samples:1000,exact:false)
        })
        model.setAutomatic(false)
        model.update(hand()); model.update(hand(["Qc","5c"]))
        try await waitForResult(model)
        try await Task.sleep(nanoseconds:250_000_000)
        XCTAssertEqual(model.result?.equity,0.2)
        model.update(hand()); model.update(nil)
        try await Task.sleep(nanoseconds:250_000_000)
        XCTAssertNil(model.result); XCTAssertFalse(model.calculating)
    }
    func testRejectsInvalidMoneyAndSupportsZeroAdditionalCall() async throws {
        let model = HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.5,samplingBound:0,samples:990,exact:true) })
        model.setAutomatic(false)
        model.update(hand()); try await waitForResult(model)
        model.callText = "1"
        for invalid in ["-1","nan","inf","1,000","0","",String(repeating:"9",count:30)] {
            model.potText = invalid; XCTAssertNil(model.callEstimate,"\(invalid)")
        }
        model.potText = "3"; model.callText = "0"
        XCTAssertEqual(model.callEstimate?.value,1.5)
        model.setOpponents(9); XCTAssertEqual(model.opponents,1)
    }
    func testReaderStartsAnalysisAfterConfirmationAndPausesOnUnlocatedEmptyFrame() async throws {
        let model = AppModel(log:.disabled)
        model.analysis.setAutomatic(false)
        let fixture = hand(board:["2c","7s","Jd"])
        let scan = CardScan(cards:fixture.hole+fixture.board)
        model.acceptScan(scan); XCTAssertFalse(model.analysis.hasCards)
        model.acceptScan(scan); try await waitForResult(model.analysis)
        XCTAssertNotNil(model.analysis.result)
        model.analysis.potText = "3"; model.analysis.callText = "1"
        XCTAssertNotNil(model.analysis.callEstimate)
        model.acceptScan(CardScan(cards:[]))
        XCTAssertNil(model.hand); XCTAssertNil(model.analysis.result)
        XCTAssertNil(model.analysis.callEstimate); XCTAssertEqual(model.analysis.potText,"")
    }
}

@MainActor final class AutomaticAnalysisTests: XCTestCase {
    func hand() -> LiveHand {
        LiveHand(hole:["Ah","Kd"].enumerated().map { DetectedCard(card:Card($0.element)!,bounds:UnitRect(x:0.4+Double($0.offset)*0.08,y:0.7,width:0.07,height:0.12)) },board:[],timestamp:Date())
    }
    func table(pot: Int = 300,call: Int = 100) -> TableObservation {
        TableObservation(potCents:pot,callCents:call,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:1000,activity:.active),
            TableSeat(id:2,bounds:UnitRect(x:0.7,y:0.4,width:0.2,height:0.05),isHero:false,stackCents:800,activity:.folded),
            TableSeat(id:3,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:2000,activity:.active)],controls:TableControls(canFold:true,canCheck:call==0,canCall:call>0))
    }
    func model() -> HandAnalysisModel {
        HandAnalysisModel(calculate:{ _,_,count,_ in EquityResult(equity:1/Double(count+1),samplingBound:0.01,samples:12000,exact:false) })
    }
    func wait(_ model: HandAnalysisModel) async throws {
        for _ in 0..<200 { if model.result != nil { return }; try await Task.sleep(nanoseconds:5_000_000) }
        XCTFail("No automatic result")
    }
    func confirm(_ model: HandAnalysisModel,_ table: TableObservation) async throws {
        model.update(hand(),table:table); model.update(hand(),table:table); try await wait(model)
    }
    func testAutomaticInputsAndSameHandPotChangesUpdateEVWithoutRestartingEquity() async throws {
        let m = model(); XCTAssertTrue(m.automatic)
        m.update(hand(),table:table()); XCTAssertFalse(m.tableConfirmed); XCTAssertNil(m.result)
        m.update(hand(),table:table()); try await wait(m)
        XCTAssertEqual(m.callEstimate?.value,1); XCTAssertEqual(m.opponents,1)
        XCTAssertEqual(m.automaticContext?.effectiveStacks,[1000])
        let previous = m.result
        m.update(hand(),table:table(pot:400)); XCTAssertNil(m.callEstimate); XCTAssertEqual(m.result,previous)
        m.update(hand(),table:table(pot:400)); XCTAssertEqual(m.callEstimate?.value,1.5)
        XCTAssertEqual(m.potText,""); XCTAssertEqual(m.callText,"")
        m.update(nil); XCTAssertNil(m.result); XCTAssertNil(m.table); XCTAssertNil(m.callEstimate)
    }
    func testStackAndActiveOpponentChangesAreReconfirmedAndFoldedSeatsExcluded() async throws {
        let m = model(); try await confirm(m,table())
        var t = table(); t.seats[0].stackCents = 500
        m.update(hand(),table:t); XCTAssertNil(m.callEstimate)
        m.update(hand(),table:t); XCTAssertEqual(m.automaticContext?.effectiveStacks,[500])
        t.seats[1].activity = .active
        m.update(hand(),table:t); XCTAssertNil(m.result); XCTAssertNil(m.callEstimate)
        m.update(hand(),table:t); try await wait(m)
        XCTAssertEqual(m.opponents,2); XCTAssertEqual(m.result?.equity,1.0/3)
    }
    func testMissingDataSidePotsAndAmbiguousAllInsSuppressAutomaticEV() async throws {
        let m = model(); try await confirm(m,table())
        var cases = [TableObservation]()
        var t = table(); t.sidePots = true; cases.append(t)
        t = table(); t.callCents = nil; cases.append(t)
        t = table(); t.seats[0].stackCents = nil; cases.append(t)
        t = table(); t.callCents = 2000; cases.append(t)
        for t in cases {
            m.update(hand(),table:t); m.update(hand(),table:t)
            XCTAssertNil(m.callEstimate); XCTAssertFalse(m.amountHelp.isEmpty)
        }
        m.update(hand(),table:nil); XCTAssertNil(m.callEstimate); XCTAssertNil(m.result)
    }
    func testHeadsUpAllInRequiresVisibleBetsAndRemovesUnmatchedWager() async throws {
        let m = model(); var t = table(pot:3000,call:2000)
        t.seats[0].betCents = 2700; t.seats[2].betCents = 200
        try await confirm(m,t)
        XCTAssertEqual(m.automaticContext?.callCents,2000)
        XCTAssertEqual(m.automaticContext?.unmatchedCents,500)
        XCTAssertEqual(m.automaticContext?.potCents,2500)
        XCTAssertEqual(m.callEstimate?.value,2.5)
        t.seats[1].activity = .active; m.update(hand(),table:t); m.update(hand(),table:t)
        XCTAssertNil(m.callEstimate)
    }
    func testManualOverrideIsExplicitAndCaptureLossClearsAllAutomaticValues() async throws {
        let m = model(); m.update(hand()); XCTAssertNil(m.callEstimate)
        m.setAutomatic(false); try await wait(m)
        m.potText = "3"; m.callText = "1"; XCTAssertEqual(m.callEstimate?.value,1)
        m.setAutomatic(true); XCTAssertNil(m.callEstimate); XCTAssertEqual(m.potText,"")
        try await confirm(m,table()); XCTAssertNotNil(m.callEstimate)
        m.update(nil); XCTAssertNil(m.table); XCTAssertFalse(m.tableConfirmed); XCTAssertNil(m.callEstimate)
    }
    func testReaderWiresCardsAndMoneyFromSameFrameAndClearsOnStale() async throws {
        let app = AppModel(log:.disabled), h = hand(), now = Date()
        let scan = CardScan(cards:h.hole,timestamp:now,table:table())
        app.acceptScan(scan,now:now); app.acceptScan(scan,now:now)
        XCTAssertTrue(app.analysis.hasCards); XCTAssertFalse(app.analysis.tableConfirmed)
        app.acceptScan(scan,now:now)
        try await wait(app.analysis); XCTAssertTrue(app.analysis.tableConfirmed); XCTAssertNotNil(app.analysis.callEstimate)
        app.expire(now:now.addingTimeInterval(3))
        XCTAssertNil(app.analysis.table); XCTAssertNil(app.analysis.result); XCTAssertNil(app.analysis.callEstimate)
        XCTAssertNil(app.analysis.display.hand); XCTAssertNil(app.analysis.display.estimate)
    }
}

extension AutomaticAnalysisTests {
    func testTransientGapsRetainPresentationButNeverLiveEVAndReuseEquity() async throws {
        let m = model(); try await confirm(m,table())
        let prior = m.display
        m.update(hand(),table:nil)
        XCTAssertNil(m.callEstimate); XCTAssertNil(m.result)
        XCTAssertEqual(m.display.estimate,prior.estimate); XCTAssertEqual(m.display.result,prior.result)
        XCTAssertFalse(m.estimateIsCurrent); XCTAssertFalse(m.equityIsCurrent)
        m.update(hand(),table:table()); m.update(hand(),table:table())
        XCTAssertEqual(m.result,prior.result,"A confirmed repeated math input reuses its simulation")
        XCTAssertNotNil(m.callEstimate)
        m.update(nil)
        XCTAssertNil(m.result); XCTAssertNotNil(m.display.hand); XCTAssertFalse(m.estimateIsCurrent)
        m.reset(); XCTAssertNil(m.display.hand); XCTAssertNil(m.display.estimate); XCTAssertNil(m.display.result)
    }
    func testWaitingForTurnAndInactiveStackNoiseDoNotInterruptEquityOrRelevantEV() async throws {
        let m = model(); try await confirm(m,table())
        var t = table(); t.seats[1].stackCents = nil
        m.update(hand(),table:t)
        XCTAssertTrue(m.tableConfirmed); XCTAssertNotNil(m.callEstimate)
        XCTAssertEqual(m.display.table?.seats[1].stackCents,800,"Presentation retains the inactive stack")
        t.callCents = nil; m.update(hand(),table:t); m.update(hand(),table:t)
        XCTAssertNotNil(m.result); XCTAssertTrue(m.equityIsCurrent); XCTAssertNil(m.callEstimate)
        XCTAssertNotNil(m.display.estimate); XCTAssertFalse(m.estimateIsCurrent)
        XCTAssertTrue(m.displayStatus.contains("Planning before your turn"))
    }
    func testChangedCardsNeverReuseOldHandPresentation() async throws {
        let m = model(); try await confirm(m,table())
        let changed = HandAnalysisTests().hand(["Qc","5c"])
        m.update(changed,table:table())
        XCTAssertNil(m.display.result); XCTAssertNil(m.display.estimate); XCTAssertNil(m.display.table)
        XCTAssertEqual(m.display.hand?.hole.map { $0.card.code },["Qc","5c"])
    }
}

extension AutomaticAnalysisTests {
    func testSavedCardReviewUpdatesProbabilitiesButFreezesLastDecisionEV() async throws {
        let m = model(); try await confirm(m,table())
        let previous = m.display.estimate
        var review = hand(); review.isReview = true
        var t = table(pot:900,call:0); t.seats[2].activity = .folded
        m.update(review,table:t); m.update(review,table:t); try await wait(m)
        XCTAssertTrue(m.isReview); XCTAssertTrue(m.equityIsCurrent)
        XCTAssertNil(m.callEstimate); XCTAssertFalse(m.estimateIsCurrent)
        XCTAssertEqual(m.display.estimate,previous)
        review.board = ["2c","7s","Jd"].enumerated().map { DetectedCard(card:Card($0.element)!,bounds:UnitRect(x:0.25+Double($0.offset)*0.08,y:0.4,width:0.07,height:0.12)) }
        m.update(review,table:t); m.update(review,table:t); try await wait(m)
        XCTAssertEqual(m.display.hand?.board.count,3); XCTAssertEqual(m.display.estimate,previous)
        XCTAssertNotNil(m.details); XCTAssertTrue(m.amountHelp.contains("no claim"))
        t.seats[1].activity = .active
        m.update(review,table:t); m.update(review,table:t); try await wait(m)
        XCTAssertEqual(m.result?.equity,1.0/3); XCTAssertEqual(m.display.estimate,previous)
        XCTAssertNil(m.automaticContext)

        m.reset(); XCTAssertNil(m.details); XCTAssertFalse(m.isReview)
    }
}

extension AutomaticAnalysisTests {
    func testReaderContinuouslyReviewsFoldedCardsAcrossBoardChangesAndStartsNewHand() async throws {
        let app = AppModel(log:.disabled)
        let base = HandAnalysisTests()
        let flop = base.hand(board:["2c","7s","Jd"])
        let scan = CardScan(cards:flop.hole+flop.board,table:table())
        for _ in 0..<3 { app.acceptScan(scan) }
        try await wait(app.analysis)
        let ev = app.analysis.display.estimate
        XCTAssertNotNil(ev)
        var folded = table(pot:500,call:0); folded.seats[2].activity = .folded; folded.callCents = nil
        for codes in [["2c","7s","Jd"],["2c","7s","Jd","Qs"],["2c","7s","Jd","Qs","3s"]] {
            let next = base.hand(board:codes)
            for _ in 0..<3 { app.acceptScan(CardScan(cards:next.board,table:folded)) }
            try await wait(app.analysis)
            XCTAssertTrue(app.hand?.isReview == true)
            XCTAssertEqual(app.analysis.display.hand?.board.count,codes.count)
            XCTAssertEqual(app.analysis.display.estimate,ev); XCTAssertNil(app.analysis.callEstimate)
        }
        XCTAssertEqual(app.scanned,12)
        let fresh = base.hand(["Qc","5c"])
        for _ in 0..<3 { app.acceptScan(CardScan(cards:fresh.hole,table:table())) }
        try await wait(app.analysis)
        XCTAssertFalse(app.analysis.isReview); XCTAssertEqual(app.hand?.hole.map(\.card),fresh.hole.map(\.card))
        app.clear("Stopped"); XCTAssertNil(app.analysis.display.hand)
    }
}

extension AutomaticAnalysisTests {
    func testThresholdExplanationRetainsOneDecisionSnapshotWhileReviewEquityChanges() async throws {
        let m = model(); try await confirm(m,table())
        XCTAssertEqual(m.display.decisionEquity,0.5)
        XCTAssertEqual(m.display.decisionCallDollars,1)
        XCTAssertEqual(m.display.eligiblePotDollars,3)
        XCTAssertEqual(m.display.estimate?.requiredEquity,0.25)
        var review = hand(); review.isReview = true
        var t = table(pot:1000,call:0); t.seats[2].activity = .folded; t.seats[1].activity = .active
        m.update(review,table:t); m.update(review,table:t); try await wait(m)
        XCTAssertEqual(m.display.result?.equity,1.0/3)
        XCTAssertEqual(m.display.decisionEquity,0.5,"Threshold comparison must use the frozen decision, not later what-if equity")
        XCTAssertEqual(m.display.decisionCallDollars,1); XCTAssertEqual(m.display.eligiblePotDollars,3)
        m.setAutomatic(false)
        XCTAssertNil(m.display.decisionEquity); XCTAssertNil(m.display.decisionCallDollars)
        m.reset(); m.update(hand()); try await wait(m)
        m.potText = "3"; m.callText = "1"
        XCTAssertEqual(m.display.decisionCallDollars,1); XCTAssertEqual(m.display.decisionEquity,m.result?.equity)
        m.callText = "0"; XCTAssertEqual(m.display.estimate?.requiredEquity,0)
        XCTAssertEqual(m.display.decisionCallDollars,0)
        m.reset(); XCTAssertNil(m.display.decisionEquity)
    }
}
