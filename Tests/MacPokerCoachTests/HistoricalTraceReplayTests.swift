import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class HistoricalTraceReplayTests:XCTestCase {
    func testPrivateCompletedSessionReplayReachesRangeResponsesAndKeepsFreeCheckThroughGaps() async throws {
        guard let path=ProcessInfo.processInfo.environment["CARD_READER_TRACE_FIXTURE"] else { throw XCTSkip("Provide the frozen completed-hand trace; live/in-progress logs are never read by this test.") }
        let data=try String(contentsOfFile:path,encoding:.utf8)
        let rows=try data.split(separator:"\n").map { line in try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any] }
        let m=PreflopRaiseResponseTests().model(q:0.43),helper=HandAnalysisTests()
        var seen=Set<String>(),priorID="",rangeHands=Set<String>(),shortHands=Set<String>(),heldChecks=0
        for row in rows {
            guard row["event"] as? String == "hand_state",let f=row["fields"] as? [String:String],f["cards_mode"]=="confirmed_current",f["displayed_historical"] != "true",
                  let id=f["hand_id"],let hole=f["hole_cards"],!hole.isEmpty else { continue }
            if id != priorID { m.reset();priorID=id };seen.insert(id)
            let seatJSON=try XCTUnwrap(f["observed_seats_json"])
            let raw=try JSONSerialization.jsonObject(with:Data(seatJSON.utf8)) as! [[String:String]]
            let seats=raw.enumerated().map { i,s in
                TableSeat(id:Int(s["id"]!)!,bounds:UnitRect(x:0.05+Double(i)*0.09,y:i==raw.count-1 ? 0.8 : 0.25+Double(i%2)*0.25,width:0.075,height:0.05),isHero:s["hero"]=="true",stackCents:Int(s["stack_cents"] ?? "unknown"),betCents:Int(s["bet_cents"] ?? "unknown"),activity:SeatActivity(rawValue:s["activity"] ?? "unknown") ?? .unknown,action:SeatAction(rawValue:s["observed_action"] ?? "none"),isActing:s["acting"]=="true")
            }
            var flags=[String:String]()
            for bit in (f["observed_controls"] ?? "").split(separator:",") { let part=bit.split(separator:"=",maxSplits:1).map(String.init);if part.count==2 { flags[part[0]]=part[1] } }
            let controls=flags.isEmpty ? nil : TableControls(canFold:flags["fold"]=="true",canCheck:flags["check"]=="true",canCall:flags["call"]=="true",canBet:flags["bet"]=="true",canRaise:flags["raise"]=="true",raiseToCents:Int(flags["raise_to"] ?? "unknown"))
            let board=(f["board_cards"] ?? "").split(separator:" ").map(String.init)
            let h=helper.hand(hole.split(separator:" ").map(String.init),board:board)
            let issue=f["table_issue"] ?? "none"
            let t=TableObservation(potCents:Int(f["observed_pot_cents"] ?? "unknown"),callCents:Int(f["observed_call_cents"] ?? "unknown"),seats:seats,sidePots:issue.contains("Side-pot"),issue:issue.contains("Multiple chip") ? issue : nil,boardCards:board.compactMap(Card.init),controls:controls,trackingUsable:seats.count>=2,dealerSeatID:Int(f["observed_dealer_seat"] ?? "unknown"),bigBlindCents:Int(f["big_blind_cents"] ?? "unknown"))
            let before=m.display.lastVerifiedTurn
            let evidence=PreflopEvidence(heroCalled:f["tracked_preflop_call"]=="true",heroRaised:f["tracked_preflop_raise"]=="true",opponentRaises:Int(f["observed_opponent_raises"] ?? "0") ?? 0)
            m.update(h,table:t,preflop:evidence)
            if m.responseKey != nil { try await PreflopRaiseResponseTests().settle(m) }
            if m.raiseResponseResult != nil { rangeHands.insert(hole) }
            if m.decisionAdvice.basis=="SHORT CASH OPEN" { shortHands.insert(hole) }
            if hole=="As 7d",let before,before.advice.kind == .check,before.board==Set(h.board.map(\.card)),t.callCents==nil {
                XCTAssertEqual(m.decisionAdvice.kind,.check);XCTAssertTrue(m.decisionAdvice.retained);heldChecks+=1
            }
            if hole=="Ks 5d",m.actionControlsConfirmed,m.effectiveSituation == .firstIn {
                XCTAssertEqual(m.decisionAdvice.kind,.raise);XCTAssertEqual(m.decisionAdvice.basis,"SHORT CASH OPEN")
            }
        }
        XCTAssertEqual(seen.count,9)
        XCTAssertTrue(rangeHands.contains("7c Js"));XCTAssertTrue(rangeHands.contains("8d 7h"));XCTAssertTrue(rangeHands.contains("4d 5d"))
        XCTAssertTrue(shortHands.contains("Ks 5d"));XCTAssertTrue(shortHands.contains("9s 5s"));XCTAssertGreaterThan(heldChecks,0)
        m.reset()
    }
}
