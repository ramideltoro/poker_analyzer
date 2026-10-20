import AppKit
import SwiftUI
import TableRecognition
import Combine

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var hand: LiveHand?
    @Published private(set) var status = "Click Start and choose the monitor containing your table."
    @Published private(set) var faces = 0
    @Published private(set) var scanned = 0
    @Published private(set) var milliseconds = 0
    @Published private(set) var receivedFrames = 0
    @Published private(set) var candidates = 0
    @Published private(set) var lastScan: Date?
    let capture: CaptureController
    let log: DiagnosticLog
    let analysis: HandAnalysisModel
    let tracking: PlayTracking
    private var analysisObserver: AnyCancellable?
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development" }
    private var stabilizer = ReadingStabilizer()
    private var reviewTracker = FoldReviewTracker()
    private var generation = UUID()
    private var busy = false
    private var pending: (CGImage,Date,[UnitRect])?
    private var watchdog: Timer?
    private let detector = AutomaticCardDetector()
    private let tableDetector = TableStateDetector()
    private let queue = DispatchQueue(label:"handreader.detection",qos:.userInitiated)
    init(log: DiagnosticLog = .shared,tracking: PlayTracking? = nil,analysis: HandAnalysisModel? = nil) {
        self.log = log; capture = CaptureController(log:log)
        self.analysis = analysis ?? HandAnalysisModel()
        self.tracking = tracking ?? PlayTracking(persist:log === DiagnosticLog.shared)
        analysisObserver = self.analysis.$display.sink { [weak self] display in
            guard let self else { return }
            self.tracking.recordDecision(display,current:self.analysis.estimateIsCurrent)
        }
        log.write("app_launched",["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown","os":ProcessInfo.processInfo.operatingSystemVersionString,"privacy":"metadata_only_no_images_or_card_values"])
        capture.onFrame = { [weak self] image,time,excluded in self?.receive(image,time:time,excluded:excluded) }
        capture.onStarted = { [weak self] in self?.status = "Scanning the selected monitor for visible cards…" }
        capture.onInvalidated = { [weak self] reason in
            guard let self else { return }
            self.clear(reason,keepLayout:self.capture.running)
        }
        watchdog = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.expire() }
        }
    }
    func start() { scanned = 0; receivedFrames = 0; candidates = 0; faces = 0; milliseconds = 0; lastScan = nil; log.write("start_clicked"); capture.chooseMonitor() }
    func stop() { capture.stop() }
    func showLogs() {
        log.flush()
        if let url = log.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { status = "Diagnostic logs could not be created in Application Support." }
    }
    func clear(_ reason: String,keepLayout: Bool = false) {
        generation = UUID(); busy = false; pending = nil; stabilizer.reset(keepLayout:keepLayout); hand = nil; faces = 0; lastScan = nil; status = reason
        reviewTracker.reset(); analysis.reset()
        tracking.endTable(reason)
        log.write("readings_cleared",["reason":reason,"layout_retained":"\(stabilizer.hasLayout)"])
    }
    func expire(now: Date = Date()) {
        if let lastScan, now.timeIntervalSince(lastScan) > 2.5 {
            clear("Scanning continues · waiting for a fresh screen reading…",keepLayout:true)
        }
    }
    private func receive(_ image: CGImage,time: Date,excluded: [UnitRect]) {
        receivedFrames += 1
        if busy { pending = (image,time,excluded); log.write("analysis_latest_frame_queued",["received_frames":"\(receivedFrames)"]); return }
        busy = true; let token = generation, detector = detector, tableDetector = tableDetector, hints = stabilizer.searchRegions
        queue.async { [weak self] in
            guard let self else { return }
            let result = autoreleasepool { Result {
                let start = Date()
                var scan = try detector.scan(image,excluding:excluded,searchRegions:hints,timestamp:time)
                // A table OCR failure clears automatic money but must not stop continuous card recognition.
                scan.table = try? tableDetector.scan(image,cards:scan.cards,heroRegions:Array(hints.prefix(2)),excluding:excluded)
                scan.seconds = Date().timeIntervalSince(start)
                return scan
            } }
            Task { @MainActor in
                guard self.generation == token, self.capture.running else { return }
                self.busy = false
                switch result {
                case .success(let scan): self.acceptScan(scan)
                case .failure(let error):
                    self.stabilizer.reset(keepLayout:true); self.hand = nil; self.status = "Card detection failed on this frame; retrying…"
                    self.analysis.update(nil)
                    self.log.write("detector_error",["domain":(error as NSError).domain,"code":"\((error as NSError).code)","message":error.localizedDescription])
                }
                if let (next,timestamp,excluded) = self.pending {
                    self.pending = nil; self.receive(next,time:timestamp,excluded:excluded)
                }
            }
        }
    }
    func acceptScan(_ scan: CardScan,now: Date = Date()) {
        var fields = scan.diagnostics.fields
        fields["recognized_faces"] = "\(scan.cards.count)"; fields["candidate_attempts"] = "\(scan.rectangles)"
        fields["scan_ms"] = String(format:"%.1f",scan.seconds*1000); fields["frame_age_ms"] = String(format:"%.1f",now.timeIntervalSince(scan.timestamp)*1000)
        fields["recognized_regions"] = scan.cards.map { card in
            let b = card.bounds
            return String(format:"%.4f,%.4f,%.4f,%.4f",b.x,b.y,b.width,b.height)
        }.joined(separator:";")
        log.write("detector_completed",fields)
        guard now.timeIntervalSince(scan.timestamp) <= 2.5, scan.timestamp.timeIntervalSince(now) <= 1 else { clear("Scanning continues · waiting for a fresh screen reading…",keepLayout:true); return }
        scanned += 1; faces = scan.cards.count; candidates = scan.rectangles; milliseconds = Int(scan.seconds*1000); lastScan = scan.timestamp
        let result = stabilizer.accept(scan)
        hand = reviewTracker.accept(live:result.0,scan:scan)
        tracking.observe(table:scan.table,hand:hand,time:scan.timestamp)
        status = hand?.isReview == true ? "Saved hole cards · continuing visible-board what-if review" : result.1
        analysis.update(hand,table:scan.table)
        if scan.cards.isEmpty && !stabilizer.hasLayout { status = scan.diagnostics.summary }
        let advice = analysis.actionAdvice
        log.write("reader_status",["message":status,"confirmed_hand":"\(hand != nil)","saved_card_review":"\(hand?.isReview == true)","completed_scans":"\(scanned)","layout_locked":"\(stabilizer.hasLayout)",
                                  "table_observed":"\(scan.table != nil)","table_confirmed":"\(analysis.tableConfirmed)","seats_read":"\(scan.table?.seats.count ?? 0)",
                                  "readable_stacks":"\(scan.table?.seats.filter { $0.stackCents != nil }.count ?? 0)","unclear_seats":"\(scan.table?.seats.filter { $0.activity == .unknown }.count ?? 0)",
                                  "pot_read":"\(scan.table?.potCents != nil)","call_read":"\(scan.table?.callCents != nil)","side_pots_detected":"\(scan.table?.sidePots ?? false)",
                                  "table_data_status":scan.table?.incompleteReason ?? (scan.table == nil ? "no_table" : "complete"),"automatic_ev_available":"\(analysis.automatic && analysis.callEstimate != nil)",
                                  "explicit_action_labels":"\(scan.table?.seats.filter { $0.action != nil }.count ?? 0)","opponent_profiles":"\(tracking.opponents.count)","own_hand_action_count":"\(tracking.currentHand?.actions?.count ?? 0)",
                                  "advice_action":advice.title,"advice_basis":advice.basis,"advice_close":"\(advice.marginal)","advice_available":"\(advice.kind != nil)","advice_state":advice.state.rawValue,"action_controls_confirmed":"\(analysis.actionControlsConfirmed)"])
    }
}
