import AppKit
import Vision
import PokerCore

/// Reads only the table around the recognized hero cards. No browser integration or image persistence.
public final class TableStateDetector: @unchecked Sendable {
    struct Text: Sendable { var value: String; var confidence: Float; var bounds: UnitRect }
    public init() {}
    public func scan(_ image: CGImage,cards: [DetectedCard],heroRegions: [UnitRect] = [],excluding: [UnitRect] = []) throws -> TableObservation? {
        let anchored = heroRegions.count == 2 ? CardGrouping.select(cards,near:heroRegions) : CardGrouping.select(cards)
        let fresh = CardGrouping.select(cards)
        let moved = anchored.issue != nil && fresh.issue == nil
        let selected = moved ? fresh : anchored
        let heroVisible = selected.issue == nil && selected.hole.count == 2
        guard heroVisible || heroRegions.count == 2 else { return nil }
        let hole = heroVisible ? selected.hole.map(\.bounds) : heroRegions
        let centerX = hole.map { $0.rect.midX }.reduce(0,+)/2
        let width = hole.map(\.width).reduce(0,+)/2, height = hole.map(\.height).reduce(0,+)/2
        let top = hole.map(\.y).min()!, bottom = hole.map { $0.rect.maxY }.max()!
        let region = CGRect(x:centerX-width*12,y:max(0,top-height*6),width:width*24,height:height*10)
            .intersection(CGRect(x:0,y:0,width:1,height:1))
        let texts = try recognize(image,region:region).filter { text in !excluding.contains { $0.rect.intersects(text.bounds.rect) } }
        let pots = texts.filter { $0.value.lowercased().hasPrefix("total pot:") && abs($0.bounds.rect.midX-centerX) < width*4 && $0.bounds.y < top-height }
        guard pots.count == 1 || (heroRegions.count == 2 && !moved) else { return TableObservation(potCents:nil,callCents:nil,seats:[],issue:"Cannot locate a unique total pot near your cards.") }
        let potText = pots.count == 1 ? pots[0] : nil, pot = potText.flatMap { labeledAmount($0,"total pot:") }
        let potY = potText?.bounds.y ?? max(0,top-height*3.5)
        let centerY = potText.map { $0.bounds.rect.midY+height*1.2 } ?? top-height*2.2
        let tableArea = CGRect(x:centerX-width*10.5,y:potY-height*2.2,width:width*21,height:bottom-potY+height*2.8)
            .intersection(CGRect(x:0,y:0,width:1,height:1))
        let panels = seatPanels(image,width:width,height:height).filter { tableArea.contains(CGPoint(x:$0.rect.midX,y:$0.rect.midY)) }
        let heroPanel = panels.first { abs($0.rect.midX-centerX) < width*1.5 && $0.y >= top && $0.y <= bottom+height }
        let controlsTop = max(bottom,(heroPanel?.rect.maxY ?? bottom)+height*0.25)
        var seats = [TableSeat](), issue: String? = pot == nil ? "Total pot unreadable; seat tracking continues from the confirmed layout." : nil
        var blocked = false
        if excluding.contains(where:{ $0.rect.intersects(tableArea) }) {
            issue = "Move the reader away from the table so every stack and card back is visible."
            blocked = true
        }
        for panel in panels {
            if excluding.contains(where:{ $0.rect.intersects(panel.rect.insetBy(dx:0,dy:-panel.height*1.5)) }) {
                issue = "A player panel is covered by the reader window."; blocked = true; continue
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
            if hero { activity = heroVisible ? .active : .folded }
            else if labels.contains(where:{ $0.contains("SITTING OUT") }) { activity = .sittingOut }
            else if labels.contains(where:{ $0.contains("NEW PLAYER") }) { activity = .waiting }
            else { activity = cardBackActivity(image,panel:panel,cards:cards) }
            let badge = CGRect(x:panel.x,y:panel.y,width:panel.width*0.29,height:panel.height)
            let numbers = texts.filter { $0.confidence >= 0.95 && badge.contains(CGPoint(x:$0.bounds.rect.midX,y:$0.bounds.rect.midY)) }
                .compactMap { Int($0.value.trimmingCharacters(in:.whitespacesAndNewlines)) }.filter { (1...9).contains($0) }
            let actionArea = CGRect(x:panel.x,y:panel.y-panel.height*0.12,width:panel.width,height:panel.height*2.3)
            func isActionText(_ text: Text) -> Bool {
                // Available hero action buttons are not completed player actions.
                let inControls = text.bounds.y >= controlsTop && abs(text.bounds.rect.midX-centerX) < width*7
                return text.confidence >= 0.98 && !inControls && actionArea.contains(CGPoint(x:text.bounds.rect.midX,y:text.bounds.rect.midY))
            }
            var observedActions = Set((texts+money).filter(isActionText).compactMap { SeatAction.parse($0.value) })
            if observedActions.isEmpty {
                let area = CGRect(x:panel.x+panel.width*0.08,y:panel.y+panel.height*0.9,width:panel.width*0.92,height:panel.height*1.35)
                let focused = try recognize(image,region:area).filter { text in !excluding.contains { $0.rect.intersects(text.bounds.rect) } }
                observedActions = Set(focused.filter(isActionText).compactMap { SeatAction.parse($0.value) })
            }
            seats.append(TableSeat(id:0,bounds:panel,isHero:hero,stackCents:stack,activity:activity,
                                   seatNumber:numbers.count == 1 ? numbers[0] : nil,isNewPlayer:labels.contains { $0.contains("NEW PLAYER") },action:observedActions.count == 1 ? observedActions.first : nil,isActing:hasTurnBar(image,panel:panel)))
        }
        // Clockwise screen locations, with hero last to avoid angle wraparound from pixel jitter.
        // These IDs describe current geometry, not persistent player identities.
        seats.sort {
            if $0.isHero != $1.isHero { return !$0.isHero }
            return atan2($0.bounds.rect.midX-centerX,centerY-$0.bounds.rect.midY) < atan2($1.bounds.rect.midX-centerX,centerY-$1.bounds.rect.midY)
        }
        for i in seats.indices { seats[i].id = i+1 }
        let actionTexts = texts.filter { $0.bounds.y >= controlsTop && $0.bounds.y < bottom+height*2.7 && abs($0.bounds.rect.midX-centerX) < width*7 }
        var (controls,call) = readActions(actionTexts,width:width,height:height)
        if call == nil {
            // OCR may merge a two-line button into one string in the whole-table
            // pass. Retry only the bounded action area; never reuse old buttons.
            let area = CGRect(x:centerX-width*7,y:controlsTop,width:width*14,height:max(0,bottom+height*2.7-controlsTop))
            let focused = try recognize(image,region:area).filter { text in !excluding.contains { $0.rect.intersects(text.bounds.rect) } }
            let retry = readActions(focused,width:width,height:height)
            if retry.1 != nil { (controls,call) = retry }
        }
        let main = texts.filter { $0.value.lowercased().hasPrefix("main pot:") && abs($0.bounds.rect.midX-centerX) < width*4 && abs($0.bounds.y-potY) < height }
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
        let board = CardGrouping.reviewBoard(cards,anchor:hole)?.map(\.card) ?? []
        let reveals = RevealedCards.associate(cards:cards,seats:seats,known:board+(heroVisible ? selected.hole.map(\.card) : []))
        for i in seats.indices { seats[i].revealedCards = reveals[i] }
        if call != nil, controls.canCall || controls.canCheck {
            for i in seats.indices { seats[i].isActing = seats[i].isHero }
        }
        let tracking = !blocked && seats.filter(\.isHero).count == 1 && (2...9).contains(seats.count)
        return TableObservation(potCents:pot,callCents:call,seats:seats,sidePots:side,issue:issue,boardCards:board,controls:controls,trackingUsable:tracking)
    }
    /// A thin neutral timer track below a seat; broad status strips and text are rejected.
    func hasTurnBar(_ image: CGImage,panel: UnitRect) -> Bool {
        let area = UnitRect(x:panel.x+panel.width*0.2,y:panel.rect.maxY+panel.height*0.18,width:panel.width*0.76,height:panel.height*0.67)
        guard area.valid, let crop = image.cropping(to:area.pixels(image)), let p = SuitRecognizer.pixels(crop) else { return false }
        let minimum = max(8,Int(Double(image.width)*panel.width*0.35)), maxHeight = max(2,Int(Double(image.height)*panel.height*0.22))
        var rows = 0
        for y in 0..<p.height {
            var run = 0, longest = 0
            for x in 0..<p.width {
                let i = (y*p.width+x)*4, values = [Int(p.bytes[i]),Int(p.bytes[i+1]),Int(p.bytes[i+2])]
                if values.min()! > 100 && values.max()!-values.min()! < 45 { run += 1; longest = max(longest,run) } else { run = 0 }
            }
            if longest >= minimum { rows += 1 }
            else { if rows >= 2 && rows <= maxHeight { return true }; rows = 0 }
        }
        return rows >= 2 && rows <= maxHeight
    }
    /// Whitespace is normalized; card characters and monetary digits are never guessed.
    func readActions(_ texts: [Text],width: Double,height: Double) -> (TableControls,Int?) {
        let actionTexts = texts.filter { $0.confidence >= 0.95 }.map { text -> Text in
            var copy = text
            copy.value = copy.value.uppercased().trimmingCharacters(in:.whitespacesAndNewlines)
                .replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression)
            return copy
        }
        func labels(_ names: [String]) -> [Text] {
            actionTexts.filter { text in names.contains { name in text.value == name || text.value.hasPrefix(name+" $") || text.value.hasPrefix(name+"$") } }
        }
        let checks = actionTexts.filter { $0.value == "CHECK" }, calls = labels(["CALL"]), raises = labels(["RAISE","RAISE TO"]), bets = labels(["BET"])
        func controlAmount(_ labels: [Text]) -> Int? {
            guard labels.count == 1 else { return nil }
            let label = labels[0]
            if let dollar = label.value.firstIndex(of:"$") { return TableMoney.cents(String(label.value[dollar...])) }
            let lowerY = label.value == "CALL" ? label.bounds.y : label.bounds.rect.maxY
            let amounts = actionTexts.filter { abs($0.bounds.rect.midX-label.bounds.rect.midX) < width && $0.bounds.y >= lowerY && $0.bounds.y < label.bounds.rect.maxY+height*0.5 }.compactMap { TableMoney.cents($0.value) }
            return amounts.count == 1 ? amounts[0] : nil
        }
        let controls = TableControls(canFold:actionTexts.contains { $0.confidence >= 0.95 && $0.value.uppercased() == "FOLD" },canCheck:checks.count == 1,canCall:calls.count == 1,
                                     canBet:bets.count == 1,canRaise:raises.count == 1,raiseToCents:controlAmount(raises),betAmountCents:controlAmount(bets))
        let call = checks.count == 1 && calls.isEmpty ? 0 : checks.isEmpty ? controlAmount(calls) : nil
        return (controls,call)
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
