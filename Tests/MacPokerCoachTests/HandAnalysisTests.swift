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
        model.update(hand()); try await waitForResult(model)
        model.callText = "1"
        for invalid in ["-1","nan","inf","1,000","0","",String(repeating:"9",count:30)] {
            model.potText = invalid; XCTAssertNil(model.callEstimate,"\(invalid)")
        }
        model.potText = "3"; model.callText = "0"
        XCTAssertEqual(model.callEstimate?.value,1.5)
        model.setOpponents(9); XCTAssertEqual(model.opponents,1)
    }
    func testReaderStartsAnalysisOnlyAfterConfirmationAndClearsItOnFold() async throws {
        let model = AppModel(log:.disabled)
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
