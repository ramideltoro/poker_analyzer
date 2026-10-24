import Foundation
import Combine
import Darwin
import TableRecognition

/// The helper runs outside the capture and UI processes. Only explicit JSON is exchanged.
enum GTOSolverRunner {
    static var executable: URL? {
        if let path=ProcessInfo.processInfo.environment["CARD_READER_SOLVER_EXECUTABLE"],FileManager.default.isExecutableFile(atPath:path) { return URL(fileURLWithPath:path) }
        let file=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/live-card-solver")
        return FileManager.default.isExecutableFile(atPath:file.path) ? file : nil
    }
    static func run(_ request:GTORequest,executable:URL? = nil) throws -> GTOResult {
        guard let executable=executable ?? self.executable else { throw GTOError.message("Local solver helper is missing. Rebuild with scripts/build-app.sh.") }
        let process=Process(),input=Pipe(),output=Pipe()
        process.executableURL=executable;process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { kill(process.processIdentifier,SIGKILL);process.waitUntilExit() } }
        try input.fileHandleForWriting.write(contentsOf:GTORequest.encoder.encode(request));try input.fileHandleForWriting.close()
        let deadline=Date().addingTimeInterval(Double(request.seconds)+15)
        while process.isRunning {
            if Task.isCancelled { throw CancellationError() }
            if Date()>deadline { throw GTOError.message("Solver exceeded its time budget and was stopped. Try a later street or narrower plausible ranges.") }
            Thread.sleep(forTimeInterval:0.025)
        }
        if Task.isCancelled { throw CancellationError() }
        let data=try output.fileHandleForReading.readToEnd() ?? Data()
        guard process.terminationStatus==0,data.count<65536 else { throw GTOError.message("Local solver stopped without a valid result. No live recommendation was replaced.") }
        struct Failure:Decodable { var error:String }
        if let error=try? JSONDecoder().decode(Failure.self,from:data) { throw GTOError.message(String(error.error.prefix(400))) }
        let result=try GTORequest.decoder.decode(GTOResult.self,from:data);try result.validate(for:request);return result
    }
}

@MainActor final class GTOSolverModel:ObservableObject {
    typealias Calculate = @Sendable (GTORequest) throws -> GTOResult
    @Published var form=GTOForm() { didSet { if form != oldValue { onChange?() } } }
    @Published private(set) var source:GTOSnapshot?
    @Published private(set) var linkedSource:GTOSnapshot?
    @Published private(set) var result:GTOResult?
    @Published private(set) var solvedRequest:GTORequest?
    @Published private(set) var running=false
    @Published private(set) var message="Set up a heads-up postflop study, or copy a supported live decision."
    @Published private(set) var automatic=false
    var onChange:(()->Void)?
    private var generation=UUID()
    private var worker:Task<GTOResult,Error>?
    private var runningRequest:GTORequest?
    private let calculate:Calculate
    init(calculate:@escaping Calculate = { try GTOSolverRunner.run($0) }) { self.calculate=calculate }
    var resultMatchesForm:Bool { result != nil && solvedRequest == (try? form.request()) }
    var liveResult:GTOResult? {
        guard let source,linkedSource==source,let request=solvedRequest,source.matches(request),resultMatchesForm,result?.converged==true else { return nil };return result
    }
    func observe(_ next:GTOSnapshot?) {
        guard source != next else { return }
        source=next
        // Confirmed changed inputs revoke the old live link permanently. Gaps merely
        // hide it until fresh independent confirmations; they never feed historical money.
        if let next,let linkedSource,linkedSource != next { self.linkedSource=nil }
        if automatic,let next { load(next);solve(reuse:true) }
        onChange?()
    }
    func importSource() { guard let source else { message="Import needs confirmed cards, one active opponent, dealer, pot, stacks, zero hero street wager and current Check/Call controls. Earlier raises and side pots need manual study.";return };load(source);onChange?() }
    private func load(_ source:GTOSnapshot) { source.fill(&form);linkedSource=source }
    func setAutomatic(_ enabled:Bool) {
        if !enabled,automatic { cancel() }
        automatic=enabled
        if enabled,let source { load(source);solve(reuse:true) }
        else if enabled { message="Automatic solving starts at the next supported heads-up postflop decision. The range and rake assumptions above will be reused." }
        onChange?()
    }
    func solve(reuse:Bool=false) {
        do {
            let request=try form.request()
            if reuse,(running && runningRequest==request || solvedRequest==request && result != nil) { return }
            cancel()
            let token=generation,calculate=calculate
            runningRequest=request
            result=nil;solvedRequest=nil;running=true;message="Solving locally with two CPU threads…"
            let task=Task.detached(priority:.utility) { try calculate(request) };worker=task
            Task { [weak self] in
                let outcome=await task.result
                guard let self,self.generation==token else { return }
                self.running=false;self.worker=nil;self.runningRequest=nil
                switch outcome {
                case .success(let value):
                    do { try value.validate(for:request);self.result=value;self.solvedRequest=request
                        self.message=value.converged ? "Target reached for the configured ranges and bet tree." : "Time / iteration budget reached. Approximate strategy shown for study; live suggestions keep their existing model."
                    } catch { self.message=error.localizedDescription }
                case .failure(let error): self.message=error is CancellationError ? "Solve cancelled." : error.localizedDescription
                }
                self.onChange?()
            }
        } catch { message=error.localizedDescription }
        onChange?()
    }
    func cancel() { generation=UUID();worker?.cancel();worker=nil;running=false;runningRequest=nil }
    func stop() { cancel();message="Solve cancelled.";onChange?() }
    func captureStopped() { source=nil;linkedSource=nil;if automatic { cancel() };onChange?() }
    deinit { worker?.cancel() }
}

extension HandAnalysisModel {
    func refreshSolverSource() {
        solver.observe(GTOSnapshot.read(hand:currentHand,table:table,confirmed:automatic && tableConfirmed && actionControlsConfirmed,position:recognizedPosition))
    }
    var solverAdvice:ActionAdvice? {
        guard automatic,tableConfirmed,actionControlsConfirmed,let table,let result=solver.liveResult,
              let c=result.preferred,let legal=DefaultDecision.available(table,confirmed:true),legal.contains(c.action),
              let request=solver.solvedRequest,let source=solver.source,source.matches(request) else { return nil }
        if [.bet,.raise].contains(c.action),c.amountCents != request.stackCents {
            guard let bb=effectiveBigBlind,c.amountCents>=bb else { return nil }
        }
        let percentage=String(format:"%.1f%%",c.frequency*100),gap=String(format:"%.2f%%",result.gapPercent)
        return ActionAdvice(title:c.action.label.uppercased(),reason:"\(c.label): the most frequent solver action (\(percentage)) for your exact hand. EV \(String(format:"%+.2f USD",c.evCents/100)); measured exploitability \(gap) of the root pot. Heads-up postflop, configured ranges, rake and restricted bet sizes; mixed actions and assumptions are in GTO solver.",kind:c.action,basis:"GTO SOLVER")
    }
}
