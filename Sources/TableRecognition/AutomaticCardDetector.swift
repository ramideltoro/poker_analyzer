import AppKit
import Vision
import CoreImage
import PokerCore

public struct DetectedCard: Sendable, Equatable {
    public var card: Card
    public var bounds: UnitRect
    public var rankScore: Double
    public var suitScore: Double
    public init(card: Card,bounds: UnitRect,rankScore: Double = 1,suitScore: Double = 1) {
        self.card = card; self.bounds = bounds; self.rankScore = rankScore; self.suitScore = suitScore
    }
}
public struct CardScan: Sendable {
    public var cards: [DetectedCard]
    public var timestamp: Date
    public var seconds: Double
    public var rectangles: Int
    public var diagnostics: ScanDiagnostics
    public init(cards: [DetectedCard],timestamp: Date = Date(),seconds: Double = 0,rectangles: Int = 0,diagnostics: ScanDiagnostics = ScanDiagnostics()) { self.cards = cards; self.timestamp = timestamp; self.seconds = seconds; self.rectangles = rectangles; self.diagnostics = diagnostics }
}

/// Immutable shared CIContext; every Vision request and working buffer is local to scan().
public final class AutomaticCardDetector: @unchecked Sendable {
    private let context = CIContext(options:[.cacheIntermediates:false])
    public init() {}
    public func scan(_ image: CGImage,excluding: [UnitRect] = [],searchRegions: [UnitRect] = [],timestamp: Date = Date()) throws -> CardScan {
        let start = Date()
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 48; request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.38; request.maximumAspectRatio = 0.88
        request.minimumSize = 0.006; request.quadratureTolerance = 25
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        var detections = [DetectedCard](), attempted = 0
        var diagnostics = ScanDiagnostics()
        diagnostics.width = image.width; diagnostics.height = image.height
        diagnostics.excludedFraction = CaptureGeometry.coveredFraction(excluding)
        let bright = brightFaces(image)
        diagnostics.visionCandidates = request.results?.count ?? 0; diagnostics.brightCandidates = bright.count
        let hints = searchRegions.filter(\.valid)
        diagnostics.hintCandidates = hints.count
        let proposals = (hints+bright).map { ($0,Optional<VNRectangleObservation>.none) } + (request.results ?? []).map { rectangle in
            let b = rectangle.boundingBox
            return (UnitRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height),Optional(rectangle))
        }
        for (bounds,rectangle) in proposals {
            let b = bounds.rect
            let footprint = bounds.rect.insetBy(dx:-bounds.width*0.18,dy:-bounds.height*0.14)
            guard b.height*Double(image.height) >= 34, b.width*Double(image.width) >= 20, b.height < 0.5 else { diagnostics.reject(.geometry); continue }
            guard !excluding.contains(where:{ !$0.rect.intersection(footprint).isNull }) else { diagnostics.reject(.readerWindow); continue }
            // Vision aspect ratio is image-normalized; reject panels using actual pixel aspect too.
            let aspect = b.width*Double(image.width)/(b.height*Double(image.height))
            guard (0.38...0.9).contains(aspect) else { diagnostics.reject(.geometry); continue }
            guard !detections.contains(where:{ overlap($0.bounds,bounds) > 0.55 }) else { diagnostics.reject(.duplicateProposal); continue }
            attempted += 1
            var found: (Card,Double,Double)?
            if let crop = refinedCrop(image,bounds:bounds), brightFace(crop) { found = readCandidate(crop,bounds:bounds,method:"refined",diagnostics:&diagnostics) }
            else { diagnostics.reject(.nonLightFace) }
            if found == nil, let rectangle, let crop = upright(image,rectangle:rectangle), brightFace(crop) { found = readCandidate(crop,bounds:bounds,method:"perspective",diagnostics:&diagnostics) }
            guard let found else { continue }
            detections.append(DetectedCard(card:found.0,bounds:bounds,rankScore:found.1,suitScore:found.2))
        }
        return CardScan(cards:detections,timestamp:timestamp,seconds:Date().timeIntervalSince(start),rectangles:attempted,diagnostics:diagnostics)
    }
    private func brightFaces(_ image: CGImage) -> [UnitRect] {
        let scale = min(1,1600.0/Double(image.width))
        let input = CIImage(cgImage:image).transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        guard let small = context.createCGImage(input,from:input.extent), let p = SuitRecognizer.pixels(small) else { return [] }
        var white = [Bool](repeating:false,count:p.width*p.height)
        for i in white.indices { white[i] = min(p.bytes[i*4],p.bytes[i*4+1],p.bytes[i*4+2]) > 185 }
        var boxes = [UnitRect]()
        for start in white.indices where white[start] {
            var queue = [start], cursor = 0, left = start%p.width, right = left, top = start/p.width, bottom = top
            white[start] = false
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1
                let x = i%p.width, y = i/p.width
                left = min(left,x); right = max(right,x); top = min(top,y); bottom = max(bottom,y)
                for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let nx = x+dx, ny = y+dy
                    if nx >= 0 && nx < p.width && ny >= 0 && ny < p.height {
                        let j = ny*p.width+nx
                        if white[j] { white[j] = false; queue.append(j) }
                    }
                }
            }
            let width = right-left+1, height = bottom-top+1, aspect = Double(width)/Double(height)
            if height >= 25 && height < p.height/2 && (0.38...0.9).contains(aspect) && Double(queue.count)/Double(width*height) > 0.55 {
                boxes.append(UnitRect(x:Double(left)/Double(p.width),y:Double(top)/Double(p.height),width:Double(width)/Double(p.width),height:Double(height)/Double(p.height)))
            } else if height >= 25 && (0.9...3.5).contains(aspect) && width < p.width/2 {
                // Seat panels can join adjacent white faces into one component.
                // Separate their white top caps before the cards meet the panel.
                let row = min(bottom,top+3)
                var run: Int?
                for x in left...(right+1) {
                    let offset = (row*p.width+min(x,p.width-1))*4
                    let light = x <= right && min(p.bytes[offset],p.bytes[offset+1],p.bytes[offset+2]) > 185
                    if light, run == nil { run = x }
                    if !light, let start = run {
                        let capWidth = x-start, capHeight = min(height,Int(Double(capWidth)/0.68))
                        if capWidth >= 16 && capHeight >= 25 && capHeight < p.height/2 {
                            boxes.append(UnitRect(x:Double(start)/Double(p.width),y:Double(top)/Double(p.height),width:Double(capWidth)/Double(p.width),height:Double(capHeight)/Double(p.height)))
                        }
                        run = nil
                    }
                }
            }
        }
        return boxes
    }
    private func refinedCrop(_ image: CGImage,bounds: UnitRect) -> CGImage? {
        let expanded = bounds.pixels(image).insetBy(dx:-bounds.width*Double(image.width)*0.18,dy:-bounds.height*Double(image.height)*0.14)
            .intersection(CGRect(x:0,y:0,width:image.width,height:image.height)).integral
        guard let crop = image.cropping(to:expanded), let p = SuitRecognizer.pixels(crop) else { return nil }
        var white = [Bool](repeating:false,count:p.width*p.height)
        for y in 0..<p.height { for x in 0..<p.width {
            let i = (y*p.width+x)*4
            white[y*p.width+x] = min(p.bytes[i],p.bytes[i+1],p.bytes[i+2]) > 185
        } }
        var visited = [Bool](repeating:false,count:white.count), largest = [Int]()
        for start in white.indices where white[start] && !visited[start] {
            var component = [start], cursor = 0; visited[start] = true
            while cursor < component.count {
                let i = component[cursor]; cursor += 1
                let x = i%p.width, y = i/p.width
                for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let nx = x+dx, ny = y+dy
                    if nx >= 0 && nx < p.width && ny >= 0 && ny < p.height {
                        let j = ny*p.width+nx
                        if white[j] && !visited[j] { visited[j] = true; component.append(j) }
                    }
                }
            }
            if component.count > largest.count { largest = component }
        }
        let xs = largest.map { $0%p.width }, ys = largest.map { $0/p.width }
        guard let x = xs.min(), let right = xs.max(), let y = ys.min(), let bottom = ys.max(), right > x, bottom > y else { return nil }
        let rect = CGRect(x:x,y:y,width:right-x+1,height:bottom-y+1)
        // A connected seat panel must not widen the card into its neighbour.
        let face: CGImage?
        if rect.width > bounds.width*Double(image.width)*1.12 { face = image.cropping(to:bounds.pixels(image)) }
        else { face = crop.cropping(to:rect) }
        guard let face else { return nil }
        let scale = max(1,220.0/Double(face.height)), output = CIImage(cgImage:face).transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        return context.createCGImage(output,from:output.extent)
    }
    private func overlap(_ a: UnitRect,_ b: UnitRect) -> Double {
        let intersection = a.rect.intersection(b.rect)
        return intersection.isNull ? 0 : intersection.width*intersection.height/min(a.width*a.height,b.width*b.height)
    }
    private func upright(_ image: CGImage,rectangle: VNRectangleObservation) -> CGImage? {
        let w = Double(image.width), h = Double(image.height)
        let corrected = CIImage(cgImage:image).applyingFilter("CIPerspectiveCorrection",parameters:[
            "inputTopLeft":CIVector(x:rectangle.topLeft.x*w,y:rectangle.topLeft.y*h),
            "inputTopRight":CIVector(x:rectangle.topRight.x*w,y:rectangle.topRight.y*h),
            "inputBottomLeft":CIVector(x:rectangle.bottomLeft.x*w,y:rectangle.bottomLeft.y*h),
            "inputBottomRight":CIVector(x:rectangle.bottomRight.x*w,y:rectangle.bottomRight.y*h)])
        let scale = max(1,220/corrected.extent.height)
        let output = corrected.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        return context.createCGImage(output,from:output.extent)
    }
    private func brightFace(_ image: CGImage) -> Bool {
        guard let p = SuitRecognizer.pixels(image) else { return false }
        var bright = 0
        for i in stride(from:0,to:p.width*p.height,by:4) {
            if min(p.bytes[i*4],p.bytes[i*4+1],p.bytes[i*4+2]) > 165 { bright += 1 }
        }
        return Double(bright)/Double((p.width*p.height+3)/4) > 0.60
    }
    private func readCandidate(_ image: CGImage,bounds: UnitRect,method: String,diagnostics: inout ScanDiagnostics) -> (Card,Double,Double)? {
        var attempt = ScanDiagnostics()
        let result = read(image,diagnostics:&attempt)
        diagnostics.record(attempt,bounds:bounds,method:method)
        return result
    }
    private func read(_ image: CGImage,diagnostics: inout ScanDiagnostics) -> (Card,Double,Double)? {
        // Isolate the first ink row: isolated 6/9 glyphs are unreliable with text OCR alone.
        let cornerRect = CGRect(x:0,y:0,width:Double(image.width),height:Double(image.height)*0.53).integral
        guard let corner = image.cropping(to:cornerRect), let p = SuitRecognizer.pixels(corner) else { diagnostics.reject(.rankInkMissing); return nil }
        let inset = 1
        var ink = [Bool](repeating:false,count:p.width*p.height)
        for i in ink.indices { ink[i] = min(p.bytes[i*4],p.bytes[i*4+1],p.bytes[i*4+2]) < 150 }
        // Rounded card corners expose table pixels. Remove ink connected to the crop's edge.
        let border = (0..<p.width).flatMap { [$0,(p.height-1)*p.width+$0] } + (0..<p.height).flatMap { [$0*p.width,$0*p.width+p.width-1] }
        var fringe = [Int](), cursor = 0
        for i in border where ink[i] { ink[i] = false; fringe.append(i) }
        while cursor < fringe.count {
            let i = fringe[cursor]; cursor += 1
            let x = i%p.width, y = i/p.width
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                let nx = x+dx, ny = y+dy
                if nx >= 0 && nx < p.width && ny >= 0 && ny < p.height {
                    let j = ny*p.width+nx
                    if ink[j] { ink[j] = false; fringe.append(j) }
                }
            }
        }
        var rows = [Int](repeating:0,count:p.height)
        for y in 2..<p.height { for x in inset..<(p.width-2) {
            if ink[y*p.width+x] { rows[y] += 1 }
        } }
        guard let top = rows.indices.first(where:{ $0 > 1 && rows[$0] >= 2 }) else { diagnostics.reject(.rankInkMissing); return nil }
        var bottom = top, gap = 0
        for y in top..<p.height {
            if rows[y] >= 2 { bottom = y; gap = 0 } else { gap += 1 }
            if gap >= 3 { break }
        }
        guard bottom-top > image.height/20 else { diagnostics.reject(.rankInkMissing); return nil }
        var left = p.width, right = 0
        for y in top...bottom { for x in inset..<(p.width-2) {
            if ink[y*p.width+x] { left = min(left,x); right = max(right,x) }
        } }
        guard right > left else { diagnostics.reject(.rankInkMissing); return nil }
        let rankRect = CGRect(x:max(0,left-1),y:max(0,top-1),width:right-left+3,height:bottom-top+3).intersection(CGRect(x:0,y:0,width:corner.width,height:corner.height))
        guard let rankImage = corner.cropping(to:rankRect), let rank = RankRecognizer.match(rankImage) else { diagnostics.reject(.rankInkMissing); return nil }
        if rank.score >= diagnostics.bestRankScore { diagnostics.bestRankScore = rank.score; diagnostics.bestRankMargin = rank.margin }
        guard rank.score >= 0.86, rank.margin >= 0.035 else { diagnostics.reject(.rankShapeUncertain); return nil }
        // Large centered suit symbols can span nearly the whole face. The rank's
        // left edge does not predict the suit's position or width.
        let y = Double(bottom+3)
        let symbolRect = CGRect(x:0,y:y,width:Double(image.width),height:min(Double(image.height)*0.55,Double(image.height)-y)).integral
        guard let symbol = image.cropping(to:symbolRect), let suit = SuitRecognizer.match(symbol) else { diagnostics.reject(.suitInkMissing); return nil }
        if suit.score >= diagnostics.bestSuitScore { diagnostics.bestSuitScore = suit.score; diagnostics.bestSuitMargin = suit.margin }
        guard suit.score >= 0.82, suit.margin >= 0.035, let card = Card(rank.rank+suit.suit.rawValue) else { diagnostics.reject(.suitShapeUncertain); return nil }
        return (card,rank.score,suit.score)
    }
}
