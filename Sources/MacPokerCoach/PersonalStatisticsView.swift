import SwiftUI
import TableRecognition

func statPercent(_ value: Double?) -> String { value.map { String(format:"%.0f%%",$0*100) } ?? "—" }
func statDollars(_ cents: Int?,signed: Bool = false) -> String { cents.map { String(format:signed ? "%+.2f USD" : "$%.2f",Double($0)/100) } ?? "—" }

struct PersonalStatisticsView: View {
    @ObservedObject var tracking: PlayTracking
    var height: CGFloat
    var showHistory: () -> Void
    @State private var definitions = false
    var body: some View {
        let stats = PersonalStatistics(archive:tracking.archive), actions = stats.actions
        let chartHeight = max(160,(height-24)*0.34)
        let detailsHeight = height-24-30-68-chartHeight-32-40
        VStack(spacing:10) {
            HStack {
                VStack(alignment:.leading,spacing:2) {
                    Text("My statistics").font(.system(size:21,weight:.semibold,design:.rounded))
                    Text("All saved play · \(tracking.archive.tables.count) table sessions · \(tracking.archive.hands.count) observed hands").font(.system(size:10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { definitions.toggle() } label: { Image(systemName:"questionmark.circle") }.buttonStyle(.plain)
                    .popover(isPresented:$definitions) { StatisticsDefinitions().padding(20).frame(width:440) }
                Button("Hand history & cash changes",action:showHistory).controlSize(.small)
            }.frame(height:30)
            HStack(spacing:10) {
                tile("Observed net",statDollars(tracking.totalNetCents,signed:true),"Measured checkpoints only",color:(tracking.totalNetCents ?? 0) >= 0 ? DashboardStyle.accent : DashboardStyle.loss)
                tile("Gross won",statDollars(stats.measured.isEmpty ? nil : stats.grossWon),"Sum of positive measured results",color:DashboardStyle.accent)
                tile("Gross lost",statDollars(stats.measured.isEmpty ? nil : stats.grossLost),"Sum of negative measured results",color:DashboardStyle.loss)
                tile("Won / lost / even","\(stats.wins) / \(stats.losses) / \(stats.even)","\(stats.measured.count) measured · \(tracking.archive.hands.count-stats.measured.count) unmeasured")
            }.frame(height:68)
            HStack(spacing:10) {
                ProfitTrend(points:stats.trend).frame(maxWidth:.infinity)
                ActionMixChart(statistics:actions).frame(maxWidth:.infinity)
            }.frame(height:chartHeight)
            VStack(alignment:.leading,spacing:8) {
                HStack { Text("YOUR PLAY STYLE · OBSERVED ACTIONS").sectionLabel(); Spacer(); Text("\(actions.total) actions · \(actions.preflopHands) sampled preflop hands").font(.system(size:10)).foregroundStyle(.secondary) }.frame(height:16)
                HStack(spacing:10) {
                    detail("Play %",statPercent(actions.playRate),"\(actions.playedHands) / \(actions.preflopHands) preflop samples")
                    detail("Preflop raise %",statPercent(actions.preflopRaiseRate),"\(actions.raisedPreflopHands) / \(actions.preflopHands) preflop samples")
                    detail("Raises","\(actions.count(.raise))","\(statPercent(actions.rate(.raise))) of recorded actions")
                    detail("Folds","\(actions.count(.fold))","\(statPercent(actions.rate(.fold))) of recorded actions")
                }.frame(maxHeight:.infinity)
                HStack(spacing:10) {
                    detail("Checks / calls / bets","\(actions.count(.check)) / \(actions.count(.call)) / \(actions.count(.bet))","Confirmed action labels only")
                    detail("Largest win / loss","\(statDollars(stats.largestWin)) / \(statDollars(stats.largestLoss))","Per measured hand interval")
                    detail("Max drawdown",statDollars(stats.drawdown),"Peak-to-trough measured decline")
                    detail("Known raise additions",statDollars(actions.pricedRaises > 0 ? actions.knownRaiseAddedCents : nil),"\(actions.pricedRaises) / \(actions.count(.raise)) raises with chip evidence")
                }.frame(maxHeight:.infinity)
                Text("Cards visible on flop: \(tracking.archive.hands.filter(\.sawFlop).count) · river: \(tracking.archive.hands.filter(\.reachedRiver).count) · measured win rate: \(statPercent(stats.winRate)) · avg. measured result: \(stats.averageCents.map { String(format:"%+.2f USD",$0/100) } ?? "—")")
                    .font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(height:14)
            }.padding(12).frame(height:detailsHeight).dashboardPanel()
            HStack {
                Text(tracking.storageError ?? "Screen-derived samples. Missed actions bias rates; missing results stay unmeasured. Record top-ups/cash-outs in history.")
                    .font(.system(size:10)).foregroundStyle(tracking.storageError == nil ? Color.secondary : Color.orange).lineLimit(2)
                Spacer()
                Text("Local history").font(.system(size:10)).foregroundStyle(DashboardStyle.accent)
            }.frame(height:32)
        }.padding(12).frame(height:height).transaction { $0.animation = nil }
    }
    private func tile(_ title: String,_ value: String,_ note: String,color: Color = .primary) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.system(size:10)).foregroundStyle(.secondary)
            Text(value).font(.system(size:24,weight:.semibold,design:.rounded)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(.horizontal,12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).dashboardPanel()
    }
    private func detail(_ title: String,_ value: String,_ note: String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.system(size:11)).foregroundStyle(.secondary)
            Text(value).font(.system(size:21,weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2)
        }.padding(10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
    }
}

struct ActionMixChart: View {
    var statistics: ActionStatistics
    private func color(_ kind: SeatAction) -> Color { switch kind { case .fold: return DashboardStyle.loss; case .check: return .gray; case .call: return DashboardStyle.accent; case .bet: return DashboardStyle.cyan; case .raise: return .orange } }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("ACTION MIX").sectionLabel(); Spacer(); Text("\(statistics.total) actions").font(.system(size:10)).foregroundStyle(.secondary) }.frame(height:14)
            ForEach(SeatAction.allCases,id:\.self) { kind in
                HStack(spacing:10) {
                    Text(kind.label).font(.system(size:11)).frame(width:38,alignment:.leading)
                    GeometryReader { geometry in
                        ZStack(alignment:.leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(color(kind)).frame(width:geometry.size.width*(statistics.rate(kind) ?? 0))
                        }
                    }.frame(height:7)
                    Text("\(statistics.count(kind)) · \(statPercent(statistics.rate(kind)))").font(.system(size:10,design:.monospaced)).monospacedDigit().frame(width:75,alignment:.trailing)
                }.frame(maxHeight:.infinity).help("\(kind.label) labels divided by all recorded action labels. This is not a per-hand opportunity rate.")
            }
            Text("Confirmed labels, including after your fold").font(.system(size:9)).foregroundStyle(.tertiary).frame(height:12)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity).dashboardPanel()
    }
}

