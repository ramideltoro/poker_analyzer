import Foundation
import PokerCore
import TableRecognition

enum PokerPosition: String, CaseIterable { case unknown="Not confirmed", early="Early", middle="Middle", hijack="Hijack", cutoff="Cutoff", button="Button", smallBlind="Small blind", bigBlind="Big blind" }
enum PreflopSituation: String, CaseIterable { case unknown="Not confirmed", firstIn="Everyone folded to me", limped="One or more limpers", raised="Facing a raise" }
struct PreflopContext {
    var position: PokerPosition = .unknown
    var situation: PreflopSituation = .unknown
    var bigBlindCents: Int?
    var source="User-confirmed first-in context"
    var automaticSituation=false
    /// Deliberately limited first-in cash-game heuristic. Never applied to limped/raised pots.
    func suggestion(hole: [Card],table: TableObservation) -> ActionAdvice? {
        guard hole.count==2, Set(hole).count==2, position != .unknown, situation == .firstIn,
              ![PokerPosition.smallBlind,.bigBlind].contains(position),
              let bb=bigBlindCents, bb>0, let hero=table.hero, hero.activity == .active,
              let stack=hero.stackCents, stack>=bb*50, table.issue==nil, !table.sidePots,
              let call=table.callCents, call>0, call<=bb, table.controls?.canCall==true,
              table.controls?.canRaise==true, let pot=table.potCents,
              pot >= bb, pot <= bb*2, // standard SB/BB, no antes/straddles or limpers
              table.seats.compactMap(\.betCents).allSatisfy({ $0<=bb }),
              !table.activeOpponents.isEmpty, table.activeOpponents.allSatisfy({ ($0.stackCents ?? 0)>=bb*50 && $0.revealedCards.isEmpty }) else { return nil }
        guard let open=Self.opens(hole:hole,position:position) else { return nil }
        guard open || table.controls?.canFold == true else { return nil }
        let name=HandDetails.startingClass(hole) ?? "This hand"
        return ActionAdvice(title:open ? "RAISE" : "FOLD",
            reason:"\(name), \(position.rawValue.lowercased()), folded to you: \(open ? "open-raise; choose a legal size on the table" : "outside this opening range"). \(position == .cutoff ? "Little cash-game cutoff chart (100 BB reference). " : "")\(source), ≥50 BB effective. Reference strategy; not solver EV.",
            kind:open ? .raise : .fold,basis:position == .cutoff ? "CUTOFF CASH CHART" : "FIRST-IN RULE")
    }
    static func opens(hole:[Card],position:PokerPosition) -> Bool? {
        guard hole.count==2, Set(hole).count==2 else { return nil }
        let sorted=hole.sorted { $0.rank>$1.rank }, h=sorted[0].rank, l=sorted[1].rank
        let suited=sorted[0].suit==sorted[1].suit, pair=h==l
        let open: Bool
        switch position {
        case .early: open = pair ? h>=7 : suited ? (h==14 && l>=10) || (h==13 && l>=12) : h==14 && l>=12
        case .middle: open = pair ? h>=5 : suited ? (h==14 && l>=8) || (h>=11 && l>=10) || (h==10 && l==9) : (h==14 && l>=11) || (h==13 && l==12)
        case .hijack: open = pair ? h>=4 : suited ? h==14 || (h>=11 && l>=10) || (h-l==1 && l>=8) : (h==14 && l>=10) || (h>=12 && l>=11)
        case .cutoff: open = CutoffOpeningChart.contains(hole)
        case .button: open = pair || (suited ? h==14 || h==13 || (h==12 && l>=6) || (h>=10 && l>=7) || (h-l<=2 && l>=4) : h==14 || (h==13 && l>=9) || (h>=10 && l>=9))
        default: return nil
        }
        return open
    }
}

import SwiftUI
struct PreflopSetup: View {
    @ObservedObject var analysis: HandAnalysisModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Optional assumptions").font(.headline)
            Text("\(analysis.positionSummary). Dealer + occupied/dealt seats must agree across two readings. Folded players still count; empty seats do not. Overrides are optional. An unrecognized position keeps a disclosed hijack fallback.").font(.caption).foregroundStyle(.secondary)
            Picker("Position override",selection:$analysis.position) { ForEach(PokerPosition.allCases,id:\.self) { Text($0 == .unknown ? "Automatic" : $0.rawValue).tag($0) } }.disabled(analysis.currentHand == nil || analysis.isReview)
            Picker("Preflop action",selection:$analysis.preflopSituation) { ForEach(PreflopSituation.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.disabled(analysis.currentHand == nil || analysis.isReview)
            HStack { Text("Big blind ($)"); TextField("e.g. 0.10",text:$analysis.bigBlindText).textFieldStyle(.roundedBorder) }
            Text("Detected big blind: \(analysis.recognizedBigBlind.map { String(format:"$%.2f",Double($0)/100) } ?? "unreadable") · prior action: \(analysis.effectiveSituation.rawValue)").font(.caption)
            Picker("Raiser assumption",selection:$analysis.raiseRange) { ForEach(RaiseRangePreset.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
            Text("Raise response: assumed \(analysis.raiseRange.range(reraised:false).notation); re-raise: \(analysis.raiseRange.range(reraised:true).notation). Other active players: \(OpponentRange.caller.notation). These are selectable scenario presets, not inferred player ranges.").font(.caption)
            Text(analysis.raiseResponseResult.map { "Raise simulation: \($0.samples.formatted()) deals; 95% individual sampling bound ±\(String(format:"%.2f",$0.samplingBound*100)) pp. Range and realization uncertainty are separate." } ?? "Raise-response target: 100,000 separate deals; approximately ±0.43 pp individual 95% sampling bound. Range uncertainty is separate.").font(.caption).foregroundStyle(.secondary)
            Text("Position discounts use 90% of range equity in cutoff/button, 75% elsewhere, or 80% if unknown. These are uncalibrated realization scenarios; all-in calls use full range equity when future betting is closed. Decisions exclude rake and solved future play.").font(.caption).foregroundStyle(.secondary)
            Text("First-in rules cover early/middle/hijack/cutoff/button at ≥50 BB effective, without antes or straddles. The cutoff chart includes 76s and 98s. Its source uses 100 BB examples and calls for opponent-dependent adjustments. Short/unreadable stacks produce a provisional plan. Choose a legal client raise size.").font(.caption)
            CutoffChartView(hole:analysis.currentHand?.hole.map(\.card) ?? [])
            Text("These are conservative cash-game heuristics, not solver solutions. A range-based response covers supported visible preflop raises; general limping and blind-defense charts are not implemented. A narrow postflop value-raise rule uses limped-pot context. Position does not change raw showdown equity; it changes how a hand can be played. Postflop dollar EV still excludes future bets, actual ranges and rake.").font(.caption).foregroundStyle(.secondary)
            Link("Starting hands & position · PokerStars Learn",destination:URL(string:"https://www.pokerstars.com/poker/learn/lesson/poker-starting-hands/")!).font(.caption)
        }.fixedSize(horizontal:false,vertical:true).preferredColorScheme(.dark)
    }
}
