import Foundation

public enum EquityError: Error { case invalidCards, invalidOpponents, invalidSamples, invalidAmounts, cancelled }

public struct ShowdownProbabilities: Equatable, Sendable {
    public let win: Double
    public let tie: Double
    public let lose: Double
    public init(win: Double,tie: Double,lose: Double) { self.win = win; self.tie = tie; self.lose = lose }
}

public struct EquityResult: Equatable, Sendable {
    public let equity: Double
    public let samplingBound: Double
    public let samples: Int
    public let exact: Bool
    public let outcomes: ShowdownProbabilities?
    /// Mutually exclusive best-five-card categories, high card through straight flush.
    public let categoryProbabilities: [Double]
    public var lower: Double { max(0,equity-samplingBound) }
    public var upper: Double { min(1,equity+samplingBound) }
    public init(equity: Double,samplingBound: Double,samples: Int,exact: Bool,outcomes: ShowdownProbabilities? = nil,categoryProbabilities: [Double] = []) {
        self.equity = equity; self.samplingBound = samplingBound; self.samples = samples; self.exact = exact
        self.outcomes = outcomes; self.categoryProbabilities = categoryProbabilities
    }
}

public struct CallEstimate: Equatable, Sendable {
    public let value: Double
    public let lower: Double
    public let upper: Double
    public let requiredEquity: Double
    /// Incremental value relative to folding; pot includes all money already in it.
    /// Assumes no later bets, no rake and one shared pot with equal eligibility.
    public init(equity: EquityResult,potBeforeCall: Double,call: Double) throws {
        let total = potBeforeCall+call
        guard potBeforeCall.isFinite, potBeforeCall > 0, call.isFinite, call >= 0, total.isFinite,
              equity.equity.isFinite, (0...1).contains(equity.equity),
              equity.samplingBound.isFinite, equity.samplingBound >= 0 else { throw EquityError.invalidAmounts }
        value = equity.equity*total-call
        lower = equity.lower*total-call; upper = equity.upper*total-call
        requiredEquity = call/total
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

public enum EquityEngine {
    private static let deck = Suit.allCases.flatMap { suit in (2...14).map { Card(rank:$0,suit:suit) } }

    /// All legal opponent hole-card combinations are equally likely. No betting-range inference.
    public static func calculate(hole: [Card],board: [Card],opponents: Int,samples: Int = 12_000,
                                 seed: UInt64 = UInt64.random(in:1...UInt64.max),exactRiver: Bool = true,
                                 cancelled: @Sendable () -> Bool = { false }) throws -> EquityResult {
        let known = hole+board
        guard hole.count == 2, [0,3,4,5].contains(board.count), Set(known).count == known.count else { throw EquityError.invalidCards }
        guard (1...8).contains(opponents) else { throw EquityError.invalidOpponents }
        guard samples > 0 else { throw EquityError.invalidSamples }
        var available = deck.filter { !known.contains($0) }
        if board.count == 5 && opponents == 1 && exactRiver {
            let hero = Evaluator.evaluate(hole+board)
            var sum = 0.0, count = 0, wins = 0, ties = 0
            for i in 0..<(available.count-1) { for j in (i+1)..<available.count {
                if count%32 == 0 && cancelled() { throw EquityError.cancelled }
                let other = Evaluator.evaluate([available[i],available[j]]+board)
                sum += hero > other ? 1 : hero == other ? 0.5 : 0
                if hero > other { wins += 1 }; if hero == other { ties += 1 }
                count += 1
            } }
            var categories = [Double](repeating:0,count:9); categories[hero.category] = 1
            return EquityResult(equity:sum/Double(count),samplingBound:0,samples:count,exact:true,
                                outcomes:ShowdownProbabilities(win:Double(wins)/Double(count),tie:Double(ties)/Double(count),lose:Double(count-wins-ties)/Double(count)),categoryProbabilities:categories)
        }
        var rng = SplitMix(state:seed), sum = 0.0
        var wins = 0, ties = 0, categories = [Int](repeating:0,count:9)
        let missing = 5-board.count, needed = missing+opponents*2
        for sample in 0..<samples {
            if sample%64 == 0 && cancelled() { throw EquityError.cancelled }
            // Partial Fisher–Yates draws a uniform deal without replacement.
            for i in 0..<needed { available.swapAt(i,Int.random(in:i..<available.count,using:&rng)) }
            let runout = board+available.prefix(missing)
            let hero = Evaluator.evaluate(hole+runout)
            categories[hero.category] += 1
            var tied = 1, lost = false
            for opponent in 0..<opponents {
                let offset = missing+opponent*2
                let other = Evaluator.evaluate([available[offset],available[offset+1]]+runout)
                if other > hero { lost = true; break }
                if other == hero { tied += 1 }
            }
            if !lost {
                sum += 1/Double(tied)
                if tied == 1 { wins += 1 } else { ties += 1 }
            }
        }
        // Two-sided 95% Hoeffding bound for bounded pot shares [0,1].
        let bound = sqrt(log(40)/(2*Double(samples)))
        return EquityResult(equity:sum/Double(samples),samplingBound:bound,samples:samples,exact:false,
                            outcomes:ShowdownProbabilities(win:Double(wins)/Double(samples),tie:Double(ties)/Double(samples),lose:Double(samples-wins-ties)/Double(samples)),
                            categoryProbabilities:categories.map { Double($0)/Double(samples) })
    }

    public static func showdownShare(hole: [Card],board: [Card],villains: [[Card]]) throws -> Double {
        let known = hole+board+villains.flatMap { $0 }
        guard hole.count == 2, board.count == 5, !villains.isEmpty, villains.count <= 8,
              villains.allSatisfy({ $0.count == 2 }), Set(known).count == known.count else { throw EquityError.invalidCards }
        let hero = Evaluator.evaluate(hole+board), others = villains.map { Evaluator.evaluate($0+board) }
        if others.contains(where:{ $0 > hero }) { return 0 }
        return 1/Double(1+others.filter { $0 == hero }.count)
    }
}
