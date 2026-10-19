import AppKit
import Vision

/// Reads only the table around the recognized hero cards. No browser integration or image persistence.
public final class TableStateDetector: @unchecked Sendable {
    struct Text: Sendable { var value: String; var confidence: Float; var bounds: UnitRect }
    public init() {}
    public func scan(_ image: CGImage,cards: [DetectedCard],heroRegions: [UnitRect] = [],excluding: [UnitRect] = []) throws -> TableObservation? {
        let selected = heroRegions.count == 2 ? CardGrouping.select(cards,near:heroRegions) : CardGrouping.select(cards)
        guard selected.issue == nil, selected.hole.count == 2 else { return nil }
        let hole = selected.hole.map(\.bounds), centerX = hole.map { $0.rect.midX }.reduce(0,+)/2
        let width = hole.map(\.width).reduce(0,+)/2, height = hole.map(\.height).reduce(0,+)/2
        let top = hole.map(\.y).min()!, bottom = hole.map { $0.rect.maxY }.max()!
        let region = CGRect(x:centerX-width*12,y:max(0,top-height*6),width:width*24,height:height*10)
            .intersection(CGRect(x:0,y:0,width:1,height:1))
        let texts = try recognize(image,region:region).filter { text in !excluding.contains { $0.rect.intersects(text.bounds.rect) } }
        let pots = texts.filter { $0.value.lowercased().hasPrefix("total pot:") && abs($0.bounds.rect.midX-centerX) < width*4 && $0.bounds.y < top-height }
        guard pots.count == 1 else { return TableObservation(potCents:nil,callCents:nil,seats:[],issue:"Cannot locate a unique total pot near your cards.") }
        let potText = pots[0], pot = labeledAmount(potText,"total pot:")
        let centerY = potText.bounds.rect.midY+height*1.2
        let tableArea = CGRect(x:centerX-width*10.5,y:potText.bounds.y-height*2.2,width:width*21,height:bottom-potText.bounds.y+height*2.8)
            .intersection(CGRect(x:0,y:0,width:1,height:1))
        let panels = seatPanels(image,width:width,height:height).filter { tableArea.contains(CGPoint(x:$0.rect.midX,y:$0.rect.midY)) }
        var seats = [TableSeat](), issue: String?
        if excluding.contains(where:{ $0.rect.intersects(tableArea) }) {
            issue = "Move the reader away from the table so every stack and card back is visible."
        }
        for panel in panels {
            if excluding.contains(where:{ $0.rect.intersects(panel.rect.insetBy(dx:0,dy:-panel.height*1.5)) }) {
                issue = "A player panel is covered by the reader window."; continue
            }
            let moneyRect = CGRect(x:panel.x+panel.width*0.32,y:panel.y+panel.height*0.08,width:panel.width*0.64,height:panel.height*0.8)
            let money = try recognize(image,region:moneyRect)
            let parsed = money.filter { $0.confidence >= 0.95 }.compactMap { TableMoney.cents($0.value) }
            let allIn = money.contains { $0.confidence >= 0.95 && $0.value.uppercased().replacingOccurrences(of:"-",with:" ") == "ALL IN" }
            let stack = parsed.count == 1 ? parsed[0] : allIn ? 0 : nil
            let hero = abs(panel.rect.midX-centerX) < width*1.5 && panel.y >= top && panel.y <= bottom+height
            let labels = texts.filter { text in
                abs(text.bounds.rect.midX-panel.rect.midX) < panel.width*0.6 && text.bounds.y >= panel.y && text.bounds.y < panel.rect.maxY+panel.height*1.1
            }.map { $0.value.uppercased() }
            let activity: SeatActivity
            if hero { activity = .active }
            else if labels.contains(where:{ $0.contains("SITTING OUT") }) { activity = .sittingOut }
            else if labels.contains(where:{ $0.contains("NEW PLAYER") }) { activity = .waiting }
            else { activity = cardBackActivity(image,panel:panel,cards:cards) }
            seats.append(TableSeat(id:0,bounds:panel,isHero:hero,stackCents:stack,activity:activity))
        }
        // Clockwise screen locations, with hero last to avoid angle wraparound from pixel jitter.
        // These IDs describe current geometry, not persistent player identities.
        seats.sort {
            if $0.isHero != $1.isHero { return !$0.isHero }
            return atan2($0.bounds.rect.midX-centerX,centerY-$0.bounds.rect.midY) < atan2($1.bounds.rect.midX-centerX,centerY-$1.bounds.rect.midY)
        }
        for i in seats.indices { seats[i].id = i+1 }
        let actionTexts = texts.filter { $0.bounds.y > bottom && $0.bounds.y < bottom+height*2.7 && abs($0.bounds.rect.midX-centerX) < width*7 }
        let checks = actionTexts.filter { $0.confidence >= 0.95 && $0.value.uppercased() == "CHECK" }
        let calls = actionTexts.filter { $0.confidence >= 0.95 && ($0.value.uppercased() == "CALL" || $0.value.uppercased().hasPrefix("CALL $")) }
        var call: Int?
        if checks.count == 1 && calls.isEmpty { call = 0 }
        else if calls.count == 1 && checks.isEmpty {
            let label = calls[0]
            if label.value.uppercased().hasPrefix("CALL $") { call = TableMoney.cents(String(label.value.dropFirst(5))) }
            else {
                let values = actionTexts.filter { $0.confidence >= 0.95 && abs($0.bounds.rect.midX-label.bounds.rect.midX) < width && $0.bounds.y >= label.bounds.y && $0.bounds.y < label.bounds.rect.maxY+height*0.45 }.compactMap { TableMoney.cents($0.value) }
                if values.count == 1 { call = values[0] }
            }
        }
        let main = texts.filter { $0.value.lowercased().hasPrefix("main pot:") && abs($0.bounds.rect.midX-centerX) < width*4 && abs($0.bounds.y-potText.bounds.y) < height }
        let mainAmount = main.count == 1 ? labeledAmount(main[0],"main pot:") : nil
        let side = texts.contains { $0.value.lowercased().contains("side pot") && abs($0.bounds.rect.midX-centerX) < width*4 } || (mainAmount != nil && mainAmount != pot)
        if !main.isEmpty && mainAmount == nil { issue = "The main-pot reading is unclear." }
        // Optional current street bets. Never confuse stack labels, pot labels or wager controls with chips.
        let amounts = texts.filter { text in
            text.confidence >= 0.95 && tableArea.contains(CGPoint(x:text.bounds.rect.midX,y:text.bounds.rect.midY)) &&
            text.bounds.y < bottom && TableMoney.cents(text.value) != nil &&
            !panels.contains(where:{ $0.rect.insetBy(dx:-width*0.2,dy:-height*0.1).intersects(text.bounds.rect) })
        }
        if amounts.contains(where:{ $0.bounds.height > height*0.28 && !isChipBet($0.bounds,seats:seats,centerX:centerX,centerY:centerY,width:width,height:height) }) {
            issue = "A large monetary label could be an unrecognized player stack."
        }
        for text in amounts {
            let distances = seats.indices.map { i in (i,hypot((text.bounds.rect.midX-seats[i].bounds.rect.midX)/width,(text.bounds.rect.midY-seats[i].bounds.rect.midY)/height)) }.sorted { $0.1 < $1.1 }
            if let nearest = distances.first, nearest.1 < 4.5 {
                if seats[nearest.0].betCents != nil { issue = "Multiple chip amounts could belong to one player." }
                seats[nearest.0].betCents = TableMoney.cents(text.value)
            }
        }
        return TableObservation(potCents:pot,callCents:call,seats:seats,sidePots:side,issue:issue)
    }
    /// A bet sits inward from a known seat toward the felt center; a missing outer stack does not.
    private func isChipBet(_ bounds: UnitRect,seats: [TableSeat],centerX: Double,centerY: Double,width: Double,height: Double) -> Bool {
        let x = (bounds.rect.midX-centerX)/width, y = (bounds.rect.midY-centerY)/height
        return seats.contains { seat in
            let sx = (seat.bounds.rect.midX-centerX)/width, sy = (seat.bounds.rect.midY-centerY)/height
            let length = sx*sx+sy*sy
            guard length > 0 else { return false }
            let t = (x*sx+y*sy)/length
            return (0.15...0.88).contains(t) && hypot(x-t*sx,y-t*sy) < 1.1
        }
    }
    private func labeledAmount(_ text: Text,_ prefix: String) -> Int? {
        guard text.confidence >= 0.95 else { return nil }
        return TableMoney.cents(String(text.value.dropFirst(prefix.count)))
    }
    func recognize(_ image: CGImage,region: CGRect) throws -> [Text] {
        let rect = region.intersection(CGRect(x:0,y:0,width:1,height:1))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return [] }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = CGRect(x:rect.minX,y:1-rect.maxY,width:rect.width,height:rect.height)
        try VNImageRequestHandler(cgImage:image).perform([request])
        return (request.results ?? []).compactMap { item in
            guard let top = item.topCandidates(1).first else { return nil }
            let b = item.boundingBox
            // Vision observations from a region request are relative to that region.
            return Text(value:top.string,confidence:top.confidence,bounds:UnitRect(x:rect.minX+b.minX*rect.width,y:rect.minY+(1-b.maxY)*rect.height,width:b.width*rect.width,height:b.height*rect.height))
        }
    }
    func seatPanels(_ image: CGImage,width: Double,height: Double) -> [UnitRect] {
        let scale = min(1,1600.0/Double(image.width)), w = Int(Double(image.width)*scale), h = Int(Double(image.height)*scale)
        guard let c = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
        guard let small = c.makeImage(), let p = SuitRecognizer.pixels(small) else { return [] }
        var mask = [Bool](repeating:false,count:w*h)
        for i in mask.indices { let r = Int(p.bytes[i*4]), g = Int(p.bytes[i*4+1]), b = Int(p.bytes[i*4+2]); mask[i] = min(r,g,b) > 70 && max(r,g,b) > 110 && max(r,g,b)-min(r,g,b) < 100 }
        var boxes = [UnitRect]()
        for start in mask.indices where mask[start] {
            var queue = [start], cursor = 0, left = start%w, right = left, top = start/w, bottom = top
            mask[start] = false
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1; let x = i%w,y = i/w
                left = min(left,x); right = max(right,x); top = min(top,y); bottom = max(bottom,y)
                for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let nx = x+dx, ny = y+dy
                    if nx >= 0 && nx < w && ny >= 0 && ny < h { let j = ny*w+nx; if mask[j] { mask[j] = false; queue.append(j) } }
                }
            }
            // Card outlines/faces can join a panel. Keep the wide horizontal band of the capsule.
            var rows = [Int](repeating:0,count:bottom-top+1)
            for i in queue { rows[i/w-top] += 1 }
            let broad = rows.indices.filter { Double(rows[$0]) > Double(right-left+1)*0.72 }
            guard let first = broad.first, let last = broad.last else { continue }
            bottom = top+last; top += first
            let bw = Double(right-left+1)/Double(w), bh = Double(bottom-top+1)/Double(h), aspect = bw*Double(w)/(bh*Double(h))
            if (3...6).contains(aspect), (2.1...4.3).contains(bw/width), (0.24...0.85).contains(bh/height), bottom-top >= 8 {
                boxes.append(UnitRect(x:Double(left)/Double(w),y:Double(top)/Double(h),width:bw,height:bh))
            }
        }
        return boxes
    }
    private func cardBackActivity(_ image: CGImage,panel: UnitRect,cards: [DetectedCard]) -> SeatActivity {
        let area = CGRect(x:panel.x+panel.width*0.18,y:panel.y-panel.height*1.45,width:panel.width*0.66,height:panel.height*1.45)
        if cards.contains(where:{ area.contains(CGPoint(x:$0.bounds.rect.midX,y:$0.bounds.rect.midY)) }) { return .active }
        guard area.minY >= 0 else { return .unknown }
        var strong = 0, clear = 0
        for x in [0.21,0.49] {
            let rect = CGRect(x:panel.x+panel.width*x,y:panel.y-panel.height*1.4,width:panel.width*0.27,height:panel.height*1.35)
            guard let crop = image.cropping(to:CGRect(x:rect.minX*Double(image.width),y:rect.minY*Double(image.height),width:rect.width*Double(image.width),height:rect.height*Double(image.height)).integral), let p = SuitRecognizer.pixels(crop) else { return .unknown }
            var dark = 0, red = 0, light = 0
            for i in 0..<(p.width*p.height) {
                let r = Int(p.bytes[i*4]),g = Int(p.bytes[i*4+1]),b = Int(p.bytes[i*4+2])
                if min(r,g,b) > 18 && max(r,g,b) < 80 && max(r,g,b)-min(r,g,b) < 25 { dark += 1 }
                if r > 100 && r > g*2 && Double(r) > Double(b)*1.6 { red += 1 }
                if min(r,g,b) > 170 { light += 1 }
            }
            let n = Double(p.width*p.height)
            if Double(dark)/n > 0.35 && Double(red)/n > 0.008 && Double(light)/n > 0.008 { strong += 1 }
            else if Double(dark)/n < 0.1 && Double(red)/n < 0.005 { clear += 1 }
        }
        return strong == 2 ? .active : clear == 2 ? .folded : .unknown
    }
}
