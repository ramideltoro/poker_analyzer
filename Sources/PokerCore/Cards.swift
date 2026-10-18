import Foundation

public enum Suit: String, Codable, CaseIterable, Sendable {
    case clubs = "c", diamonds = "d", hearts = "h", spades = "s"
    public var symbol: String { switch self { case .clubs: return "♣"; case .diamonds: return "♦"; case .hearts: return "♥"; case .spades: return "♠" } }
    public var red: Bool { self == .hearts || self == .diamonds }
}

public struct Card: Hashable, Codable, Sendable, Identifiable {
    public let rank: Int
    public let suit: Suit
    public var id: String { code }
    public var code: String { "23456789TJQKA".map(String.init)[rank - 2] + suit.rawValue }
    public var display: String { code.dropLast() + suit.symbol }
    public init(rank: Int, suit: Suit) { precondition((2...14).contains(rank)); self.rank = rank; self.suit = suit }
    private enum CodingKeys: String, CodingKey { case rank, suit }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rank = try values.decode(Int.self, forKey: .rank); suit = try values.decode(Suit.self, forKey: .suit)
        guard (2...14).contains(rank) else { throw DecodingError.dataCorruptedError(forKey: .rank, in: values, debugDescription: "Card rank must be 2 through 14") }
    }
    public init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "10", with: "T")
        guard t.count == 2, let r = "23456789TJQKA".firstIndex(of: Character(t.prefix(1).uppercased())),
              let s = Suit(rawValue: String(t.suffix(1)).lowercased()) else { return nil }
        rank = "23456789TJQKA".distance(from: "23456789TJQKA".startIndex, to: r) + 2; suit = s
    }
}

public struct HandRank: Comparable, Equatable, Sendable {
    public let value: Int
    public let category: Int
    public var name: String { ["High card", "One pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"][category] }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

public enum Evaluator {
    // Evaluate 5–7 cards directly, selecting the best five within each category.
    public static func evaluate(_ cards: [Card]) -> HandRank {
        precondition((5...7).contains(cards.count) && Set(cards).count == cards.count)
        var counts = [Int](repeating: 0, count: 15)
        var suits = [Suit: [Int]]()
        for c in cards { counts[c.rank] += 1; suits[c.suit, default: []].append(c.rank) }
        let ranks = (2...14).reversed().filter { counts[$0] > 0 }
        func straight(_ values: [Int]) -> Int? {
            var set = Set(values); if set.contains(14) { set.insert(1) }
            for high in stride(from: 14, through: 5, by: -1) { if (0..<5).allSatisfy({ set.contains(high - $0) }) { return high } }
            return nil
        }
        func result(_ category: Int, _ kickers: [Int]) -> HandRank {
            var value = category
            for i in 0..<5 { value = value * 15 + (i < kickers.count ? kickers[i] : 0) }
            return HandRank(value: value, category: category)
        }
        let flush = suits.values.first { $0.count >= 5 }?.sorted(by: >)
        if let flush, let high = straight(flush) { return result(8, [high]) }
        if let quad = ranks.first(where: { counts[$0] == 4 }) { return result(7, [quad, ranks.first(where: { $0 != quad })!]) }
        let trips = ranks.filter { counts[$0] >= 3 }
        if let trip = trips.first, let pair = ranks.first(where: { $0 != trip && counts[$0] >= 2 }) { return result(6, [trip, pair]) }
        if let flush { return result(5, Array(flush.prefix(5))) }
        if let high = straight(ranks) { return result(4, [high]) }
        if let trip = trips.first { return result(3, [trip] + ranks.filter { $0 != trip }.prefix(2)) }
        let pairs = ranks.filter { counts[$0] >= 2 }
        if pairs.count >= 2 { return result(2, Array(pairs.prefix(2)) + [ranks.first(where: { !pairs.prefix(2).contains($0) })!]) }
        if let pair = pairs.first { return result(1, [pair] + ranks.filter { $0 != pair }.prefix(3)) }
        return result(0, Array(ranks.prefix(5)))
    }

}
