import SwiftUI
import PokerCore
import TableRecognition
import AppKit
import UniformTypeIdentifiers

private func trackedMoney(_ cents: Int?,signed: Bool = false) -> String {
    cents.map { String(format:signed ? "%+.2f USD" : "$%.2f",Double($0)/100) } ?? "—"
}

struct OpponentTrackingPanel: View {
    @ObservedObject var tracking: PlayTracking
    var height: CGFloat
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            HStack { Text("PLAYER ACTIONS").sectionLabel(); Spacer(); Image(systemName:"memorychip").foregroundStyle(DashboardStyle.accent) }.frame(height:14)
            HStack(spacing:3) {
                Text("Seat").frame(width:40,alignment:.leading)
                ForEach(["Play","Raise","Fold","Check"],id:\.self) { Text($0).frame(maxWidth:.infinity) }
            }.font(.system(size:8)).foregroundStyle(.secondary).frame(height:12)
            ForEach(0..<8,id:\.self) { i in
                let player = tracking.opponents.sorted { $0.screenPosition < $1.screenPosition }[safe:i]
                let stats = player?.statistics
                let values = player == nil ? Array(repeating:"—",count:4) : [stats?.playRate,stats?.rate(.raise),stats?.rate(.fold),stats?.rate(.check)].map { value in samplePercent(value)+(value != nil && (stats?.inferredCount ?? 0) > 0 ? "*" : "") }
                VStack(alignment:.leading,spacing:1) {
                    HStack(spacing:3) {
                        Text(player?.label ?? "—").font(.system(size:9,weight:.medium)).lineLimit(1).minimumScaleFactor(0.7).frame(width:40,alignment:.leading)
                        ForEach(values.indices,id:\.self) { j in
                            Text(values[j]).font(.system(size:10,design:.rounded)).monospacedDigit().frame(maxWidth:.infinity)
                        }
                    }
                    HStack {
                        Text(player.map { "\($0.observedRounds.count) rounds · \($0.statistics.total) acts · \($0.flopRounds.count) flops" } ?? "Waiting for seat").foregroundStyle(.secondary)
                        Spacer(minLength:2)
                        Text(player?.actions.last.map { $0.kind.label+($0.inferred ? "*" : "") } ?? player?.shown.last?.cards.map(\.display).joined(separator:" ") ?? "—").foregroundStyle(DashboardStyle.cyan)
                    }.font(.system(size:8)).lineLimit(1)
                }.frame(height:max(24,(height-102)/8)).help("Play: entered pot in sampled preflop hands. Raise/Fold/Check: recorded action mix. n=0 means no action samples. * includes inferred actions. Flops count rounds with active cards visible on a board. Open history for evidence and samples.")
            }
            Text("n=0: no samples. * includes inferred actions. Flops = visible participation; details in history.")
                .font(.system(size:9)).foregroundStyle(.tertiary).lineLimit(2).frame(height:26,alignment:.topLeading)
        }.padding(10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).frame(height:height).dashboardPanel()
    }
}

