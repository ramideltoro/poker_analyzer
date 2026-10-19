import SwiftUI
import PokerCore

struct ProbabilityCharts: View {
    let result: EquityResult?
    let requiredEquity: Double?
    let equityCurrent: Bool
    let estimateCurrent: Bool
    static let categories: [(String,String)] = [
        ("High card","No pair or better in your best five cards."),("One pair","Exactly one pair, with three other ranks."),
        ("Two pair","Two different pairs and one other card."),("Three of a kind","Three of one rank, without a full house."),
        ("Straight","Five consecutive ranks, without a straight flush."),("Flush","Five of one suit, without a straight flush."),
        ("Full house","Three of one rank plus a pair."),("Four of a kind","Four cards of one rank."),
        ("Straight flush","Five consecutive cards of one suit; includes a royal flush.")]
    var body: some View {
        HStack(spacing:10) {
            outcomesPanel
            categoriesPanel
        }.frame(height:DashboardStyle.chartHeight)
    }
    private var outcomesPanel: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("SHOWDOWN OUTCOME").sectionLabel()
            HStack(spacing:15) {
                outcomeRing.frame(width:94,height:94)
                VStack(spacing:10) {
                    legend("Win",result?.outcomes?.win,DashboardStyle.accent,detail:"Finish ahead of all opponents and take the whole shared pot.")
                    legend("Tie",result?.outcomes?.tie,DashboardStyle.cyan,detail:"Tie for first. Equity receives only your fraction of the split pot.")
                    legend("Lose",result?.outcomes?.lose,DashboardStyle.loss,detail:"At least one opponent finishes ahead of you.")
                }.frame(maxWidth:.infinity)
            }.frame(height:98)
            Divider().overlay(Color.white.opacity(0.025))
            probabilityRow("Pot share",result?.equity,color:DashboardStyle.accent,current:equityCurrent,detail:"Your average share of the pot, including ties. This is showdown equity.")
            probabilityRow("Call threshold",requiredEquity,color:.orange,current:estimateCurrent,detail:"Break-even calling equity: call ÷ (eligible pot + call). This is a cost threshold, not an outcome probability.")
            Text("Random legal opponent hands.\nA tie counts only when tied for best.")
                .font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2).frame(height:25,alignment:.topLeading)
        }.padding(12).frame(maxWidth:.infinity,alignment:.topLeading).frame(height:DashboardStyle.chartHeight).dashboardPanel()
    }
    private var outcomeRing: some View {
        let win = max(0,min(1,result?.outcomes?.win ?? 0))
        let tie = max(0,min(1,result?.outcomes?.tie ?? 0))
        let colors = [DashboardStyle.accent,DashboardStyle.cyan,DashboardStyle.loss]
        let ranges = [0.0,win,min(1,win+tie),result?.outcomes == nil ? 0 : 1]
        return ZStack {
            Circle().stroke(Color.white.opacity(0.06),lineWidth:10)
            ForEach(0..<3,id:\.self) { i in
                Circle().trim(from:ranges[i],to:max(ranges[i],ranges[i+1]))
                    .stroke(colors[i].opacity(equityCurrent ? 0.95 : 0.3),style:StrokeStyle(lineWidth:10,lineCap:.butt)).rotationEffect(.degrees(-90))
            }
            VStack(spacing:2) {
                Text(result?.outcomes.map { String(format:"%.1f%%",$0.win*100) } ?? "—")
                    .font(.system(size:18,weight:.semibold,design:.rounded)).monospacedDigit()
                Text("WIN OUTRIGHT").font(.system(size:7,weight:.medium)).foregroundStyle(.secondary).tracking(0.4)
            }.foregroundStyle(equityCurrent ? .primary : .secondary)
        }.padding(6).accessibilityElement(children:.ignore)
            .accessibilityLabel("Win outright \(result?.outcomes.map { String(format:"%.1f percent",$0.win*100) } ?? "waiting")")
    }
    private func legend(_ title: String,_ value: Double?,_ color: Color,detail: String) -> some View {
        HStack(spacing:6) {
            Circle().fill(color.opacity(equityCurrent ? 1 : 0.35)).frame(width:6,height:6)
            Text(title).font(.system(size:10)).foregroundStyle(.secondary)
            Spacer(minLength:4)
            Text(value.map { String(format:"%.1f%%",$0*100) } ?? "—").font(.system(size:11,weight:.medium,design:.monospaced))
                .foregroundStyle(equityCurrent ? .primary : .secondary).frame(width:46,alignment:.trailing)
        }.frame(height:16).help(detail)
    }
    private var categoriesPanel: some View {
        VStack(alignment:.leading,spacing:7) {
            Text("FINAL HAND · BY THE RIVER").sectionLabel()
            VStack(spacing:2) {
                ForEach(0..<9,id:\.self) { i in
                    probabilityRow(Self.categories[i].0,result?.categoryProbabilities[safe:i],color:DashboardStyle.cyan,current:equityCurrent,detail:Self.categories[i].1)
                }
            }
            HStack { Text("0%"); Spacer(); Text("50%"); Spacer(); Text("100%") }
                .font(.system(size:8,design:.monospaced)).foregroundStyle(.tertiary).padding(.leading,97).padding(.trailing,45).frame(height:9)
            Text("Best five cards, including the board.\nMaking a category does not guarantee a win.")
                .font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2).frame(height:25,alignment:.topLeading)
        }.padding(12).frame(maxWidth:.infinity,alignment:.topLeading).frame(height:DashboardStyle.chartHeight).dashboardPanel()
    }
    private func probabilityRow(_ label: String,_ value: Double?,color: Color,current: Bool,detail: String) -> some View {
        HStack(spacing:6) {
            Text(label).font(.system(size:10)).frame(width:91,alignment:.leading)
            GeometryReader { geometry in
                Capsule().fill(Color.white.opacity(0.065))
                Capsule().fill(color.opacity(current ? 0.9 : 0.3)).frame(width:geometry.size.width*max(0,min(1,value ?? 0)))
            }.frame(height:5)
            Text(value.map { String(format:"%.1f%%",$0*100) } ?? "—")
                .font(.system(size:10,weight:.medium,design:.monospaced)).monospacedDigit()
                .foregroundStyle(current ? .primary : .secondary).frame(width:39,alignment:.trailing).contentTransition(.identity)
        }.frame(height:15).help(detail).accessibilityElement(children:.ignore)
            .accessibilityLabel("\(label): \(value.map { String(format:"%.1f percent",$0*100) } ?? "waiting"). \(detail)\(current ? "" : " Previous reading.")")
    }
}
