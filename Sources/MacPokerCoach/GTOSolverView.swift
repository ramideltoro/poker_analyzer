import SwiftUI
import AppKit

struct GTOSolverView:View {
    @ObservedObject var solver:GTOSolverModel
    @State private var showHelp=false
    var body:some View {
        GeometryReader { geometry in
            let compact=geometry.size.height<670
            VStack(alignment:.leading,spacing:compact ? 10 : 16) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text("GTO solver").font(.system(size:24,weight:.semibold,design:.rounded))
                        Text("Local heads-up postflop strategy · editable ranges · a restricted no-limit bet tree").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("How it works",systemImage:"info.circle") { showHelp=true }.buttonStyle(.bordered)
                        .popover(isPresented:$showHelp) { GTOSolverHelp().padding(20).frame(width:490) }
                }
                HStack(alignment:.top,spacing:16) {
                    setup(compact:compact).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                    results(compact:compact).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                }
                Text("Engine: postflop-solver © 2022 Wataru Inariba · AGPL-3.0-or-later · No warranty · Source, license and build instructions included in the app.")
                    .font(.system(size:9)).foregroundStyle(.tertiary)
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }.transaction { $0.animation=nil }
    }
    private func setup(compact:Bool)->some View {
        VStack(alignment:.leading,spacing:compact ? 8 : 12) {
            HStack {
                Text("SUBGAME INPUTS").sectionLabel();Spacer()
                Button("Copy live spot") { solver.importSource() }.controlSize(.small).disabled(solver.source==nil)
                    .help("Needs a confirmed heads-up postflop decision, known position, pot, stacks and wagers. Hero must have no paid wager on this street. Ranges and rake stay as entered.")
            }
            HStack { field("Your hole cards",text:$solver.form.hole);field("Board (3–5 cards)",text:$solver.form.board) }
            Picker("Your postflop order",selection:$solver.form.heroIp) { Text("Out of position · first").tag(false);Text("In position · last").tag(true) }.pickerStyle(.segmented).labelsHidden()
            HStack { field("Pot before street bet ($)",text:$solver.form.pot);field("Effective stack at root ($)",text:$solver.form.stack);field("Facing first bet ($)",text:$solver.form.facingBet) }
            Text("Pot excludes the facing bet. Effective stack is the smaller remaining stack before that bet. With no bet, IP is after OOP checks; OOP acts first.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            range("OUT-OF-POSITION RANGE",text:$solver.form.oopRange)
            range("IN-POSITION RANGE",text:$solver.form.ipRange)
            HStack { field("Rake (%) · explicit assumption",text:$solver.form.rake);field("Rake cap ($)",text:$solver.form.rakeCap) }
            HStack {
                Picker("Time",selection:$solver.form.seconds) { Text("10 sec").tag(10);Text("20 sec").tag(20);Text("60 sec").tag(60) }
                Picker("Iterations",selection:$solver.form.iterations) { Text("200").tag(200);Text("500").tag(500);Text("2,000").tag(2000) }
            }.font(.system(size:10))
            Picker("Target gap",selection:$solver.form.target) { Text("0.1% pot").tag(0.1);Text("0.5% pot").tag(0.5);Text("1% pot").tag(1.0) }.font(.system(size:10))
            HStack {
                Button(solver.running ? "Restart solve" : "Solve locally",systemImage:"cpu") { solver.solve() }.buttonStyle(.borderedProminent).tint(DashboardStyle.accent).foregroundStyle(.black)
                Button("Cancel") { solver.stop() }.disabled(!solver.running)
                Spacer()
            }.controlSize(.small)
            Toggle("Solve updated live spots automatically",isOn:Binding(get:{solver.automatic},set:{solver.setAutomatic($0)})).font(.system(size:11)).toggleStyle(.switch).controlSize(.mini).tint(DashboardStyle.accent)
                .help("Reuses these range and rake assumptions for each supported live snapshot. Recognition gaps keep ordinary estimates; a changed spot cancels its old solve. Large flop trees may exceed the memory limit.")
            Text("Ranges are assumptions, not recognized opponent hands. Defaults are illustrative broad ranges; edit them for the line played. Your range must contain your actual hand.").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(14).dashboardPanel()
    }
    private func results(compact:Bool)->some View {
        VStack(alignment:.leading,spacing:compact ? 10 : 14) {
            HStack {
                Text("ACTION MIX FOR YOUR EXACT HAND").sectionLabel();Spacer()
                if solver.running { ProgressView().controlSize(.small) }
                Text(solver.liveResult != nil ? "LIVE MATCH" : solver.resultMatchesForm ? "STUDY" : solver.result == nil ? "LOCAL" : "SAVED RESULT")
                    .font(.system(size:9,weight:.semibold)).foregroundStyle(solver.liveResult != nil ? DashboardStyle.accent : .secondary)
            }
            if let result=solver.result,let request=solver.solvedRequest {
                Text(result.preferred?.label.uppercased() ?? "—").font(.system(size:compact ? 26 : 34,weight:.bold,design:.rounded)).foregroundStyle(DashboardStyle.accent)
                Text("\(request.hole.joined(separator:" ")) · \(request.board.joined(separator:" ")) · \(request.heroIp ? "in position" : "out of position")")
                    .font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).lineLimit(2)
                HStack { Text("Action / frequency");Spacer();Text("EV from this decision") }.font(.system(size:9)).foregroundStyle(.secondary)
                VStack(spacing:compact ? 8 : 12) {
                    ForEach(result.choices) { choice in
                        VStack(spacing:4) {
                            HStack {
                                Text(choice.label).font(.system(size:12,weight:.medium))
                                Text(String(format:"%.1f%%",choice.frequency*100)).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format:"%+.2f USD",choice.evCents/100)).font(.system(size:12,weight:.medium,design:.monospaced)).monospacedDigit()
                            }
                            GeometryReader { g in
                                Capsule().fill(Color.white.opacity(0.06)).overlay(alignment:.leading) {
                                    Capsule().fill(choice.action == .fold ? DashboardStyle.loss : choice.action == .raise || choice.action == .bet ? DashboardStyle.cyan : DashboardStyle.accent).frame(width:max(0,g.size.width*choice.frequency))
                                }
                            }.frame(height:6)
                        }.accessibilityElement(children:.combine)
                    }
                }
                Grid(alignment:.leading,horizontalSpacing:18,verticalSpacing:10) {
                    GridRow {
                        metric("Strategy EV",String(format:"%+.2f USD",result.evCents/100),"Frequency-weighted EV of the strategy for your exact hand. Previous chips are sunk. Fold is zero; future bets and configured rake are included.")
                        metric("Range equity",String(format:"%.1f%%",result.equity*100),"Showdown equity against the solver’s conditional opponent range at this node. It is separate from the dashboard’s random-hand equity.")
                    }
                    GridRow {
                        metric("Exploitability",String(format:"%.3f%% pot",result.gapPercent),"Measured root-profile exploitability relative to the root pot, within this action abstraction. This is not a per-hand EV error bound or uncertainty about ranges.")
                        metric("Work",String(format:"%d iterations · %.1fs",result.iterations,result.elapsedSeconds),"Actual completed DCFR iterations and elapsed local compute time. This is not a count of simulated or historical deals.")
                    }
                }
                Text(result.converged ? "Requested convergence target reached." : "Budget limited · target not reached · study only.")
                    .font(.system(size:11,weight:.medium)).foregroundStyle(result.converged ? DashboardStyle.accent : .orange)
                Text("Most frequent action shown above. A mixed strategy deliberately uses several actions. EV assumes both players’ full ranges, the configured future tree, and the modeled rake.")
                    .font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !solver.resultMatchesForm { Text("Inputs changed. These values belong to the saved inputs shown above; solve again to update.").font(.system(size:10)).foregroundStyle(.orange) }
            } else {
                Spacer(minLength:8)
                Image(systemName:"chart.bar.xaxis").font(.system(size:40,weight:.light)).foregroundStyle(DashboardStyle.cyan)
                Text(solver.running ? "Building and solving the game tree" : "Strategy, sizing and EV in one view").font(.system(size:17,weight:.medium))
                Text("Enter a flop, turn or river and both ranges, then Solve locally. Results appear here after the worker finishes. Flop trees need more memory and time than river trees.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:8)
            }
            Text(solver.message).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text("Tree: 50% pot bets; pot-sized raises; stack-capped all-ins; the observed first bet is added exactly. 512 MiB strategy limit (compressed for larger trees), SPR ≤20, two threads. No preflop, multiway or side-pot solve.").font(.system(size:10)).foregroundStyle(.tertiary).fixedSize(horizontal:false,vertical:true)
        }.padding(14).dashboardPanel()
    }
    private func field(_ label:String,text:Binding<String>)->some View {
        VStack(alignment:.leading,spacing:4) { Text(label).font(.system(size:9)).foregroundStyle(.secondary);TextField(label,text:text).textFieldStyle(.roundedBorder).font(.system(size:12,design:.monospaced)).labelsHidden() }.frame(maxWidth:.infinity)
    }
    private func range(_ label:String,text:Binding<String>)->some View {
        VStack(alignment:.leading,spacing:4) { Text(label).sectionLabel();TextField("e.g. TT+,AQs+,AKo",text:text,axis:.vertical).lineLimit(2...3).textFieldStyle(.roundedBorder).font(.system(size:11,design:.monospaced)) }
    }
    private func metric(_ label:String,_ value:String,_ help:String)->some View {
        VStack(alignment:.leading,spacing:4) { Text(label).font(.system(size:10)).foregroundStyle(.secondary);Text(value).font(.system(size:15,weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth:.infinity,alignment:.leading).help(help)
    }
}
struct GTOSolverHelp:View {
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("What this solver solves").font(.headline)
            Text("Discounted counterfactual regret minimization (DCFR) computes an approximate equilibrium for two full hand ranges. The selected cards pick your row of that strategy; they are not revealed to the opponent. Weighted range syntax is supported, e.g. AA,AKs,AQo:0.5.")
            Text("Root inputs start before the first bet on the displayed street. With a facing bet, the engine solves the root and follows that exact first bet to your node (OOP checks first when applicable). It does not reconstruct earlier raises or infer ranges from player statistics. Rake defaults to an explicit zero-rake study assumption; enter the actual rate/cap for your model.")
            Text("Exploitability measures the whole root profile within the chosen sizes. Hitting 0.5% of the pot does not guarantee the best action for every individual hand, correct ranges, or a full no-limit equilibrium. Off-path hands with zero reach are rejected.")
            Text("Copy live spot requires independently confirmed heads-up cards, dealer order, pot, stacks, Call/Check price and wagers, with no hero investment this street. A converged result replaces the ordinary suggestion only while all inputs and legal actions match. Changed inputs, folds, capture interruption and edited assumptions prevent live use. Automatic mode reuses your explicit ranges and rake; it may finish after a decision window closes.")
            HStack {
                Link("Engine source",destination:URL(string:"https://github.com/b-inary/postflop-solver")!)
                Button("Included source & license") {
                    let url=Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/GTOSolverSource.zip")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Text("postflop-solver © 2022 Wataru Inariba. The solver helper is free software under AGPL-3.0-or-later, without warranty. Source and licenses for the helper and dependencies are included.").font(.caption).foregroundStyle(.secondary)
        }.font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
    }
}
