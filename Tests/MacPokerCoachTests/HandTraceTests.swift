import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class HandTraceTests: XCTestCase {
    func records(_ folder: URL) throws -> [DiagnosticLog.Record] {
        try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter { $0.pathExtension=="jsonl" }.flatMap { file in
            try String(contentsOf:file,encoding:.utf8).split(separator:"\n").map { try JSONDecoder().decode(DiagnosticLog.Record.self,from:Data($0.utf8)) }
        }
    }
    func testTraceIncludesOwnCardsMoneyReasonAssumptionsAndIsDeduplicatedAndPrivate() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let trace=HandTraceLog(directory:folder), model=HandAnalysisModel(), helper=HandAnalysisTests()
        let h=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
        var t=DynamicDecisionTests().table(); t.seats[0].revealedCards=[Card("Kh")!,Card("Kd")!]
        model.update(h,table:t); model.update(h,table:t)
        trace.record(hand:h,observed:t,analysis:model,display:model.display,status:"synthetic")
        trace.record(hand:h,observed:t,analysis:model,display:model.display,status:"synthetic")
        trace.flush()
        var values=try records(folder); XCTAssertEqual(values.count,1)
        let f=values[0].fields
        XCTAssertEqual(f["hole_cards"],"9s 6h"); XCTAssertEqual(f["board_cards"],"9d 6c Ah")
        XCTAssertEqual(f["observed_pot_cents"],"400"); XCTAssertFalse(f["displayed_reason"]!.isEmpty)
        XCTAssertEqual(f["equity_model"],"uniform_random_legal_hands_no_future_bets_or_rake")
        XCTAssertTrue(f["observed_controls"]!.contains("bet=true"))
        XCTAssertFalse(f.values.joined().contains("Kh")); XCTAssertFalse(f.values.joined().contains("Kd"))
        let attributes=try FileManager.default.attributesOfItem(atPath:trace.fileURL!.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue,0o600)
        let priorID=f["hand_id"]
        let next=helper.hand(["Kc","Qs"]); model.update(next,table:t)
        trace.record(hand:next,observed:t,analysis:model,display:model.display,status:"synthetic")
        trace.end("synthetic stopped"); trace.flush()
        values=try records(folder); XCTAssertEqual(values.count,3)
        XCTAssertNotEqual(values[1].fields["hand_id"],priorID); XCTAssertEqual(values[2].event,"capture_end")
        model.reset()
    }
    func testAppLogsAsyncCalculationWithoutAnotherFrameAndRetainsOnlyBoundedFiles() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        for n in 0..<10 { try Data().write(to:folder.appendingPathComponent("old-\(n).jsonl")) }
        let trace=HandTraceLog(directory:folder)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,6)
        let analysis=HandAnalysisModel(calculate:{ _,_,_,_ in
            Thread.sleep(forTimeInterval:0.03)
            return EquityResult(equity:0.7,samplingBound:0.01,samples:1234,exact:false)
        })
        let app=AppModel(log:.disabled,analysis:analysis,handTrace:trace), helper=HandAnalysisTests()
        let h=helper.hand(["9s","6h"],board:["9d","6c","Ah"])
        var t=DynamicDecisionTests().table(); t.controls=nil; t.callCents=nil
        for _ in 0..<3 { app.acceptScan(CardScan(cards:h.hole+h.board,table:t)) }
        try await helper.waitForResult(analysis); trace.flush()
        let entries=try records(folder)
        XCTAssertTrue(entries.contains { $0.fields["equity_samples"]=="1234" })
        XCTAssertTrue(entries.contains { $0.fields["display_mode"]=="forecast" && $0.fields["displayed_action"]=="bet" })
        app.clear("synthetic end"); trace.flush()
        XCTAssertTrue(try records(folder).contains { $0.event=="capture_end" })
    }
    func testRotationAndDisabledLoggerDoNotWriteImages() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let trace=HandTraceLog(directory:folder,limit:100), model=HandAnalysisModel()
        let h=HandAnalysisTests().hand(), t=DynamicDecisionTests().table()
        for n in 0..<15 { trace.record(hand:h,observed:t,analysis:model,display:model.display,status:"synthetic \(n)") }
        trace.flush()
        let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
        XCTAssertLessThanOrEqual(files.count,3); XCTAssertTrue(files.allSatisfy { $0.pathExtension=="jsonl" })
        XCTAssertNil(HandTraceLog(enabled:false).fileURL)
    }
}
