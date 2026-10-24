import PokerCore

/// Membership transcribed from Jonathan Little's illustrative cutoff cash-game chart,
/// Strategies for Beating Small Stakes Poker Cash Games, printed p.30 (PDF p.31).
/// The book's default examples are 100 BB; opponent-dependent adjustments are explicit in the source.
/// This is a reference opening range, not solved EV, a calling range or a short-stack push/fold chart.
enum CutoffOpeningChart {
    static let sourceURL="https://pokercoaching.com/wp-content/uploads/2022/06/Small-Stakes-Poker-Cash-Games.pdf#page=31"
    static let notation="22+, A2s+, K7s+, Q8s+, J8s+, T7s+, 98s, 97s, 87s, 86s, 76s, 75s, 65s, 64s, 54s, A2o+, K9o+, Q9o+, J9o+, T9o, T8o, 98o, 87o"
    static func contains(_ hole: [Card]) -> Bool {
        guard hole.count==2,Set(hole).count==2 else { return false }
        let h=max(hole[0].rank,hole[1].rank),l=min(hole[0].rank,hole[1].rank),suited=hole[0].suit==hole[1].suit
        if h==l || h==14 { return true }
        if suited {
            return h==13 && l>=7 || h==12 && l>=8 || h==11 && l>=8 || h==10 && l>=7 ||
                (5...9).contains(h) && (h-l==1 || h>=6 && h-l==2)
        }
        return (11...13).contains(h) && l>=9 || h==10 && l>=8 || (h==9 || h==8) && h-l==1
    }
}
