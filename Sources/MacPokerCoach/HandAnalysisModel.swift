import Foundation
import Combine
import PokerCore
import TableRecognition

@MainActor final class HandAnalysisModel: ObservableObject {
    typealias Calculate = @Sendable ([Card],[Card],Int,@escaping @Sendable () -> Bool) throws -> EquityResult
    @Published private(set) var result: EquityResult?
    @Published private(set) var opponents = 1
    @Published private(set) var calculating = false
    @Published private(set) var error: String?
    @Published var potText = ""
    @Published var callText = ""
    private struct Key: Equatable, Sendable { var hole: [Card]; var board: [Card]; var opponents: Int }
    private var key: Key?
    private var current: LiveHand?
    private var generation = UUID()
    private var worker: Task<EquityResult,Error>?
    private let calculate: Calculate

    init(calculate: @escaping Calculate = { hole,board,opponents,cancelled in
        try EquityEngine.calculate(hole:hole,board:board,opponents:opponents,cancelled:cancelled)
    }) { self.calculate = calculate }

    func setOpponents(_ count: Int) {
        guard (1...8).contains(count), count != opponents else { return }
        opponents = count; update(current)
    }
    func update(_ hand: LiveHand?) {
        current = hand
        let next = hand.map { Key(hole:$0.hole.map(\.card).sorted { $0.code < $1.code },board:$0.board.map(\.card).sorted { $0.code < $1.code },opponents:opponents) }
        guard next != key else { return }
        generation = UUID(); let token = generation
        worker?.cancel(); worker = nil; key = next
        result = nil; calculating = false; error = nil; potText = ""; callText = ""
        guard let next else { return }
        calculating = true
        let calculate = calculate
        let task = Task.detached(priority:.utility) {
            try calculate(next.hole,next.board,next.opponents,{ Task.isCancelled })
        }
        worker = task
        Task { [weak self] in
            let outcome = await task.result
            guard let self, self.generation == token else { return }
            self.worker = nil; self.calculating = false
            switch outcome {
            case .success(let result): self.result = result
            case .failure: self.error = "Analysis unavailable for this reading. Waiting for new cards."
            }
        }
    }
    var callEstimate: CallEstimate? {
        guard let result, let pot = Self.amount(potText), let call = Self.amount(callText) else { return nil }
        return try? CallEstimate(equity:result,potBeforeCall:pot,call:call)
    }
    var hasCards: Bool { key != nil }
    var amountHelp: String {
        if current == nil { return "Waiting for confirmed cards." }
        if potText.isEmpty || callText.isEmpty { return "Enter the current pot and your call amount for dollar EV." }
        guard let pot = Self.amount(potText), pot > 0, let call = Self.amount(callText), call >= 0,
              (pot+call).isFinite else { return "Use a positive pot and a nonnegative call in dollars, e.g. 1.50. No commas." }
        return "Pot includes the opponent's current bet and all earlier contributions; exclude your new call."
    }
    private static func amount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20, trimmed.allSatisfy({ "0123456789.".contains($0) }),
              let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
    deinit { worker?.cancel() }
}
