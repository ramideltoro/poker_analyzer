import XCTest
import AppKit
import TableRecognition

final class ScreenshotTests: XCTestCase {
    func testSuppliedDiamondArtworkCropWithoutAccountData() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"diamond-hand",withExtension:"png",subdirectory:"Fixtures"))
        let image = try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let scan = try AutomaticCardDetector().scan(image)
        let selected = CardGrouping.select(scan.cards)
        XCTAssertEqual(selected.hole.map { $0.card.code },["9d","5d"],"\(scan.cards) \(scan.diagnostics.fields)")
        XCTAssertEqual(selected.board.map { $0.card.code },["6s","4s","Qs"])
        var reader = ReadingStabilizer()
        XCTAssertNil(reader.accept(scan).0)
        XCTAssertEqual(reader.accept(scan).0?.hole.map { $0.card.code },["9d","5d"])
        XCTAssertNil(reader.accept(CardScan(cards:[])).0)
        XCTAssertEqual(reader.searchRegions.count,5)
        XCTAssertNil(reader.accept(scan).0)
        XCTAssertEqual(reader.accept(scan).0?.board.map { $0.card.code },["6s","4s","Qs"])
    }
    func testDiamondHandScreenshotWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["CARD_READER_DIAMOND_FIXTURE"] else { throw XCTSkip("Provide the diamond-hand screenshot for private replay.") }
        let image = try XCTUnwrap(NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let scan = try AutomaticCardDetector().scan(image)
        let selected = CardGrouping.select(scan.cards)
        XCTAssertEqual(selected.hole.map { $0.card.code },["9d","5d"],"\(scan.cards) \(scan.diagnostics.fields) \(selected.issue ?? "")")
        XCTAssertEqual(selected.board.map { $0.card.code },["6s","4s","Qs"])
        for (width,height) in [(3840,2160),(2560,1440),(1920,1080)] {
            for offset in [0,1,7] {
                let context = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(CGColor(gray:0.1,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
                context.interpolationQuality = .high
                context.draw(image,in:CGRect(x:offset,y:offset,width:width,height:height))
                let frame = try XCTUnwrap(context.makeImage())
                let resized = try AutomaticCardDetector().scan(frame)
                let selection = CardGrouping.select(resized.cards)
                XCTAssertEqual(selection.hole.map { $0.card.code },["9d","5d"],"\(width)x\(height) offset=\(offset) \(resized.cards) \(resized.diagnostics.fields)")
                XCTAssertEqual(selection.board.map { $0.card.code },["6s","4s","Qs"],"\(width)x\(height) offset=\(offset)")
            }
        }
    }
    func testSuppliedFlopArtworkCropWithoutAccountData() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"flop-and-hand",withExtension:"png",subdirectory:"Fixtures"))
        let image = try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let scan = try AutomaticCardDetector().scan(image)
        let selected = CardGrouping.select(scan.cards)
        XCTAssertEqual(selected.hole.map { $0.card.code },["Ac","Jh"],"\(scan.cards) \(scan.diagnostics.fields)")
        XCTAssertEqual(selected.board.map { $0.card.code },["4s","Tc","Jc"])
        var reader = ReadingStabilizer()
        XCTAssertNil(reader.accept(scan).0)
        let hand = try XCTUnwrap(reader.accept(scan).0)
        XCTAssertEqual(hand.hole.map { $0.card.code },["Ac","Jh"])
        XCTAssertEqual(hand.board.map { $0.card.code },["4s","Tc","Jc"])
        XCTAssertNil(reader.accept(CardScan(cards:[])).0)
    }
    func testSecondUserScreenshotWithFlopWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["CARD_READER_FLOP_FIXTURE"] else { throw XCTSkip("Provide the second screenshot for private replay.") }
        let image = try XCTUnwrap(NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let scan = try AutomaticCardDetector().scan(image)
        let selection = CardGrouping.select(scan.cards)
        XCTAssertEqual(selection.hole.map { $0.card.code },["Ac","Jh"],"\(scan.cards) \(scan.diagnostics.fields) \(selection.issue ?? "")")
        XCTAssertEqual(selection.board.map { $0.card.code },["4s","Tc","Jc"])
        var reader = ReadingStabilizer()
        XCTAssertNil(reader.accept(scan).0)
        XCTAssertEqual(reader.accept(scan).0?.hole.map { $0.card.code },["Ac","Jh"])
        for (width,height) in [(3840,2160),(2560,1440),(1920,1080)] {
            for offset in [0,1,7] {
                let context = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(CGColor(gray:0.1,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
                context.interpolationQuality = .high
                context.draw(image,in:CGRect(x:offset,y:offset,width:width,height:height))
                let frame = try XCTUnwrap(context.makeImage())
                let resized = try AutomaticCardDetector().scan(frame)
                let selection = CardGrouping.select(resized.cards)
                XCTAssertEqual(selection.hole.map { $0.card.code },["Ac","Jh"],"\(width)x\(height) offset=\(offset) \(resized.cards) \(resized.diagnostics.fields)")
                XCTAssertEqual(selection.board.map { $0.card.code },["4s","Tc","Jc"],"\(width)x\(height) offset=\(offset)")
            }
        }
    }
    func testUserScreenshotAtCaptureResolutionsAndPixelOffsets() throws {
        guard let path = ProcessInfo.processInfo.environment["CARD_READER_SCREENSHOT_FIXTURE"] else { throw XCTSkip("Provide the original screenshot for private replay.") }
        let image = try XCTUnwrap(NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let detector = AutomaticCardDetector()
        for (width,height) in [(3840,2160),(2560,1440),(1920,1080)] {
            for offset in [0,1,7] {
                let context = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(CGColor(gray:0.1,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
                context.interpolationQuality = .high
                context.draw(image,in:CGRect(x:offset,y:offset,width:width,height:height))
                let frame = try XCTUnwrap(context.makeImage())
                let scan = try detector.scan(frame)
                let selected = CardGrouping.select(scan.cards)
                XCTAssertEqual(selected.hole.map { $0.card.code },["Qc","5c"],"\(width)x\(height) offset=\(offset): \(scan.cards) \(scan.diagnostics.fields)")
                XCTAssertTrue(selected.board.isEmpty)
            }
        }
    }
    func testUserSuppliedLargeSuitCards() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"hero",withExtension:"png",subdirectory:"Fixtures"))
        let image = try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        for scale: CGFloat in [0.5,0.75,1.0,1.25] {
            let background = NSImage(size:NSSize(width:1200,height:900))
            background.lockFocus()
            NSColor(calibratedRed:0.03,green:0.22,blue:0.15,alpha:1).setFill()
            NSRect(x:0,y:0,width:1200,height:900).fill()
            NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:NSRect(x:420,y:80,width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale))
            background.unlockFocus()
            let scene = try XCTUnwrap(background.cgImage(forProposedRect:nil,context:nil,hints:nil))
            let scan = try AutomaticCardDetector().scan(scene)
            XCTAssertEqual(Set(scan.cards.map { $0.card.code }),Set(["Qc","5c"]),"scale=\(scale) \(scan.cards) \(scan.diagnostics.fields)")
        }
    }
    func testFullUserScreenshotWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["CARD_READER_SCREENSHOT_FIXTURE"] else { throw XCTSkip("Full screenshot stays outside the project; provide its path for the private replay.") }
        let image = try XCTUnwrap(NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let scan = try AutomaticCardDetector().scan(image)
        let selected = CardGrouping.select(scan.cards)
        XCTAssertEqual(selected.hole.map { $0.card.code },["Qc","5c"],"\(scan.cards) \(scan.diagnostics.fields) \(selected.issue ?? "")")
        XCTAssertTrue(selected.board.isEmpty,"The sidebar contains a previous hand, not a live board.")
        var stabilizer = ReadingStabilizer()
        XCTAssertNil(stabilizer.accept(scan).0)
        XCTAssertEqual(stabilizer.accept(scan).0?.hole.map { $0.card.code },["Qc","5c"])
        XCTAssertNil(stabilizer.accept(CardScan(cards:[])).0)
    }
}
