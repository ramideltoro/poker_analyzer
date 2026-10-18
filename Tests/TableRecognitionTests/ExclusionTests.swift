import XCTest
import TableRecognition

final class ExclusionTests: XCTestCase {
    let display = CGRect(x:0,y:0,width:1000,height:800)
    func testFullyCoveredReaderDoesNotMaskSafari() {
        let windows = [CaptureGeometry.Window(bounds:display,isReader:false),CaptureGeometry.Window(bounds:display,isReader:true)]
        XCTAssertTrue(CaptureGeometry.visibleReaderRegions(windows,display:display).isEmpty)
    }
    func testOnlyVisiblePartOfReaderIsExcluded() {
        let windows = [CaptureGeometry.Window(bounds:CGRect(x:300,y:0,width:700,height:800),isReader:false),CaptureGeometry.Window(bounds:display,isReader:true)]
        let regions = CaptureGeometry.visibleReaderRegions(windows,display:display)
        XCTAssertEqual(CaptureGeometry.coveredFraction(regions),0.3,accuracy:0.00001)
        XCTAssertFalse(regions.contains { $0.rect.contains(CGPoint(x:0.8,y:0.7)) })
    }
    func testOtherSpaceAndTransparentOverlayDoNotInventOcclusion() {
        XCTAssertTrue(CaptureGeometry.visibleReaderRegions([],display:display).isEmpty)
        let windows = [CaptureGeometry.Window(bounds:display,isReader:false,opaque:false),CaptureGeometry.Window(bounds:display,isReader:true)]
        XCTAssertEqual(CaptureGeometry.coveredFraction(CaptureGeometry.visibleReaderRegions(windows,display:display)),1,accuracy:0.00001)
    }
    func testUnionCoverageDoesNotCountPreviousFrameTwice() {
        let region = UnitRect(x:0,y:0,width:0.5,height:0.5)
        XCTAssertEqual(CaptureGeometry.coveredFraction([region,region,region]),0.25,accuracy:0.00001)
    }
    func testRecognitionFailureSummaryExplainsStage() {
        var diagnostics = ScanDiagnostics()
        XCTAssertTrue(diagnostics.summary.contains("no card-shaped"))
        diagnostics.visionCandidates = 3; diagnostics.reject(.rankShapeUncertain)
        XCTAssertTrue(diagnostics.summary.contains("ranks or suits"))
        XCTAssertEqual(diagnostics.fields["rejected_rankShapeUncertain"],"1")
        diagnostics.excludedFraction = 1
        XCTAssertTrue(diagnostics.summary.contains("covers nearly all"))
    }
}
