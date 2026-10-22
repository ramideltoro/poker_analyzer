import Foundation
import PokerCore

public struct LiveHand: Sendable {
    public var hole: [DetectedCard]
    public var board: [DetectedCard]
    public var timestamp: Date
    public var isReview: Bool
    public init(hole: [DetectedCard],board: [DetectedCard],timestamp: Date,isReview: Bool = false) {
        self.hole = hole; self.board = board; self.timestamp = timestamp; self.isReview = isReview
    }
    public var combination: String? {
        let cards = (hole+board).map(\.card)
        guard hole.count == 2, board.count >= 3, Set(cards).count == cards.count else { return nil }
        return Evaluator.evaluate(cards).name
    }
}
public struct HandSelection: Sendable {
    public var hole: [DetectedCard]
    public var board: [DetectedCard]
    public var issue: String?
}
public enum CardGrouping {
    static func select(_ cards: [DetectedCard],near anchor: [UnitRect]) -> HandSelection {
        guard anchor.count == 2 else { return select(cards) }
        var hole = [DetectedCard]()
        for slot in anchor {
            let matches = cards.filter { card in
                let b = card.bounds
                return (0.6...1.6).contains(b.height/slot.height) &&
                    abs(b.rect.midX-slot.rect.midX) < max(b.width,slot.width)*0.55 &&
                    abs(b.rect.midY-slot.rect.midY) < max(b.height,slot.height)*0.55
            }
            guard matches.count == 1, !hole.contains(matches[0]) else {
                // Reacquire a moved/resized table only with a comparable, nearby pair.
                let fresh = select(cards)
                if fresh.issue == nil, let first = fresh.hole.first {
                    let center = anchor.map { $0.rect.midX }.reduce(0,+)/2
                    let newCenter = fresh.hole.map { $0.bounds.rect.midX }.reduce(0,+)/2
                    if (0.6...1.6).contains(first.bounds.height/anchor[0].height),
                       abs(newCenter-center) < 0.18,
                       abs(first.bounds.rect.midY-anchor[0].rect.midY) < 0.18 { return fresh }
                }
                return HandSelection(hole:[],board:[],issue:"Scanning continuously · waiting for your next two readable cards…")
            }
            hole.append(matches[0])
        }
        let center = hole.map { $0.bounds.rect.midX }.reduce(0,+)/2
        let span = hole[1].bounds.rect.maxX-hole[0].bounds.x
        let height = hole.map { $0.bounds.height }.reduce(0,+)/2
        let top = hole.map { $0.bounds.y }.min()!
        let boardCandidates = cards.filter { card in
            !hole.contains(card) && (0.6...1.6).contains(card.bounds.height/height) &&
                abs(card.bounds.rect.midX-center) < span*2 &&
                card.bounds.rect.midY < top-height*0.2 && card.bounds.y > top-height*6
        }
        let rows = groups(boardCandidates)
        guard rows.count <= 1, rows.allSatisfy({ (3...5).contains($0.count) }) else {
            return HandSelection(hole:hole,board:[],issue:"Hole cards read; community cards are incomplete or changing.")
        }
        let board = rows.first ?? []
        guard Set((hole+board).map(\.card)).count == hole.count+board.count else {
            return HandSelection(hole:[],board:[],issue:"Duplicate card faces detected; scanning continues…")
        }
        return HandSelection(hole:hole,board:board,issue:nil)
    }
    /// Position is an assumption: one isolated two-card row below a possible 3–5 card board.
    public static func select(_ cards: [DetectedCard]) -> HandSelection {
        // Table previews and hand-history thumbnails may repeat the current cards.
        // Group only faces at a comparable scale to the largest readable faces.
        let largestHeight = cards.map { $0.bounds.height }.max() ?? 0
        let cards = cards.filter { $0.bounds.height >= largestHeight*0.6 }
        guard Set(cards.map(\.card)).count == cards.count else { return HandSelection(hole:[],board:[],issue:"Duplicate card faces detected; waiting for a clear table.") }
        let groups = groups(cards)
        let pairs = groups.filter { $0.count == 2 }, boards = groups.filter { (3...5).contains($0.count) }
        guard pairs.count == 1 else {
            return HandSelection(hole:[],board:[],issue:pairs.count > 1 ? "Multiple two-card groups visible. Keep one table visible." : "Searching for two readable cards together…")
        }
        guard boards.count <= 1, !groups.contains(where:{ $0.count > 5 }) else { return HandSelection(hole:[],board:[],issue:"Card layout is ambiguous. Keep one table visible.") }
        let pair = pairs[0], board = boards.first ?? []
        let center=pair.map { $0.bounds.rect.midX }.reduce(0,+)/2
        let span=pair[1].bounds.rect.maxX-pair[0].bounds.x
        if groups.contains(where:{ row in
            row.count<3 && row != pair && row.contains(where:{ $0.bounds.rect.midY<pair[0].bounds.y && abs($0.bounds.rect.midX-center)<span*2 })
        }) { return HandSelection(hole:pair,board:[],issue:"Hole cards read; community cards are incomplete or changing.") }
        if let first = board.first, pair[0].bounds.rect.midY <= first.bounds.rect.midY+first.bounds.height*0.3 {
            return HandSelection(hole:[],board:[],issue:"Cannot identify your cards below the board.")
        }
        return HandSelection(hole:pair,board:board,issue:nil)
    }
    /// Only full-size faces in the board area above the previously confirmed hero seat.
    public static func reviewBoard(_ cards: [DetectedCard],anchor: [UnitRect]) -> [DetectedCard]? {
        guard anchor.count == 2 else { return nil }
        let center = anchor.map { $0.rect.midX }.reduce(0,+)/2
        let height = anchor.map(\.height).reduce(0,+)/2
        let top = anchor.map(\.y).min()!
        let span = anchor[1].rect.maxX-anchor[0].x
        let candidates = cards.filter {
            (0.6...1.6).contains($0.bounds.height/height) &&
            abs($0.bounds.rect.midX-center) < span*2 &&
            $0.bounds.rect.midY < top-height*0.2 && $0.bounds.y > top-height*6
        }
        let rows = groups(candidates)
        guard rows.count <= 1, rows.allSatisfy({ (3...5).contains($0.count) }) else { return nil }
        let board = rows.first ?? []
        return Set(board.map(\.card)).count == board.count ? board : nil
    }
    private static func groups(_ cards: [DetectedCard]) -> [[DetectedCard]] {
        var rows = [[DetectedCard]]()
        for card in cards.sorted(by:{ $0.bounds.rect.midY < $1.bounds.rect.midY }) {
            if let index = rows.firstIndex(where:{ row in
                let reference = row[0].bounds
                return abs(reference.rect.midY-card.bounds.rect.midY) < max(reference.height,card.bounds.height)*0.42 &&
                    max(reference.height,card.bounds.height)/min(reference.height,card.bounds.height) < 1.6
            }) { rows[index].append(card) } else { rows.append([card]) }
        }
        var groups = [[DetectedCard]]()
        for row in rows {
            var cluster = [DetectedCard]()
            for card in row.sorted(by:{ $0.bounds.x < $1.bounds.x }) {
                if let previous = cluster.last, card.bounds.x-previous.bounds.rect.maxX > max(previous.bounds.width,card.bounds.width)*1.4 {
                    groups.append(cluster); cluster.removeAll()
                }
                cluster.append(card)
            }
            if !cluster.isEmpty { groups.append(cluster) }
        }
        return groups
    }
}
public struct ReadingStabilizer {
    private var previous: HandSelection?
    private var lastComplete: HandSelection?
    private var heroAnchor = [UnitRect]()
    private var boardAnchor = [UnitRect]()
    public private(set) var confirmedHole = [DetectedCard]()
    public var searchRegions: [UnitRect] { heroAnchor+boardAnchor }
    public var hasLayout: Bool { heroAnchor.count == 2 }
    public init() {}
    public mutating func reset(keepLayout: Bool = false) {
        previous = nil; confirmedHole=[]
        if !keepLayout { heroAnchor = []; boardAnchor = []; lastComplete=nil }
    }
    public mutating func accept(_ scan: CardScan) -> (LiveHand?,String) {
        var selection = CardGrouping.select(scan.cards,near:heroAnchor)
        if selection.issue != nil, let table = scan.table, table.trackingUsable, table.issue == nil,
           table.potCents != nil, let hero = table.hero, hero.activity == .active {
            let fresh = CardGrouping.select(scan.cards)
            if fresh.issue == nil, let first = fresh.hole.first {
                let center = fresh.hole.map { $0.bounds.rect.midX }.reduce(0,+)/2
                if abs(center-hero.bounds.rect.midX) < first.bounds.width*1.5,
                   hero.bounds.y >= first.bounds.y, hero.bounds.y < first.bounds.rect.maxY+first.bounds.height {
                    selection = fresh // still requires normal two-frame confirmation below
                }
            }
        }
        // Missing community-card OCR must not turn an existing flop into a new preflop hand.
        if selection.issue==nil, let old=lastComplete, old.hole.map(\.card)==selection.hole.map(\.card),
           selection.board.count<old.board.count {
            selection=HandSelection(hole:selection.hole,board:[],issue:"Hole cards read; confirming missing community cards from the current street.")
        }
        confirmedHole=[]
        if selection.hole.count==2, let old=previous, old.hole.map(\.card)==selection.hole.map(\.card),
           zip(old.hole,selection.hole).allSatisfy({ abs($0.bounds.x-$1.bounds.x)<0.05 && abs($0.bounds.y-$1.bounds.y)<0.05 }) {
            confirmedHole=selection.hole
        }
        defer { previous = selection }
        if let issue = selection.issue { return (nil,issue) }
        guard let old = previous, old.issue == nil,
              old.hole.map(\.card) == selection.hole.map(\.card), old.board.map(\.card) == selection.board.map(\.card),
              zip(old.hole,selection.hole).allSatisfy({ abs($0.bounds.x-$1.bounds.x) < 0.05 && abs($0.bounds.y-$1.bounds.y) < 0.05 }) else {
            return (nil,"Confirming the detected cards…")
        }
        lastComplete=selection
        heroAnchor = selection.hole.map(\.bounds)
        boardAnchor = selection.board.map(\.bounds)
        return (LiveHand(hole:selection.hole,board:selection.board,timestamp:scan.timestamp),"Scanning continuously · cards detected")
    }
}