struct ProfitTrend: View {
    var points: [Int]
    private var low: Double { Double(min(0,points.min() ?? 0)) }
    private var high: Double { Double(max(0,points.max() ?? 0)) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("MEASURED RESULTS").sectionLabel(); Spacer(); Text(statDollars(points.count > 1 ? points.last : nil,signed:true)).font(.system(size:11,weight:.medium)).monospacedDigit() }.frame(height:14)
            GeometryReader { geometry in
                let width = max(1,geometry.size.width-58), height = max(1,geometry.size.height)
                let y: (Double) -> Double = { value in height*(1-(value-low)/max(1,high-low)) }
                Path { path in path.move(to:CGPoint(x:0,y:y(0))); path.addLine(to:CGPoint(x:width,y:y(0))) }
                    .stroke(Color.white.opacity(0.15),style:StrokeStyle(lineWidth:1,dash:[3,4]))
                if points.count > 1 {
                    Path { path in
                        let stride = max(1,points.count/400)
                        var indices = Array(Swift.stride(from:0,to:points.count,by:stride)); if indices.last != points.count-1 { indices.append(points.count-1) }
                        for (position,index) in indices.enumerated() {
                            let point = CGPoint(x:width*Double(index)/Double(points.count-1),y:y(Double(points[index])))
                            if position == 0 { path.move(to:point) } else { path.addLine(to:point) }
                        }
                    }.stroke(DashboardStyle.accent,style:StrokeStyle(lineWidth:2,lineJoin:.round))
                } else { Text("Measured results will appear after a readable next-hand checkpoint.").font(.system(size:11)).foregroundStyle(.secondary).frame(width:width,height:height) }
                VStack { Text(statDollars(Int(high))); Spacer(); Text(statDollars(Int(low))) }.font(.system(size:9)).foregroundStyle(.secondary).frame(width:56,height:height).offset(x:width+2)
            }
            Text("\(max(0,points.count-1)) measured hand intervals · unfinished results excluded").font(.system(size:9)).foregroundStyle(.tertiary).frame(height:12)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity).dashboardPanel()
    }
}

struct StatisticsDefinitions: View {
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Statistics and sample sizes").font(.headline)
            Text("Play % = preflop hands with a recorded call, bet or raise ÷ preflop hands with any recorded action. Blinds alone do not count. Preflop raise % uses the same denominator and counts hands with a raise label. These sampled rates can differ from complete-history VPIP/PFR.")
            Text("Raise, fold, check, call and bet percentages are shares of all recorded actions, across streets. A hand can contain several actions. Every action needs two consistent high-confidence labels at the same seat. Missed or short labels reduce coverage and can bias the percentages.")
            Text("Gross won/lost sum positive/negative measured hand intervals. Net uses preflop balance checkpoints minus recorded cash changes. A measured win includes blinds/rake already reflected in the balance, not the gross pot payout. Add top-ups/cash removals before the next checkpoint. Missing hands can combine intervals.")
            Text("Known raise additions include only raises with a readable stack reduction as the label appeared. Unknown amounts remain absent. Max drawdown is the largest decline from a previous peak in measured hand results. Old hands without action labels still count as observed hands, not as checks or folds.")
        }.font(.callout).fixedSize(horizontal:false,vertical:true)
    }
}
