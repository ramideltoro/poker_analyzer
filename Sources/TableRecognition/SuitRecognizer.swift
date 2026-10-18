import AppKit
import CoreText
import PokerCore

/// Geometric glyph similarity, not a probability of correctness.
public enum SuitRecognizer {
    public struct Match { public var suit: Suit; public var score: Double; public var margin: Double }
    private static let templates: [(Suit,[Bool])] = {
        var result = CardArtworkTemplates.suits
        for name in ["Arial","Times New Roman","Georgia","Helvetica Neue","Apple Symbols","DejaVu Sans"] {
            for suit in Suit.allCases {
                let image = render(suit,fontName:name)
                if let mask = mask(image) { result.append((suit,mask)) }
            }
        }
        return result
    }()
    public static func render(_ suit: Suit,fontName: String = "Arial") -> CGImage {
        renderGlyph(suit.symbol,fontName:fontName)
    }
    static func renderGlyph(_ glyph: String,fontName: String) -> CGImage {
        let context = CGContext(data:nil,width:128,height:128,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray:1,alpha:1); context.fill(CGRect(x:0,y:0,width:128,height:128))
        let font = CTFontCreateWithName(fontName as CFString,100,nil)
        let string = NSAttributedString(string:glyph,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)])
        let line = CTLineCreateWithAttributedString(string)
        context.textPosition = CGPoint(x:6,y:20); CTLineDraw(line,context)
        return context.makeImage()!
    }
    public static func match(_ image: CGImage) -> Match? {
        guard let sample = mask(image) else { return nil }
        let scores = Suit.allCases.compactMap { suit -> (Suit,Double)? in
            let best = templates.filter { $0.0 == suit }.map { alignedDice(sample,$0.1) }.max() ?? 0
            return (suit,best)
        }.sorted { $0.1 > $1.1 }
        guard scores.count == 4 else { return nil }
        return Match(suit:scores[0].0,score:scores[0].1,margin:scores[0].1-scores[1].1)
    }
    static func dice(_ a: [Bool],_ b: [Bool]) -> Double {
        var overlap = 0, count = 0
        for i in a.indices { if a[i] { count += 1 }; if b[i] { count += 1 }; if a[i] && b[i] { overlap += 1 } }
        return count > 0 ? Double(2*overlap)/Double(count) : 0
    }
    static func alignedDice(_ a: [Bool],_ b: [Bool]) -> Double {
        let count = a.filter { $0 }.count+b.filter { $0 }.count
        guard count > 0 else { return 0 }
        var best = 0
        for dy in -1...1 { for dx in -1...1 {
            var overlap = 0
            for y in 1..<27 { for x in 1..<27 where a[y*28+x] && b[(y+dy)*28+x+dx] { overlap += 1 } }
            best = max(best,overlap)
        } }
        return Double(2*best)/Double(count)
    }
    static func pixels(_ image: CGImage) -> (bytes:[UInt8],width:Int,height:Int)? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating:255,count:w*h*4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        return success ? (bytes,w,h) : nil
    }
    static func mask(_ image: CGImage,largestOnly: Bool = true) -> [Bool]? {
        guard let p = pixels(image) else { return nil }
        let w = p.width, h = p.height
        var foreground = [Bool](repeating:false,count:w*h)
        for i in foreground.indices {
            let offset = i*4
            foreground[i] = min(p.bytes[offset],p.bytes[offset+1],p.bytes[offset+2]) < 150
        }
        // Ignore isolated antialiasing/noise and select the largest connected ink component.
        var visited = [Bool](repeating:false,count:w*h), largest = [Int](), all = [Int]()
        for start in foreground.indices where foreground[start] && !visited[start] {
            var queue = [start], cursor = 0; visited[start] = true
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1
                let x = i%w, y = i/w
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x+dx, ny = y+dy
                    if nx >= 0 && nx < w && ny >= 0 && ny < h {
                        let j = ny*w+nx
                        if foreground[j] && !visited[j] { visited[j] = true; queue.append(j) }
                    }
                } }
            }
            if queue.count > largest.count { largest = queue }
            if queue.count >= 4 { all += queue }
        }
        if !largestOnly { largest = all }
        guard largest.count >= 8 else { return nil }
        let xs = largest.map { $0%w }, ys = largest.map { $0/w }
        let minX = xs.min()!, minY = ys.min()!, bw = xs.max()!-minX+1, bh = ys.max()!-minY+1
        guard Double(bw)/Double(bh) > 0.35, Double(bw)/Double(bh) < 1.8 else { return nil }
        let set = Set(largest)
        // Preserve aspect ratio instead of stretching hearts/diamonds into the same square.
        let scale = 24.0/Double(max(bw,bh)), ox = (28-Double(bw)*scale)/2, oy = (28-Double(bh)*scale)/2
        var mask = [Bool](repeating:false,count:28*28)
        for y in 0..<28 { for x in 0..<28 {
            let sx = Int((Double(x)-ox)/scale)+minX, sy = Int((Double(y)-oy)/scale)+minY
            if Double(x) >= ox && Double(y) >= oy && sx >= minX && sx < minX+bw && sy >= minY && sy < minY+bh { mask[y*28+x] = set.contains(sy*w+sx) }
        } }
        return mask
    }
}
