import Foundation
import CoreGraphics

public struct UnitRect: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double,y: Double,width: Double,height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var valid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x+width <= 1.001 && y+height <= 1.001 }
    public var rect: CGRect { CGRect(x:x,y:y,width:width,height:height) }
    public func pixels(_ image: CGImage) -> CGRect { CGRect(x:x*Double(image.width),y:y*Double(image.height),width:width*Double(image.width),height:height*Double(image.height)).integral }
}

public enum CaptureGeometry {
    public struct Window: Sendable {
        public var bounds: CGRect
        public var isReader: Bool
        public var opaque: Bool
        public init(bounds: CGRect,isReader: Bool,opaque: Bool = true) { self.bounds = bounds; self.isReader = isReader; self.opaque = opaque }
    }
    /// Front-to-back on-screen window metadata. Fully covered/off-Space reader windows exclude nothing.
    public static func visibleReaderRegions(_ windows: [Window],display: CGRect) -> [UnitRect] {
        var covered = [CGRect](), result = [UnitRect]()
        for window in windows {
            let bounds = window.bounds.intersection(display)
            guard !bounds.isNull, !bounds.isEmpty else { continue }
            if window.isReader {
                var pieces = [bounds]
                for higher in covered { pieces = pieces.flatMap { subtract($0,higher) } }
                result += pieces.compactMap { excludedQuartzWindow($0,display:display) }
            }
            if window.opaque { covered.append(bounds) }
        }
        return result
    }
    private static func subtract(_ rect: CGRect,_ cover: CGRect) -> [CGRect] {
        let cut = rect.intersection(cover)
        guard !cut.isNull, !cut.isEmpty else { return [rect] }
        return [CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:cut.minY-rect.minY),
                CGRect(x:rect.minX,y:cut.maxY,width:rect.width,height:rect.maxY-cut.maxY),
                CGRect(x:rect.minX,y:cut.minY,width:cut.minX-rect.minX,height:cut.height),
                CGRect(x:cut.maxX,y:cut.minY,width:rect.maxX-cut.maxX,height:cut.height)].filter { !$0.isEmpty }
    }
    public static func coveredFraction(_ regions: [UnitRect]) -> Double {
        let rects = regions.filter(\.valid).map(\.rect)
        let xs = Set(rects.flatMap { [$0.minX,$0.maxX] }).sorted()
        guard xs.count >= 2 else { return 0 }
        var area = 0.0
        for i in 1..<xs.count {
            let x = (xs[i]+xs[i-1])/2
            let bands = rects.filter { $0.minX < x && $0.maxX > x }.sorted { $0.minY < $1.minY }
            var bottom = 0.0, length = 0.0
            for band in bands where band.maxY > bottom { length += band.maxY-max(bottom,band.minY); bottom = band.maxY }
            area += (xs[i]-xs[i-1])*length
        }
        return min(1,max(0,area))
    }
    /// AppKit window positions converted to the selected display's top-left coordinate space.
    public static func excludedRegion(window: CGRect,display: CGRect,mainScreenHeight: CGFloat) -> UnitRect? {
        let quartz = CGRect(x:window.minX,y:mainScreenHeight-window.maxY,width:window.width,height:window.height)
        return excludedQuartzWindow(quartz,display:display)
    }
    public static func excludedQuartzWindow(_ quartz: CGRect,display: CGRect) -> UnitRect? {
        let intersection = quartz.intersection(display)
        guard !intersection.isNull, display.width > 0, display.height > 0 else { return nil }
        return UnitRect(x:(intersection.minX-display.minX)/display.width,y:(intersection.minY-display.minY)/display.height,width:intersection.width/display.width,height:intersection.height/display.height)
    }
}
