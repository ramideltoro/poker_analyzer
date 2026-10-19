import SwiftUI
import PokerCore

struct ProbabilityCharts: View {
    let result: EquityResult?
    let requiredEquity: Double?
    let equityCurrent: Bool
    let estimateCurrent: Bool
    static let categories: [(String,String)] = [
        ("High card","No pair or better in your best five cards."),
        ("One pair","Exactly one pair, with three other ranks."),
        ("Two pair","Two different pairs and one other card."),
        ("Three of a kind","Three of one rank, without a full house."),
        ("Straight","Five consecutive ranks, without a straight flush."),
        ("Flush","Five of one suit, without a straight flush."),
        ("Full house","Three of one rank plus a pair."),
        ("Four of a kind","Four cards of one rank."),
        ("Straight flush","Five consecutive cards of one suit; includes a royal flush.")]
    var body: some View {
        HStack(alignment:.top,spacing:16) {
            VStack(alignment:.leading,spacing:8) {
                Text("SHOWDOWN OUTCOME").font(.system(size:10,weight:.semibold)).tracking(1)
                probabilityRow("Win outright",result?.outcomes?.win,color:.mint,current:equityCurrent,detail:"Finish ahead of every opponent and take the entire shared pot.")
                probabilityRow("Tie for best",result?.outcomes?.tie,color:.cyan,current:equityCurrent,detail:"Share first place. Equity counts only your fraction of the split pot.")
                probabilityRow("Lose",result?.outcomes?.lose,color:Color(red:0.95,green:0.46,blue:0.48),current:equityCurrent,detail:"At least one opponent finishes with a better hand.")
                axis
                Text("Win, tie and lose add to 100%. A tied hand beaten by another player counts as a loss.").font(.caption2).foregroundStyle(.secondary).frame(height:40,alignment:.top)
                Divider()
                probabilityRow("Pot share",result?.equity,color:.mint,current:equityCurrent,detail:"Average fraction of the pot you receive, counting split pots fairly. This is showdown equity.")
                probabilityRow("Call threshold",requiredEquity,color:.orange,current:estimateCurrent,detail:"Equity needed for a zero-dollar call EV: call ÷ (eligible pot + call). This is a cost threshold, not an outcome probability.")
                Text("Pot share includes split-pot fractions. Call threshold is the break-even requirement for the displayed call.").font(.caption2).foregroundStyle(.secondary).frame(height:44,alignment:.top)
            }.chartPanel()
            VStack(alignment:.leading,spacing:8) {
                Text("YOUR FINAL HAND · BY THE RIVER").font(.system(size:10,weight:.semibold)).tracking(1)
                ForEach(0..<9,id:\.self) { i in
                    probabilityRow(Self.categories[i].0,result?.categoryProbabilities[safe:i],color:.cyan,current:equityCurrent,detail:Self.categories[i].1)
                }
                axis
                Text("Exactly one best-five-card category per deal, using your cards and the board. These add to 100%; making a category does not guarantee winning.").font(.caption2).foregroundStyle(.secondary).frame(height:44,alignment:.top)
            }.chartPanel()
        }.frame(height:366,alignment:.top)
    }
    private var axis: some View {
        HStack { Text("0%"); Spacer(); Text("50%"); Spacer(); Text("100%") }
            .font(.system(size:9,design:.monospaced)).foregroundStyle(.tertiary).padding(.leading,114).padding(.trailing,52).frame(height:10)
    }
    private func probabilityRow(_ label: String,_ value: Double?,color: Color,current: Bool,detail: String) -> some View {
        HStack(spacing:8) {
            Text(label).font(.system(size:11)).frame(width:106,alignment:.leading)
            GeometryReader { geometry in
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color.opacity(current ? 0.85 : 0.3))
                    .frame(width:geometry.size.width*max(0,min(1,value ?? 0)))
            }.frame(height:8)
            Text(value.map { String(format:"%.1f%%",$0*100) } ?? "—")
                .font(.system(size:11,weight:.medium,design:.monospaced)).monospacedDigit()
                .foregroundStyle(current ? .primary : .secondary).frame(width:44,alignment:.trailing).contentTransition(.identity)
        }.frame(height:20).help(detail).accessibilityElement(children:.ignore)
            .accessibilityLabel("\(label): \(value.map { String(format:"%.1f percent",$0*100) } ?? "waiting"). \(detail)\(current ? "" : " Previous reading, updating.")")
    }
}
private extension View {
    func chartPanel() -> some View {
        self.padding(14).frame(maxWidth:.infinity,alignment:.topLeading).frame(height:366,alignment:.top)
            .background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
    }
}
