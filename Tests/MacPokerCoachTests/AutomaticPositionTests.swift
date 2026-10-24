import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class AutomaticPositionTests: XCTestCase {
    func table(count: Int=6,hero: Int=3,dealer: Int=4,firstIn: Bool=true) -> TableObservation {
        let seats=(1...count).map { id in
            TableSeat(id:id,bounds:UnitRect(x:0.05+Double(id)*0.07,y:0.2+Double(id%2)*0.4,width:0.06,height:0.04),isHero:id==hero,stackCents:10000,betCents:0,activity:firstIn && id != hero && id != dealer && id != dealer%count+1 && id != (dealer+1)%count+1 ? .folded : .active)
        }
        var t=TableObservation(potCents:150,callCents:100,seats:seats,controls:TableControls(canFold:true,canCall:true,canRaise:true,raiseToCents:200),dealerSeatID:dealer,bigBlindCents:100)
        t.seats[dealer%count].betCents=50; t.seats[(dealer+1)%count].betCents=100
        return t
    }
    func testAllSixAndNineHandedPositionsFromClockwiseDealerAndDealtSeats() throws {
        for count in [6,9] { for dealer in 1...count { for hero in 1...count {
            let t=table(count:count,hero:hero,dealer:dealer,firstIn:false)
            let p=try XCTUnwrap(RecognizedPosition.read(t)),distance=(hero-dealer+count)%count
            let expected: PokerPosition
            switch distance {
            case 0: expected = .button
            case 1: expected = .smallBlind
            case 2: expected = .bigBlind
            case count-1: expected = .cutoff
            case count-2: expected = .hijack
            default: expected = count==9 && distance==6 ? .middle : .early
            }
            XCTAssertEqual(p.position,expected,"\(count), dealer \(dealer), hero \(hero)")
        } } }
    }
    func testFoldedPlayersStillCountAndSittingOutWaitingOrEmptySeatsDoNot() throws {
        var t=table(),p=try XCTUnwrap(RecognizedPosition.read(t))
        XCTAssertEqual(p.position,.cutoff)
        for i in t.seats.indices where !t.seats[i].isHero { t.seats[i].activity = .folded }
        XCTAssertEqual(RecognizedPosition.read(t)?.position,.cutoff)
        t.seats[0].activity = .sittingOut; t.seats[1].activity = .waiting
        p=try XCTUnwrap(RecognizedPosition.read(t)); XCTAssertEqual(p.position,.cutoff); XCTAssertEqual(p.ring.count,4)
        t.seats.removeFirst(2); XCTAssertEqual(RecognizedPosition.read(t)?.position,.cutoff)
        t.seats.firstIndex(where:{ $0.id==4 }).map { t.seats[$0].activity = .waiting }
        XCTAssertNil(RecognizedPosition.read(t),"No unsupported dead-button guess")
    }
    func testHeadsUpAndThreeHandedDoNotInventCutoff() {
        XCTAssertEqual(RecognizedPosition.read(table(count:2,hero:1,dealer:1,firstIn:false))?.position,.button)
        XCTAssertEqual(RecognizedPosition.read(table(count:2,hero:2,dealer:1,firstIn:false))?.position,.bigBlind)
        for h in 1...3 { XCTAssertNotEqual(RecognizedPosition.read(table(count:3,hero:h,dealer:1,firstIn:false))?.position,.cutoff) }
    }
    func testIndependentTwoFrameConfirmationRejectsChangedDealerRosterAmbiguityOrMissingInput() {
        var s=PositionStabilizer(),t=table()
        s.update(t); XCTAssertNil(s.recognized); XCTAssertNil(s.bigBlind)
        s.update(t); XCTAssertEqual(s.recognized?.position,.cutoff); XCTAssertEqual(s.bigBlind,100)
        t.potCents=900; t.seats[0].activity = .folded; t.seats[0].stackCents=100
        s.update(t); XCTAssertEqual(s.recognized?.position,.cutoff,"Unrelated chip changes do not unset position")
        t.dealerSeatID=3; s.update(t); XCTAssertNil(s.recognized)
        s.update(t); XCTAssertEqual(s.recognized?.position,.button)
        t.seats[0].activity = .unknown; s.update(t); XCTAssertNil(s.recognized)
        t=table(); s.update(t); s.update(t); XCTAssertNotNil(s.recognized)
        s.update(nil); XCTAssertNil(s.recognized); XCTAssertNil(s.bigBlind)
        s.update(t); XCTAssertNil(s.recognized)
        s.update(t); t.seats.removeFirst(); s.update(t); XCTAssertNil(s.recognized)
        s.update(t); XCTAssertNil(s.recognized,"Changed dealt roster cannot reassign positions within this hand")
        s.reset(); XCTAssertNil(s.recognized)
        s.update(t); s.update(t); XCTAssertNotNil(s.recognized,"A new hand may establish a changed roster")
    }
    func testFirstInRequiresFoldedPriorSeatsAndStandardPotButLimpRaiseAndSunkCallOverrideIt() throws {
        let t=table(),p=try XCTUnwrap(RecognizedPosition.read(t))
        XCTAssertEqual(p.situation(table:t,bigBlind:100,evidence:PreflopEvidence()),.firstIn)
        XCTAssertEqual(p.situation(table:t,bigBlind:nil,evidence:PreflopEvidence()),.unknown)
        for mode in 0..<7 {
            var a=t,e=PreflopEvidence()
            switch mode {
            case 0: a.seats[0].activity = .active
            case 1: a.seats[0].betCents=100; a.seats[0].action = .call; a.potCents=250
            case 2: a.seats[0].betCents=300; a.potCents=450
            case 3: e.heroCalled=true
            case 4: a.potCents=250
            case 5: a.sidePots=true
            default: a.seats[0].action = .raise
            }
            let r=try XCTUnwrap(RecognizedPosition.read(a)).situation(table:a,bigBlind:100,evidence:e)
            XCTAssertNotEqual(r,.firstIn,"\(mode)")
            if mode==1 { XCTAssertEqual(r,.limped) }
            if [2,3,6].contains(mode) { XCTAssertEqual(r,.raised) }
        }
    }
    func testEveryCutoffChartCellMatchesIndependentlyTranscribedSourceRows() {
        // Rows of blue cells from the source PDF's p.31, ordered A,K,Q,J,T,9,...,2.
        let blueRows=["1111111111111","1111111100000","1111111000000","1111111000000","1111111100000","1111111100000","1000111110000","1000001111000","1000000011100","1000000001100","1000000000100","1000000000010","1000000000001"]
        let ranks=Array((2...14).reversed())
        for (r,h) in ranks.enumerated() { for (c,l) in ranks.enumerated() {
            let cards=[Card(rank:max(h,l),suit:.hearts),Card(rank:min(h,l),suit:h>l ? .hearts : .spades)]
            XCTAssertEqual(CutoffOpeningChart.contains(cards),Array(blueRows[r])[c]=="1","row \(r), col \(c)")
            XCTAssertEqual(PreflopContext.opens(hole:cards,position:.cutoff),CutoffOpeningChart.contains(cards))
        } }
        XCTAssertTrue(CutoffOpeningChart.contains([Card("7h")!,Card("6h")!]))
        XCTAssertFalse(CutoffOpeningChart.contains([Card("7h")!,Card("6d")!]))
        XCTAssertFalse(CutoffOpeningChart.contains([Card("7h")!,Card("7h")!]))
    }
    @MainActor func testRecognizedCutoffSevenSixRaisesWithoutManualInputAndEarlyPositionDoesNot() {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.01,samples:1000,exact:false) }),h=HandAnalysisTests().hand(["7h","6h"]),t=table()
        m.update(h,table:t); m.update(h,table:t)
        XCTAssertEqual(m.position,.unknown,"Automatic is separate from a manual override")
        XCTAssertEqual(m.effectivePosition,.cutoff); XCTAssertEqual(m.effectiveSituation,.firstIn)
        XCTAssertEqual(m.actionAdvice.kind,.raise); XCTAssertEqual(m.decisionAdvice.kind,.raise)
        XCTAssertEqual(m.decisionAdvice.basis,"CUTOFF CASH CHART")
        XCTAssertTrue(m.decisionAdvice.reason.contains("recognized dealer")); XCTAssertNil(m.callEstimate)
        m.position = .early; XCTAssertEqual(m.effectivePosition,.early); XCTAssertEqual(m.decisionAdvice.kind,.fold)
        m.position = .unknown; XCTAssertEqual(m.decisionAdvice.kind,.raise)
        m.update(HandAnalysisTests().hand(["8h","7h"]),table:t)
        XCTAssertEqual(m.effectivePosition,.unknown,"New hand re-confirms the button")
        m.update(HandAnalysisTests().hand(["8h","7h"]),table:t); XCTAssertEqual(m.effectivePosition,.cutoff)
        m.reset(); XCTAssertEqual(m.effectivePosition,.unknown); XCTAssertNil(m.recognizedBigBlind)
    }
    @MainActor func testRecognizedPositionFeedsProvisionalPlanBeforeTurnAndShortStacksAreDisclosed() {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.01,samples:1000,exact:false) }),h=HandAnalysisTests().hand(["7h","6h"])
        var t=table(); t.controls=nil; t.callCents=nil; t.seats[0].activity = .active
        m.update(h,table:t); m.update(h,table:t)
        XCTAssertTrue(m.isPlanning); XCTAssertEqual(m.effectivePosition,.cutoff)
        XCTAssertEqual(m.decisionAdvice.kind,.raise); XCTAssertTrue(m.decisionAdvice.provisional)
        t=table(); for i in t.seats.indices { t.seats[i].stackCents=2000 }
        m.update(h,table:t); m.update(h,table:t)
        XCTAssertEqual(m.decisionAdvice.kind,.raise); XCTAssertTrue(m.decisionAdvice.provisional)
        XCTAssertTrue(m.decisionAdvice.reason.contains("short/unreadable"))
        t.dealerSeatID=nil; m.update(h,table:t)
        XCTAssertEqual(m.effectivePosition,.unknown); XCTAssertTrue(m.positionSummary.contains("fallback"))
        m.reset()
    }
    @MainActor func testCutoffOpeningChartCannotBecomeAnOpenRaiseInLimpedOrRaisedPot() {
        let m=HandAnalysisModel(calculate:{ _,_,_,_ in EquityResult(equity:0.1,samplingBound:0.01,samples:1000,exact:false) }),h=HandAnalysisTests().hand(["7h","6h"])
        for mode in 0..<3 {
            var t=table();t.potCents=450
            switch mode {
            case 0:t.seats[0].activity = .active;t.seats[0].betCents=300;t.callCents=300
            case 1:t.seats[0].activity = .active;t.seats[0].betCents=100;t.seats[0].action = .call
            default:break // More than blinds, but the individual wagers were missed.
            }
            m.update(h,table:t);m.update(h,table:t)
            XCTAssertEqual(m.effectivePosition,.cutoff)
            XCTAssertNotEqual(m.decisionAdvice.kind,.raise,"\(mode): first-in chart must not apply")
            XCTAssertNotEqual(m.decisionAdvice.basis,"CUTOFF CASH CHART")
            m.reset()
        }
    }
}
