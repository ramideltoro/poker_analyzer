import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class DiagnosticLogTests: XCTestCase {
    func testStructuredLogAndBoundedRotation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("card-reader-log-test-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let log = DiagnosticLog(directory:folder,limit:350)
        XCTAssertNotNil(log.fileURL)
        for i in 0..<30 { log.write("frame_received",["number":"\(i)","width":"3840"]) }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
        XCTAssertLessThanOrEqual(files.count,3)
        var records = [DiagnosticLog.Record]()
        for file in files {
            let text = try String(contentsOf:file,encoding:.utf8)
            for line in text.split(separator:"\n") { records.append(try JSONDecoder().decode(DiagnosticLog.Record.self,from:Data(line.utf8))) }
        }
        XCTAssertTrue(records.contains { $0.fields["number"] == "29" })
        XCTAssertTrue(records.allSatisfy { $0.event == "frame_received" && !$0.timestamp.isEmpty })
    }
    @MainActor func testLogsExplainNoFacesWithoutWritingCardValues() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("card-reader-log-test-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let log = DiagnosticLog(directory:folder)
        let model = AppModel(log:log)
        let pair = [DetectedCard(card:Card("Ah")!,bounds:UnitRect(x:0.4,y:0.7,width:0.07,height:0.12)),DetectedCard(card:Card("Kd")!,bounds:UnitRect(x:0.48,y:0.7,width:0.07,height:0.12))]
        model.acceptScan(CardScan(cards:pair)); model.acceptScan(CardScan(cards:pair))
        var diagnostics = ScanDiagnostics(); diagnostics.visionCandidates = 4; diagnostics.reject(.rankShapeUncertain)
        model.acceptScan(CardScan(cards:[],diagnostics:diagnostics))
        XCTAssertTrue(model.status.contains("Scanning continuously"))
        log.flush()
        let data = try String(contentsOf:XCTUnwrap(log.fileURL),encoding:.utf8)
        XCTAssertTrue(data.contains("detector_completed"))
        XCTAssertTrue(data.contains("rejected_rankShapeUncertain"))
        XCTAssertTrue(data.contains("recognized_regions"))
        XCTAssertTrue(data.contains("layout_locked"))
        XCTAssertFalse(data.contains("Ah")); XCTAssertFalse(data.contains("Kd"))
        let records = try data.split(separator:"\n").map { try JSONDecoder().decode(DiagnosticLog.Record.self,from:Data($0.utf8)) }
        XCTAssertFalse(records.contains { $0.fields.keys.contains("cards") || $0.fields.keys.contains("image") || $0.fields.keys.contains("window_title") || $0.fields.keys.contains("url") })
    }
}