struct TrackingSheet: View {
    @ObservedObject var tracking: PlayTracking
    var endTable: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Int
    @State private var cash = ""
    @State private var cashDirection = 1
    @State private var selectedHand: UUID?
    @State private var exportMessage: String?
    init(tracking: PlayTracking,endTable: @escaping () -> Void,initialTab: Int = 0) {
        self.tracking = tracking; self.endTable = endTable; _tab = State(initialValue:initialTab)
        _selectedHand = State(initialValue:tracking.archive.hands.last?.id)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Play history").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("End table & stop scanning",action:endTable).disabled(!tracking.active)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("History",selection:$tab) {
                Text("Opponents · current table").tag(0)
                Text("My play · saved locally").tag(1)
            }.pickerStyle(.segmented)
            if let error = tracking.storageError { Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
            if tab == 0 { opponentHistory } else { ownHistory }
        }.padding(24).frame(width:940,height:690).background(DashboardStyle.background).preferredColorScheme(.dark)
    }
    private var opponentHistory: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(tracking.status).font(.callout).foregroundStyle(.secondary)
            Text("Cards stay in memory for this uninterrupted table session. A NEW PLAYER marker, confirmed seat disappearance, changed seat/layout, Stop, capture loss or leaving the table clears the relevant records. Short reveals may be missed. River reveals are not proof of a completed showdown.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Anonymous replacements or table switches with identical layouts can be invisible. End this table before switching, and clear a seat if continuity is uncertain. Profiles are not used to change live equity assumptions.")
                .font(.caption).foregroundStyle(.orange)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if tracking.opponents.isEmpty { Text("No confirmed occupied opponent seats yet.").foregroundStyle(.secondary).padding(.vertical,40) }
                    ForEach(tracking.opponents.sorted { $0.screenPosition < $1.screenPosition }) { player in
                        VStack(alignment:.leading,spacing:8) {
                            HStack {
                                Text(player.label).font(.headline)
                                Text("\(player.observedRounds.count) observed rounds · \(player.shown.count) shown hands").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear this seat") { tracking.forgetOpponent(player.id) }.controlSize(.small)
                            }
                            let stats = player.statistics
                            HStack(spacing:18) {
                                opponentMetric("Play",samplePercent(stats.playRate),"\(stats.playedHands)/\(stats.preflopHands) preflop hands")
                                opponentMetric("Preflop raise",samplePercent(stats.preflopRaiseRate),"\(stats.raisedPreflopHands)/\(stats.preflopHands) preflop hands")
                                opponentMetric("Raise",samplePercent(stats.rate(.raise)),"\(stats.count(.raise))/\(stats.total) actions")
                                opponentMetric("Fold",samplePercent(stats.rate(.fold)),"\(stats.count(.fold))/\(stats.total) actions")
                                opponentMetric("Check",samplePercent(stats.rate(.check)),"\(stats.count(.check))/\(stats.total) actions")
                                opponentMetric("Call / bet","\(stats.count(.call)) / \(stats.count(.bet))","Observed actions")
                            }
                            Text("Play/PFR use sampled preflop hands. Other percentages use recorded actions, including estimates. Missed actions bias rates; these are not complete-history VPIP/PFR.").font(.caption).foregroundStyle(.secondary)
                            Text("Evidence: \(stats.total-stats.inferredCount) labels · \(stats.inferredCount) inferred. Flop visible: \(player.flopRounds.count)/\(player.observedRounds.count) observed rounds (partial rounds included; not VPIP).")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(player.actions.suffix(8).reversed())) { event in
                                Text("\(event.time.formatted(date:.omitted,time:.standard)) · \(event.kind.label) · \(event.evidenceDescription) · street \(event.street)")
                                    .font(.caption).foregroundStyle(event.inferred ? .orange : DashboardStyle.cyan)
                            }
                            if player.shown.isEmpty { Text("No two-card reveal confirmed.").font(.caption).foregroundStyle(.secondary) }
                            ForEach(player.shown.reversed()) { reveal in
                                HStack {
                                    Text(reveal.time,style:.time).frame(width:100,alignment:.leading)
                                    Text(reveal.cards.map(\.display).joined(separator:"  ")).font(.title3).foregroundStyle(DashboardStyle.cyan).frame(width:110,alignment:.leading)
                                    Text(reveal.board.isEmpty ? "No board recorded" : reveal.board.map(\.display).joined(separator:" ")).frame(maxWidth:.infinity,alignment:.leading)
                                    Text(reveal.kind).foregroundStyle(.secondary)
                                }.font(.callout)
                            }
                        }.padding(14).dashboardPanel()
                    }
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    private var ownHistory: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:16) {
                stat("Observed hands",String(tracking.archive.hands.count))
                stat("Measured results",String(tracking.measuredHands.count))
                stat("Won / lost / even", "\(tracking.measuredHands.filter { ($0.netCents ?? 0) > 0 }.count) / \(tracking.measuredHands.filter { ($0.netCents ?? 0) < 0 }.count) / \(tracking.measuredHands.filter { $0.netCents == 0 }.count)")
                stat("Observed net*",trackedMoney(tracking.totalNetCents,signed:true))
            }.frame(height:55)
            Text("*Measured between confirmed preflop stack + current-bet checkpoints. Unrecorded top-ups/cash removals affect this estimate. The first partial hand and the final unfinished hand may have no result. Missing deals can combine an interval; these are observed results, not account statements or exact win rates.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Cards visible: \(tracking.archive.hands.filter(\.sawFlop).count) on flop · \(tracking.archive.hands.filter(\.reachedRiver).count) on river · \(tracking.archive.hands.filter(\.cardsDisappeared).count) disappearances (fold / muck / reading gap).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Cash change",selection:$cashDirection) { Text("Added to table").tag(1); Text("Removed from table").tag(-1) }.frame(width:240)
                TextField("Dollars",text:$cash).frame(width:90)
                Button("Record") {
                    guard let cents = TableMoney.cents(cash,requireCurrency:false), cents > 0 else { exportMessage = "Enter a positive dollar amount, such as 5.00."; return }
                    if tracking.addCashAdjustment(cents:cents*cashDirection) { cash = ""; exportMessage = nil }
                }.disabled(!tracking.active)
                Spacer()
                Button("Export my history") { exportOwnHistory() }
            }
            Text(exportMessage ?? tracking.tableRecord.map { "This table: \(trackedMoney($0.netCents,signed:true)) · pending cash changes: \(trackedMoney($0.pendingCashCents,signed:true)). Updates at the next preflop checkpoint." } ?? "Personal history persists after this table closes. Opponent cards are never included.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height:30,alignment:.topLeading)
            HSplitView {
                ScrollView {
                    LazyVStack(spacing:6) {
                        ForEach(tracking.archive.hands.reversed()) { hand in
                            Button { selectedHand = hand.id } label: {
                                VStack(alignment:.leading,spacing:5) {
                                    HStack { Text(hand.hole.compactMap(Card.init).map(\.display).joined(separator:" ")).fontWeight(.semibold); Spacer(); Text(trackedMoney(hand.netCents,signed:true)).monospacedDigit() }
                                    Text("\(hand.started.formatted(date:.abbreviated,time:.shortened)) · \(hand.completion)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(selectedHand == hand.id ? DashboardStyle.cyan.opacity(0.13) : Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
                            }.buttonStyle(.plain)
                        }
                        if tracking.archive.hands.isEmpty { Text("Your confirmed hands will appear here.").foregroundStyle(.secondary).padding(20) }
                    }
                }.frame(minWidth:310)
                if let record = tracking.archive.hands.first(where:{ $0.id == selectedHand }) {
                    ScrollView {
                        VStack(alignment:.leading,spacing:10) {
                            Text("Your recorded observations").font(.headline)
                            Text("Board: \(record.board.compactMap(Card.init).map(\.display).joined(separator:" "))")
                            Text("\(record.startedPreflop ? "First seen preflop" : "Partial hand") · \(record.cardsDisappeared ? "Cards disappeared (possible fold/muck)" : "No disappearance confirmed")")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(record.actions ?? []) { event in
                                Text("\(event.time.formatted(date:.omitted,time:.standard)) · \(event.kind.label) · \(event.evidenceDescription) · added \(trackedMoney(event.addedCents)) · wager to \(trackedMoney(event.wagerToCents)) · street \(event.street)")
                                    .font(.caption).foregroundStyle(DashboardStyle.cyan)
                            }
                            ForEach(record.observations) { event in
                                VStack(alignment:.leading,spacing:3) {
                                    Text("\(event.time.formatted(date:.omitted,time:.standard)) · \([0:"Preflop",3:"Flop",4:"Turn",5:"River"][event.street] ?? "Street") · \(event.note)").font(.caption)
                                    Text(event.equity.map { String(format:"Equity %.1f%% · call EV %+.2f USD · call %.2f USD",$0*100,event.callEV ?? 0,Double(event.callCents ?? 0)/100) } ?? "Stack \(trackedMoney(event.stackCents)) · bet \(trackedMoney(event.betCents)) · pot \(trackedMoney(event.potCents))")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    if let opponents = event.opponents { Text("vs \(opponents) random hands · no later bets or rake").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                    }.frame(minWidth:380)
                } else { Text("Select a hand to see your cards, board, chip observations and decision estimates.").foregroundStyle(.secondary).padding(20).frame(minWidth:380,maxHeight:.infinity) }
            }.frame(maxHeight:.infinity)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
private func opponentMetric(_ title: String,_ value: String,_ sample: String) -> some View {
    VStack(alignment:.leading,spacing:3) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.title3).monospacedDigit()
        Text(sample).font(.caption2).foregroundStyle(.secondary)
    }.frame(maxWidth:.infinity,alignment:.leading)
}
    private func stat(_ title: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3).monospacedDigit() }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func exportOwnHistory() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "my-poker-history.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(tracking.archive).write(to:url,options:.atomic); exportMessage = "Exported your own history; no opponent data included." }
        catch { exportMessage = "Could not export your history to that location." }
    }
}
