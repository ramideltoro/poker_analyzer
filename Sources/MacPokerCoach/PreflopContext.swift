import Foundation
import PokerCore
import TableRecognition

enum PokerPosition: String, CaseIterable { case unknown="Not confirmed", early="Early", middle="Middle", hijack="Hijack", cutoff="Cutoff", button="Button", smallBlind="Small blind", bigBlind="Big blind" }
enum PreflopSituation: String, CaseIterable { case unknown="Not confirmed", firstIn="Everyone folded to me", limped="One or more limpers", raised="Facing a raise" }
struct PreflopContext {
    var position: PokerPosition = .unknown
    var situation: PreflopSituation = .unknown
    var bigBlindCents: Int?
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
        let sorted=hole.sorted { $0.rank>$1.rank }, h=sorted[0].rank, l=sorted[1].rank
        let suited=sorted[0].suit==sorted[1].suit, pair=h==l
        let open: Bool
        switch position {
        case .early: open = pair ? h>=7 : suited ? (h==14 && l>=10) || (h==13 && l>=12) : h==14 && l>=12
        case .middle: open = pair ? h>=5 : suited ? (h==14 && l>=8) || (h>=11 && l>=10) || (h==10 && l==9) : (h==14 && l>=11) || (h==13 && l==12)
        case .hijack: open = pair ? h>=4 : suited ? h==14 || (h>=11 && l>=10) || (h-l==1 && l>=8) : (h==14 && l>=10) || (h>=12 && l>=11)
        case .cutoff: open = pair || (suited ? h==14 || (h==13 && l>=8) || (h>=11 && l>=9) || (h==10 && l>=8) || (h-l==1 && l>=4) : (h==14 && l>=8) || (h>=11 && l>=10))
        case .button: open = pair || (suited ? h==14 || h==13 || (h==12 && l>=6) || (h>=10 && l>=7) || (h-l<=2 && l>=4) : h==14 || (h==13 && l>=9) || (h>=10 && l>=9))
        default: return nil
        }
        guard open || table.controls?.canFold == true else { return nil }
        let name=HandDetails.startingClass(hole) ?? "This hand"
        return ActionAdvice(title:open ? "RAISE" : "FOLD",
            reason:"\(name), \(position.rawValue.lowercased()), folded to you: \(open ? "open-raise; choose a legal size on the table" : "outside this conservative opening range"). User-confirmed first-in context, ≥50 BB effective. Cash-game heuristic; not solver EV.",
            kind:open ? .raise : .fold,basis:"FIRST-IN RULE")
    }
}

import SwiftUI
struct PreflopSetup: View {
    @ObservedObject var analysis: HandAnalysisModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Position & preflop context").font(.headline)
            Text("Confirm for this hand. Position and prior action clear on a new detected hand; the big blind stays until capture resets.").font(.caption).foregroundStyle(.secondary)
            Picker("Your position",selection:$analysis.position) { ForEach(PokerPosition.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.disabled(analysis.currentHand?.board.isEmpty != true || analysis.isReview)
            Picker("Before you",selection:$analysis.preflopSituation) { ForEach(PreflopSituation.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.disabled(analysis.currentHand?.board.isEmpty != true || analysis.isReview)
            HStack { Text("Big blind ($)"); TextField("e.g. 0.10",text:$analysis.bigBlindText).textFieldStyle(.roundedBorder) }
            Text("First-in rules cover early/middle/hijack/cutoff/button at ≥50 BB effective, without antes or straddles. 98s is included in the cutoff opening range. Choose a legal raise size on the table.").font(.caption)
            Text("These are conservative cash-game heuristics, not solver solutions. Limped, raised, short-stack and blind-defense strategies are not implemented. Position does not change raw showdown equity; it changes how a hand can be played. Postflop dollar EV still excludes future bets, actual ranges and rake.").font(.caption).foregroundStyle(.secondary)
            Link("Starting hands & position · PokerStars Learn",destination:URL(string:"https://www.pokerstars.com/poker/learn/lesson/poker-starting-hands/")!).font(.caption)
        }.fixedSize(horizontal:false,vertical:true).preferredColorScheme(.dark)
    }
}
