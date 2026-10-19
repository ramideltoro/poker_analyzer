import SwiftUI
import PokerCore

struct ShowdownOutcomePanel: View {
    let result: EquityResult?
    let current: Bool
    let height: CGFloat
    private var ringSize: CGFloat { min(148,max(72,height-48)) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("SHOWDOWN OUTCOME").sectionLabel()
                Spacer()
                Text("Win / tie / lose").font(.system(size:10)).foregroundStyle(.secondary)
            }.frame(height:14)
            HStack(spacing:22) {
                outcomeRing.frame(width:ringSize,height:ringSize)
                VStack(spacing:height >= 190 ? 18 : 8) {
                    legend("Win outright",result?.outcomes?.win,DashboardStyle.accent)
                    legend("Tie for best",result?.outcomes?.tie,DashboardStyle.cyan)
                    legend("Lose",result?.outcomes?.lose,DashboardStyle.loss)
                }.frame(maxWidth:.infinity)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).frame(height:height).dashboardPanel()
            .help("Win, tie and lose total 100%. A tie counts only when tied for best. Equity includes your fraction of tied pots.")
    }
    private var outcomeRing: some View {
        let win = max(0,min(1,result?.outcomes?.win ?? 0)), tie = max(0,min(1,result?.outcomes?.tie ?? 0))
        let ranges = [0.0,win,min(1,win+tie),result?.outcomes == nil ? 0 : 1]
        let colors = [DashboardStyle.accent,DashboardStyle.cyan,DashboardStyle.loss]
        return ZStack {
            Circle().stroke(Color.white.opacity(0.06),lineWidth:10)
            ForEach(0..<3,id:\.self) { i in
                Circle().trim(from:ranges[i],to:max(ranges[i],ranges[i+1]))
                    .stroke(colors[i].opacity(current ? 0.95 : 0.3),style:StrokeStyle(lineWidth:10,lineCap:.butt)).rotationEffect(.degrees(-90))
            }
            VStack(spacing:2) {
                Text(result?.outcomes.map { String(format:"%.1f%%",$0.win*100) } ?? "—").font(.system(size:ringSize >= 100 ? 24 : 17,weight:.semibold,design:.rounded)).monospacedDigit()
                Text("WIN OUTRIGHT").font(.system(size:7,weight:.medium)).foregroundStyle(.secondary)
            }.foregroundStyle(current ? .primary : .secondary)
        }.padding(6).accessibilityElement(children:.ignore)
            .accessibilityLabel("Win outright \(result?.outcomes.map { String(format:"%.1f percent",$0.win*100) } ?? "waiting")")
    }
    private func legend(_ title: String,_ value: Double?,_ color: Color) -> some View {
        HStack(spacing:7) {
            Circle().fill(color.opacity(current ? 1 : 0.35)).frame(width:6,height:6)
            Text(title).font(.system(size:height >= 190 ? 13 : 11)).foregroundStyle(.secondary)
            Spacer(minLength:5)
            Text(value.map { String(format:"%.1f%%",$0*100) } ?? "—")
                .font(.system(size:height >= 190 ? 18 : 13,weight:.medium,design:.monospaced)).monospacedDigit()
                .foregroundStyle(current ? .primary : .secondary).frame(width:65,alignment:.trailing)
        }.frame(height:height >= 190 ? 22 : 18)
    }
}

struct FinalHandPanel: View {
    let result: EquityResult?
    let current: Bool
    let height: CGFloat
    static let categories = ["High card","One pair","Two pair","Three of a kind","Straight","Flush","Full house","Four of a kind","Straight flush"]
    static let definitions = ["No pair or better in your best five cards.","Exactly one pair, with three other ranks.","Two distinct pairs.","Three of one rank, without a full house.","Five consecutive ranks, without a straight flush.","Five of one suit, without a straight flush.","Three of one rank plus a pair.","Four cards of one rank.","Five consecutive cards of one suit, including a royal flush."]
    private var rowHeight: CGFloat { max(12,min(30,(height-(height >= 270 ? 82 : 66))/9)) }
    var body: some View {
        VStack(alignment:.leading,spacing:height >= 270 ? 7 : 5) {
            Text("FINAL HAND · BY THE RIVER").sectionLabel().frame(height:14)
            VStack(spacing:1) {
                ForEach(0..<9,id:\.self) { i in
                    HStack(spacing:8) {
                        Text(Self.categories[i]).font(.system(size:height >= 270 ? 12 : 10)).frame(width:height >= 270 ? 112 : 90,alignment:.leading)
                        GeometryReader { g in
                            Capsule().fill(Color.white.opacity(0.065))
                            Capsule().fill(DashboardStyle.cyan.opacity(current ? 0.9 : 0.3)).frame(width:g.size.width*max(0,min(1,result?.categoryProbabilities[safe:i] ?? 0)))
                        }.frame(height:6)
                        Text(result?.categoryProbabilities[safe:i].map { String(format:"%.1f%%",$0*100) } ?? "—")
                            .font(.system(size:height >= 270 ? 13 : 10,weight:.medium,design:.monospaced)).monospacedDigit()
                            .foregroundStyle(current ? .primary : .secondary).frame(width:48,alignment:.trailing)
                    }.frame(height:rowHeight).contentTransition(.identity)
                        .help(Self.definitions[i])
                        .accessibilityElement(children:.combine)
                }
            }
            Text("Best five cards, including the board. A category does not guarantee a win.")
                .font(.system(size:height >= 270 ? 11 : 9)).foregroundStyle(.secondary).lineLimit(height >= 270 ? 2 : 1).frame(height:height >= 270 ? 24 : 12,alignment:.topLeading)
        }.padding(10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).frame(height:height).dashboardPanel()
    }
}
