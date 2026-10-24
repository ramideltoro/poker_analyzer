import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class GTOSolverTests:XCTestCase {
    nonisolated func sample(_ request:GTORequest,converged:Bool=true)->GTOResult {
        let choices:[GTOChoice] = request.facingBetCents==0 ? [GTOChoice(action:.check,amountCents:0,frequency:0.25,evCents:50),GTOChoice(action:.bet,amountCents:request.potCents/2,frequency:0.75,evCents:50)] : [GTOChoice(action:.fold,amountCents:0,frequency:0.1,evCents:0),GTOChoice(action:.call,amountCents:request.facingBetCents,frequency:0.9,evCents:50)]
        return GTOResult(protocol:1,engine:"fixture",iterations:20,elapsedSeconds:0.1,exploitabilityCents:Double(request.potCents)*(converged ? 0.001 : 0.02),gapPercent:converged ? 0.1 : 2,converged:converged,compressed:false,memoryBytes:1024,equity:0.5,evCents:request.facingBetCents==0 ? 50 : 45,choices:choices)
    }
    func table(_ hand:LiveHand)->TableObservation {
        var t=AutomaticPositionTests().table(count:6,hero:3,dealer:4,firstIn:false)
        for i in t.seats.indices { t.seats[i].activity = .folded;t.seats[i].betCents=0;t.seats[i].stackCents=300 }
        t.seats[2].activity = .active;t.seats[0].activity = .active
        t.potCents=100;t.callCents=0;t.boardCards=hand.board.map(\.card);t.bigBlindCents=10
        t.controls=TableControls(canCheck:true,canBet:true,betAmountCents:10)
        return t
    }
    func settle(_ model:GTOSolverModel) async throws {
        for _ in 0..<300 { if !model.running { return };try await Task.sleep(nanoseconds:5_000_000) };XCTFail("Solver did not settle")
    }
    func testFormRejectsDuplicatesPreflopOverbetsBadRakeAndExcessiveSPR() throws {
        var f=GTOForm();XCTAssertNoThrow(try f.request())
        f.hole="As As";XCTAssertThrowsError(try f.request())
        f=GTOForm();f.board="";XCTAssertThrowsError(try f.request())
        f=GTOForm();f.facingBet="3.01";XCTAssertThrowsError(try f.request())
        f=GTOForm();f.rake="nan";XCTAssertThrowsError(try f.request())
        f=GTOForm();f.stack="21";XCTAssertThrowsError(try f.request())
        f=GTOForm();f.board="QsJh2c4d3s";f.hole="10s,Ah";let r=try f.request();XCTAssertEqual(r.hole,["Ah","Ts"])
    }
    func testResultContractRejectsInvalidMixGapAndIllegalChoices() throws {
        let q=try GTOForm().request();var r=sample(q);XCTAssertNoThrow(try r.validate(for:q))
        r.choices[0].frequency=0.5;XCTAssertThrowsError(try r.validate(for:q))
        r=sample(q);r.gapPercent=0.6;XCTAssertThrowsError(try r.validate(for:q))
        r=sample(q);r.choices[0].action = .call;XCTAssertThrowsError(try r.validate(for:q))
        r=sample(q);r.choices[0].evCents = .infinity;XCTAssertThrowsError(try r.validate(for:q))
    }
    func testSnapshotCopiesRootMoneyAndRecognizesRelativePostflopOrder() throws {
        let h=HandAnalysisTests().hand(["As","Kh"],board:["Qs","Jh","2c"]);var t=table(h)
        let s=try XCTUnwrap(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)))
        XCTAssertTrue(s.heroIp);var f=GTOForm();s.fill(&f);XCTAssertTrue(s.matches(try f.request()))
        t.seats[0].betCents=37;t.seats[0].stackCents=263;t.potCents=137;t.callCents=37;t.controls=TableControls(canFold:true,canCall:true,canRaise:true)
        let paid=try XCTUnwrap(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)));paid.fill(&f)
        let q=try f.request();XCTAssertEqual(q.potCents,100);XCTAssertEqual(q.stackCents,300);XCTAssertEqual(q.facingBetCents,37)
        t.seats[2].betCents=10;XCTAssertNil(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)))
        t=table(h);t.seats[0].betCents=nil;XCTAssertNil(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)))
        t=table(h);t.seats[1].activity = .active;XCTAssertNil(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)))
        t=table(h);t.sidePots=true;XCTAssertNil(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)))
        t=table(h);XCTAssertNil(GTOSnapshot.read(hand:h,table:t,confirmed:false,position:RecognizedPosition.read(t)))
    }
    func testLiveAdviceUsesConvergedMatchingSolverBeforeHeuristicsAndRevokesOnChanges() async throws {
        let solver=GTOSolverModel(calculate:{ [self] in sample($0) })
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.5,samplingBound:0,samples:1,exact:true) },solver:solver)
        let h=HandAnalysisTests().hand(["As","Kh"],board:["Qs","Jh","2c"]);var t=table(h)
        m.update(h,table:t);m.update(h,table:t)
        XCTAssertNotNil(solver.source);solver.importSource();solver.solve();try await settle(solver)
        XCTAssertNotNil(solver.liveResult);XCTAssertEqual(m.actionAdvice.basis,"GTO SOLVER");XCTAssertEqual(m.decisionAdvice.kind,.bet)
        solver.form.rake="5";XCTAssertNil(solver.liveResult);XCTAssertNotEqual(m.actionAdvice.basis,"GTO SOLVER")
        solver.form.rake="0";XCTAssertNotNil(solver.liveResult)
        t.potCents=110;m.update(h,table:t);XCTAssertNil(m.solverAdvice)
        m.update(h,table:t);XCTAssertNil(solver.liveResult);XCTAssertNotNil(solver.result)
        t.potCents=100;m.update(h,table:t);m.update(h,table:t);XCTAssertNil(solver.liveResult,"Changed spot cannot resurrect an old live binding")
        m.reset();XCTAssertNil(solver.source);XCTAssertNil(solver.linkedSource)
    }
    func testUnconvergedOrOffTreeActionNeverBecomesSolverAdvice() async throws {
        let solver=GTOSolverModel(calculate:{ [self] in sample($0,converged:false) })
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.5,samplingBound:0,samples:1,exact:true) },solver:solver)
        let h=HandAnalysisTests().hand(["As","Kh"],board:["Qs","Jh","2c"]);let t=table(h)
        m.update(h,table:t);m.update(h,table:t);solver.importSource();solver.solve();try await settle(solver)
        XCTAssertNotNil(solver.result);XCTAssertNil(solver.liveResult);XCTAssertNotEqual(m.actionAdvice.basis,"GTO SOLVER");m.reset()
    }
    func testLateCancelledWorkerCannotReplaceNewRequestAndEditedInputsRemainStudyOnly() async throws {
        let solver=GTOSolverModel(calculate:{ [self] q in if q.potCents==100 { Thread.sleep(forTimeInterval:0.1) };return sample(q) })
        solver.solve();solver.form.pot="2";solver.solve();try await settle(solver)
        try await Task.sleep(nanoseconds:150_000_000)
        XCTAssertEqual(solver.solvedRequest?.potCents,200);XCTAssertTrue(solver.resultMatchesForm);XCTAssertNil(solver.liveResult)
        solver.form.pot="3";XCTAssertFalse(solver.resultMatchesForm)
        solver.solve();solver.stop();try await Task.sleep(nanoseconds:120_000_000);XCTAssertNil(solver.result)
    }
