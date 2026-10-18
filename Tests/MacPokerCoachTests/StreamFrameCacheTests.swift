import XCTest
import ScreenCaptureKit
@testable import MacPokerCoach

final class StreamFrameCacheTests: XCTestCase {
    func testIdleRequiresACompleteFrameAndRetainsOnlyLatestContent() {
        var cache = StreamFrameCache<Int>()
        XCTAssertNil(cache.observe(status:.idle))
        XCTAssertEqual(cache.observe(status:.complete,newFrame:1),1)
        XCTAssertEqual(cache.observe(status:.idle),1)
        XCTAssertEqual(cache.observe(status:.complete,newFrame:2),2)
        XCTAssertEqual(cache.observe(status:.idle),2)
    }
    func testInterruptionDiscardsOldContentUntilANewCompleteFrame() {
        for status: SCFrameStatus? in [.blank,.suspended,.stopped,.started,nil] {
            var cache = StreamFrameCache<Int>()
            XCTAssertEqual(cache.observe(status:.complete,newFrame:1),1)
            XCTAssertNil(cache.observe(status:status))
            XCTAssertNil(cache.observe(status:.idle))
            XCTAssertEqual(cache.observe(status:.complete,newFrame:2),2)
        }
    }
    func testUnreadableCompleteFrameCannotRenewAnOldImage() {
        var cache = StreamFrameCache<Int>()
        XCTAssertEqual(cache.observe(status:.complete,newFrame:1),1)
        XCTAssertNil(cache.observe(status:.complete))
        XCTAssertNil(cache.observe(status:.idle))
    }
}
