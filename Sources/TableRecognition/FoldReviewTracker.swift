import Foundation

/// Saved cards are explicit counterfactual inputs, never a claim that hidden cards were re-read.
public struct FoldReviewTracker {
    private var saved: LiveHand?
    private var pendingBoard: [DetectedCard]?
    private var missing = 0
    private var ended = false
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func accept(live: LiveHand?,scan: CardScan) -> LiveHand? {
        if let live { saved = live; missing = 0; pendingBoard = nil; ended = false; return live }
        guard !ended, let saved else { return nil }
        let anchor = saved.hole.map(\.bounds)
        // A partially visible or newly dealt hero card needs normal confirmation.
        guard !scan.cards.contains(where:{ c in anchor.contains { $0.rect.intersects(c.bounds.rect) } }),
              let board = CardGrouping.reviewBoard(scan.cards,anchor:anchor),
              (scan.table?.hero?.activity == .folded || !board.isEmpty) else {
            missing = 0; pendingBoard = nil; return nil
        }
        let agrees = pendingBoard?.map(\.card) == board.map(\.card)
        pendingBoard = board; missing = agrees ? missing+1 : 1
        guard missing >= 2 else { return nil }
        let old = saved.board.map(\.card), next = board.map(\.card)
        guard next.count >= old.count, Array(next.prefix(old.count)) == old,
              Set((saved.hole+board).map(\.card)).count == saved.hole.count+board.count else {
            ended = true; return nil
        }
        let review = LiveHand(hole:saved.hole,board:board,timestamp:scan.timestamp,isReview:true)
        self.saved = review
        return review
    }
}
