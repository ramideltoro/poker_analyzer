import SwiftUI
import PokerCore

struct CutoffChartView: View {
    var hole: [Card]
    private let ranks=Array((2...14).reversed())
    private func cards(_ row: Int,_ col: Int) -> [Card] {
        [Card(rank:max(row,col),suit:.hearts),Card(rank:min(row,col),suit:row>col ? .hearts : .spades)]
    }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("Cutoff · unopened cash pot").font(.subheadline.bold())
            Text("Blue: reference open-raise · gray: fold · outline: your hand").font(.caption2).foregroundStyle(.secondary)
            Grid(horizontalSpacing:2,verticalSpacing:2) {
                ForEach(ranks,id:\.self) { row in
                    GridRow { ForEach(ranks,id:\.self) { col in
                        let c=cards(row,col),name=HandDetails.startingClass(c) ?? ""
                        let selected=HandDetails.startingClass(hole)==name
                        Text(name).font(.system(size:8,weight:.medium,design:.monospaced)).frame(maxWidth:.infinity).frame(height:20)
                            .background(CutoffOpeningChart.contains(c) ? DashboardStyle.cyan.opacity(0.35) : Color.gray.opacity(0.18),in:RoundedRectangle(cornerRadius:3))
                            .overlay(RoundedRectangle(cornerRadius:3).stroke(selected ? Color.white : Color.clear,lineWidth:2))
                            .accessibilityLabel("\(name): \(CutoffOpeningChart.contains(c) ? "open-raise" : "fold")\(selected ? ", your hand" : "")")
                    } }
                }
            }
            Link("Jonathan Little · cash-game cutoff chart, p.30",destination:URL(string:CutoffOpeningChart.sourceURL)!).font(.caption)
            Text("Reference range for first-in decisions. It does not prescribe calling a raise or guarantee profit. The other position ranges remain local heuristics.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