func testAutomaticModeReusesSameInFlightSpotAndReplacesChangedInput() async throws {
    let solver=GTOSolverModel(calculate:{ [self] q in Thread.sleep(forTimeInterval:0.08);return sample(q) })
    let h=HandAnalysisTests().hand(["As","Kh"],board:["Qs","Jh","2c"]),t=table(h)
    let first=try XCTUnwrap(GTOSnapshot.read(hand:h,table:t,confirmed:true,position:RecognizedPosition.read(t)))
    solver.observe(first);solver.setAutomatic(true);solver.observe(nil);solver.observe(first)
    XCTAssertTrue(solver.running);try await settle(solver);XCTAssertNotNil(solver.liveResult)
    var changed=first;changed.pot=200;solver.observe(changed);XCTAssertNil(solver.result)
    try await settle(solver);XCTAssertEqual(solver.solvedRequest?.potCents,200);XCTAssertNotNil(solver.liveResult)
    solver.captureStopped();XCTAssertNil(solver.liveResult);XCTAssertNil(solver.source)
}
func testUnsupportedPreferredActionAndUnconfirmedMinimumNeverOverrideLiveAdvice() async throws {
    let solver=GTOSolverModel(calculate:{ [self] in sample($0) })
    let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.5,samplingBound:0,samples:1,exact:true) },solver:solver)
    let h=HandAnalysisTests().hand(["As","Kh"],board:["Qs","Jh","2c"]);var t=table(h)
    t.controls=TableControls(canCheck:true);m.update(h,table:t);m.update(h,table:t)
    solver.importSource();solver.solve();try await settle(solver)
    XCTAssertNotNil(solver.liveResult);XCTAssertNil(m.solverAdvice);XCTAssertEqual(m.decisionAdvice.kind,.check)
    t.controls=TableControls(canCheck:true,canBet:true);t.bigBlindCents=nil
    m.update(h,table:t);m.update(h,table:t);XCTAssertNil(m.solverAdvice);m.reset()
}
func testNativeHelperTypicalTurnUsesRealRangeStrategyAndValidatedEVs() throws {
    guard let executable=GTOSolverRunner.executable else { throw XCTSkip("Set CARD_READER_SOLVER_EXECUTABLE") }
    var f=GTOForm();f.board="Qs Jh 2c 4d";let q=try f.request()
    let r=try GTOSolverRunner.run(q,executable:executable)
    XCTAssertTrue(r.converged);XCTAssertGreaterThan(r.iterations,0);XCTAssertGreaterThan(r.memoryBytes,0)
    XCTAssertEqual(r.choices.reduce(0) { $0+$1.frequency },1,accuracy:0.001);XCTAssertNoThrow(try r.validate(for:q))
}
    func testNativeHelperExactAllInEVAndBadRangeError() throws {
        guard let executable=GTOSolverRunner.executable else { throw XCTSkip("Set CARD_READER_SOLVER_EXECUTABLE to run the real native helper") }
        var f=GTOForm();f.hole="As Kd";f.board="2c 3d 4h 5s 9c";f.oopRange="AsKd";f.ipRange="KcKh";f.pot="2";f.stack="1";f.facingBet="1"
        let q=try f.request(),r=try GTOSolverRunner.run(q,executable:executable)
        XCTAssertTrue(r.converged);XCTAssertEqual(r.preferred?.action,.call);XCTAssertEqual(try XCTUnwrap(r.choices.first(where:{$0.action == .call})).evCents,300,accuracy:0.01)
        f.ipRange="invalid";XCTAssertThrowsError(try GTOSolverRunner.run(f.request(),executable:executable))
    }
}
