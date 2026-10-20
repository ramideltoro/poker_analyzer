import XCTest
import CoreGraphics
@testable import TableRecognition

final class SmallCropTests: XCTestCase {
    func testTinyAndNarrowRankCropsAreRejectedWithoutTrapping() throws {
        let detector = AutomaticCardDetector()
        // The reported crash had a two-pixel-wide refined crop, making 1..<0 invalid.
        for width in 1...8 { for height in 1...24 {
            let context = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
            let image = try XCTUnwrap(context.makeImage())
            var diagnostics = ScanDiagnostics()
            XCTAssertNil(detector.read(image,diagnostics:&diagnostics),"\(width) × \(height)")
        } }
    }
}
