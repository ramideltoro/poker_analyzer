import Foundation

public struct RunoutDetails: Sendable {
    public let madeHand: String
    public let improvingCards: [Card]
    public let nextCardImprovement: Double?
    public let riverImprovement: Double?
    public let runouts: Int
    public init?(hole: [Card],board: [Card]) {
        let all = hole+board
        guard hole.count == 2, (3...5).contains(board.count), Set(all).count == all.count else { return nil }
        let current = Evaluator.evaluate(all)
        madeHand = current.name
        let unseen = (2...14).flatMap { r in Suit.allCases.map { Card(rank:r,suit:$0) } }.filter { !all.contains($0) }
        guard board.count < 5 else {
            improvingCards = []; nextCardImprovement = nil; riverImprovement = nil; runouts = 0; return
        }
        improvingCards = unseen.filter { Evaluator.evaluate(all+[$0]).category > current.category }
        nextCardImprovement = Double(improvingCards.count)/Double(unseen.count)
        var better = 0, total = 0
        if board.count == 4 {
            total = unseen.count; better = improvingCards.count
        } else {
            for i in 0..<unseen.count-1 { for j in i+1..<unseen.count {
                total += 1
                if Evaluator.evaluate(all+[unseen[i],unseen[j]]).category > current.category { better += 1 }
            } }
        }
        riverImprovement = Double(better)/Double(total); runouts = total
    }
}

public enum HandDetails {
    /// A deterministic best-five selection; equivalent selections may exist in tied hands.
    public static func bestFive(_ cards: [Card]) -> [Card] {
        guard (5...7).contains(cards.count), Set(cards).count == cards.count else { return [] }
        var best = [Card](), rank: HandRank?
        for a in 0..<cards.count-4 { for b in a+1..<cards.count-3 { for c in b+1..<cards.count-2 {
            for d in c+1..<cards.count-1 { for e in d+1..<cards.count {
                let selection = [cards[a],cards[b],cards[c],cards[d],cards[e]], value = Evaluator.evaluate(selection)
                if rank == nil || value > rank! { rank = value; best = selection }
            } }
        } } }
        return best.sorted { $0.rank == $1.rank ? $0.code < $1.code : $0.rank > $1.rank }
    }
    public static func startingClass(_ hole: [Card]) -> String? {
        guard hole.count == 2, Set(hole).count == 2 else { return nil }
        let sorted = hole.sorted { $0.rank > $1.rank }
        let ranks = sorted.map { String($0.code.prefix(1)) }.joined()
        return ranks + (sorted[0].rank == sorted[1].rank ? "" : sorted[0].suit == sorted[1].suit ? "s" : "o")
    }
    public static func texture(_ board: [Card]) -> String {
        guard board.count >= 3 else { return "Preflop · no community cards" }
        let rankCounts = Dictionary(grouping:board,by:\.rank).values.map(\.count)
        let suitCount = Dictionary(grouping:board,by:\.suit).values.map(\.count).max() ?? 0
        let pair = rankCounts.contains(4) ? "Four of a kind on board" : rankCounts.contains(3) && rankCounts.contains(2) ? "Full house on board" : rankCounts.contains(3) ? "Trips on board" : rankCounts.filter { $0 >= 2 }.count >= 2 ? "Two paired ranks" : rankCounts.contains(2) ? "Paired board" : "Unpaired board"
        let suits = suitCount >= 3 ? "\(suitCount) of one suit" : suitCount == 2 ? "Two of one suit" : "Rainbow"
        let ranks = Set(board.map(\.rank)); var wheel = ranks; if ranks.contains(14) { wheel.insert(1) }
        let connected = (5...14).map { high in (0..<5).filter { wheel.contains(high-$0) }.count }.max() ?? 0
        return "\(pair) · \(suits) · \(connected) distinct ranks within five"
    }
}

public struct ReferenceData: Decodable, Sendable {
    public struct Sample: Decodable, Sendable {
        public let known: Int
        public let river: Int
        public let categories: [Int]
        public var mostCommonFinish: String {
            guard river > 0, categories.count == 9, let best = categories.indices.max(by:{ categories[$0] < categories[$1] }) else { return "No completed-board samples" }
            let names = ["high card","one pair","two pair","three of a kind","straight","flush","full house","four of a kind","straight flush"]
            return "\(names[best]) (\(String(format:"%.1f",Double(categories[best])*100/Double(river)))%)"
        }
    }
    public let hands: Int
    public let flops: Int
    public let rivers: Int
    public let files: Int
    public let excludedVariants: Int
    public let invalidRevealedSamples: Int
    public let duplicateHandHQIDs: Int
    public let quarantinedRecords: Int
    public let conflictingGroups: Int
    public let rawHandHQ: Int
    public let uciRows: Int
    public let uciMismatches: Int
    public let sources: [String:Int]
    public let classes: [String:Sample]
    public static let shared: ReferenceData? = {
        let url = Bundle.main.url(forResource:"reference-data",withExtension:"json") ?? Bundle.module.url(forResource:"reference-data",withExtension:"json",subdirectory:"Resources")
        guard let url, let data = try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(ReferenceData.self,from:data)
    }()
}
