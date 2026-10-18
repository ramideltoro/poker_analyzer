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
    @Published private(set) var automatic = true
    @Published private(set) var table: TableObservation?
    @Published private(set) var tableConfirmed = false
    @Published var potText = ""
    @Published var callText = ""
    private struct CardsKey: Equatable { var hole: [Card]; var board: [Card] }
    private struct Key: Equatable, Sendable { var hole: [Card]; var board: [Card]; var opponents: Int }
    private var cardsKey: CardsKey?
    private var key: Key?
    private var current: LiveHand?
    private var tableStabilizer = TableReadingStabilizer()
    private var generation = UUID()
    private var worker: Task<EquityResult,Error>?
    private let calculate: Calculate

    init(calculate: @escaping Calculate = { hole,board,opponents,cancelled in
        try EquityEngine.calculate(hole:hole,board:board,opponents:opponents,cancelled:cancelled)
    }) { self.calculate = calculate }

    func setAutomatic(_ enabled: Bool) {
        guard enabled != automatic else { return }
        automatic = enabled; potText = ""; callText = ""
        invalidate(); refreshAnalysis()
    }
    func setOpponents(_ count: Int) {
        guard !automatic, (1...8).contains(count), count != opponents else { return }
        opponents = count; potText = ""; callText = ""; refreshAnalysis()
    }
    func update(_ hand: LiveHand?,table reading: TableObservation? = nil) {
        current = hand
        let next = hand.map { CardsKey(hole:$0.hole.map(\.card).sorted { $0.code < $1.code },board:$0.board.map(\.card).sorted { $0.code < $1.code }) }
        if next != cardsKey {
            cardsKey = next; potText = ""; callText = ""; tableStabilizer.reset()
        }
        if hand == nil { table = nil; tableConfirmed = false; tableStabilizer.reset() }
        else {
            table = reading
            tableConfirmed = tableStabilizer.accept(reading) != nil
            if automatic, tableConfirmed, let reading, validOpponentCount(reading) {
                opponents = reading.activeOpponents.count
            }
        }
        refreshAnalysis()
    }
    private func validOpponentCount(_ table: TableObservation) -> Bool {
        table.seats.filter(\.isHero).count == 1 && (2...9).contains(table.seats.count) &&
        table.seats.allSatisfy { $0.activity != .unknown } && (1...8).contains(table.activeOpponents.count)
    }
    private func invalidate() {
        generation = UUID(); worker?.cancel(); worker = nil; key = nil
        result = nil; calculating = false; error = nil
    }
    private func refreshAnalysis() {
        var next: Key?
        if let cardsKey {
            if !automatic || (table.map { validOpponentCount($0) && $0.activeOpponents.count == opponents } == true && (tableConfirmed || key != nil)) {
                next = Key(hole:cardsKey.hole,board:cardsKey.board,opponents:opponents)
            }
        }
        guard next != key else { return }
        invalidate(); key = next
        guard let next else { return }
        let token = generation, calculate = calculate
        calculating = true
        let task = Task.detached(priority:.utility) { try calculate(next.hole,next.board,next.opponents,{ Task.isCancelled }) }
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
    var automaticContext: StackCallContext? {
        guard automatic, tableConfirmed, let table, table.incompleteReason == nil,
              let pot = table.potCents, let quoted = table.callCents, let stack = table.hero?.stackCents else { return nil }
        var uncapped = quoted
        if quoted >= stack {
            // Some clients cap the Call label at hero's stack. Both visible street bets must resolve the true gap.
            guard table.activeOpponents.count == 1, let ownBet = table.hero?.betCents,
                  let opponentBet = table.activeOpponents.first?.betCents else { return nil }
            uncapped = max(0,opponentBet-ownBet)
            guard quoted == min(uncapped,stack) || quoted == uncapped else { return nil }
        }
        return try? StackCallContext(potCents:pot,uncappedCallCents:uncapped,heroStackCents:stack,
                                    opponentStackCents:table.activeOpponents.compactMap(\.stackCents),sidePots:table.sidePots)
    }
    var callEstimate: CallEstimate? {
        guard let result else { return nil }
        if automatic { return try? automaticContext?.estimate(result) }
        guard let pot = Self.amount(potText), let call = Self.amount(callText) else { return nil }
        return try? CallEstimate(equity:result,potBeforeCall:pot,call:call)
    }
    var hasCards: Bool { current != nil }
    var amountHelp: String {
        guard current != nil else { return "Waiting for confirmed cards." }
        if automatic {
            guard let table else { return "Analysis incomplete · waiting for pot, stacks and action controls." }
            guard tableConfirmed else { return "Confirming table amounts and player activity across consecutive frames…" }
            if let issue = table.incompleteReason { return "Analysis incomplete · "+issue }
            guard automaticContext != nil else { return "Analysis incomplete · need both current bets to resolve an all-in call." }
            return "Pot, remaining stacks, active opponents and call amount read from the table."
        }
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
