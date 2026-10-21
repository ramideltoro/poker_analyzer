import XCTest
import AppKit
import PokerCore
@testable import TableRecognition

final class ContinuousSourceTests: XCTestCase {
    func testMovedUserSuppliedTableReacquiresOnlyWithFreshTableGeometry() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"table-flop",withExtension:"png",subdirectory:"Fixtures"))
        let source = try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let w=source.width, h=source.height
        let context = try XCTUnwrap(CGContext(data:nil,width:w*2,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let detector = AutomaticCardDetector(), tableDetector = TableStateDetector()
        var reader = ReadingStabilizer(), oldBounds = [UnitRect]()
        for offset in [0,w] {
            context.setFillColor(CGColor(gray:0.08,alpha:1)); context.fill(CGRect(x:0,y:0,width:w*2,height:h))
            context.draw(source,in:CGRect(x:offset,y:0,width:w,height:h))
            let image = try XCTUnwrap(context.makeImage())
            var scan = try detector.scan(image,searchRegions:reader.searchRegions)
            scan.table = try tableDetector.scan(image,cards:scan.cards,heroRegions:Array(reader.searchRegions.prefix(2)))
            XCTAssertEqual(scan.table?.hero?.stackCents,290)
            XCTAssertEqual(scan.table?.potCents,19); XCTAssertEqual(scan.table?.trackingUsable,true)
            if offset > 0 {
                var withoutTable = scan; withoutTable.table = nil
                XCTAssertNil(reader.accept(withoutTable).0,"A distant pair alone must not replace the hero anchor")
                var invalid = scan; invalid.table?.potCents = nil
                XCTAssertNil(reader.accept(invalid).0)
            }
            XCTAssertNil(reader.accept(scan).0)
            let hand = try XCTUnwrap(reader.accept(scan).0)
            XCTAssertEqual(hand.hole.map { $0.card.code },["Ac","Jh"])
            XCTAssertEqual(hand.board.map { $0.card.code },["4s","Tc","Jc"])
            if offset > 0 { XCTAssertGreaterThan(hand.hole[0].bounds.x-oldBounds[0].x,0.4) }
            oldBounds = hand.hole.map(\.bounds)
        }
    }
    func testMissingPotKeepsConfirmedSeatTrackingButCannotPriceAHand() throws {
        let f=TableReadingTests(), (source,cards)=f.practiceTable(seatCount:6,seatAction:"CHECK")
        let c = try XCTUnwrap(CGContext(data:nil,width:source.width,height:source.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        c.draw(source,in:CGRect(x:0,y:0,width:source.width,height:source.height))
        c.scaleBy(x:CGFloat(source.width)/1200,y:CGFloat(source.height)/1000)
        c.setFillColor(CGColor(red:0.04,green:0.19,blue:0.19,alpha:1)); c.fill(CGRect(x:490,y:1000-385,width:280,height:50))
        let image=try XCTUnwrap(c.makeImage()), detector=TableStateDetector()
        let anchored=try XCTUnwrap(detector.scan(image,cards:cards,heroRegions:cards.map(\.bounds)))
        XCTAssertEqual(anchored.seats.count,6); XCTAssertTrue(anchored.trackingUsable)
        XCTAssertNil(anchored.potCents); XCTAssertNotNil(anchored.incompleteReason)
        XCTAssertEqual(anchored.seats.filter { $0.action == .check }.count,1)
        let fresh=try XCTUnwrap(detector.scan(image,cards:cards))
        XCTAssertFalse(fresh.trackingUsable); XCTAssertTrue(fresh.seats.isEmpty)
        let blocked=try XCTUnwrap(detector.scan(image,cards:cards,heroRegions:cards.map(\.bounds),excluding:[anchored.seats[0].bounds]))
        XCTAssertFalse(blocked.trackingUsable)
    }
    func testTimerTrackRejectsBroadBandsAndStatusText() throws {
        let panel=UnitRect(x:0.4,y:0.3,width:0.2,height:0.05), detector=TableStateDetector()
        func image(_ style: Int) -> CGImage {
            let scene=NSImage(size:NSSize(width:1000,height:1000)); scene.lockFocus()
            NSColor(calibratedRed:0.04,green:0.19,blue:0.19,alpha:1).setFill(); NSRect(x:0,y:0,width:1000,height:1000).fill()
            NSColor(calibratedWhite:0.8,alpha:1).setFill()
            if style == 0 { NSRect(x:450,y:1000-375,width:130,height:5).fill() }
            if style == 1 { NSRect(x:440,y:1000-400,width:150,height:50).fill() }
            if style == 2 { ("CHECK" as NSString).draw(at:NSPoint(x:450,y:1000-380),withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.white]) }
            scene.unlockFocus(); return scene.cgImage(forProposedRect:nil,context:nil,hints:nil)!
        }
        XCTAssertTrue(detector.hasTurnBar(image(0),panel:panel))
        XCTAssertFalse(detector.hasTurnBar(image(1),panel:panel)); XCTAssertFalse(detector.hasTurnBar(image(2),panel:panel))
    }
}
