import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage
import TableRecognition

/// An idle event confirms unchanged content; silence never renews an old frame.
struct StreamFrameCache<Frame> {
    private(set) var frame: Frame?
    mutating func observe(status: SCFrameStatus?,newFrame: Frame? = nil) -> Frame? {
        switch status {
        case .complete: frame = newFrame
        case .idle: break
        default: frame = nil
        }
        return frame
    }
}

private final class FrameSink: NSObject, SCStreamOutput {
    let context = CIContext(options:[.cacheIntermediates:false])
    var receive: ((CGImage,Date,String) -> Void)?
    var status: ((Int) -> Void)?
    var interrupted: (() -> Void)?
    private var cache = StreamFrameCache<CGImage>()
    private var last = Date.distantPast
    func stream(_ stream: SCStream,didOutputSampleBuffer sampleBuffer: CMSampleBuffer,of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]]
        let raw = attachments?.first?[.status] as? Int
        let frameStatus = sampleBuffer.isValid ? raw.flatMap(SCFrameStatus.init(rawValue:)) : nil
        status?(raw ?? -1)
        autoreleasepool {
            var newFrame: CGImage?
            if frameStatus == .complete, let buffer = sampleBuffer.imageBuffer {
                let ci = CIImage(cvPixelBuffer:buffer)
                newFrame = context.createCGImage(ci,from:ci.extent)
            }
            let hadFrame = cache.frame != nil
            guard let image = cache.observe(status:frameStatus,newFrame:newFrame) else {
                if hadFrame { interrupted?() }
                return
            }
            let now = Date()
            guard now.timeIntervalSince(last) >= 0.45 else { return }
            last = now
            receive?(image,now,frameStatus == .idle ? "stream_idle" : "stream")
        }
    }
}

@MainActor final class CaptureController: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate {
    @Published private(set) var running = false
    @Published private(set) var choosing = false
    var onFrame: ((CGImage,Date,[UnitRect]) -> Void)?
    var onStarted: (() -> Void)?
    var onInvalidated: ((String) -> Void)?
    private var stream: SCStream?
    private var sink: FrameSink?
    private var display: SCDisplay?
    private var generation = UUID()
    private var lastDelivered = Date.distantPast
    private var previousExclusions = [UnitRect]()
    private var activity: NSObjectProtocol?
    private let log: DiagnosticLog
    private var delivered = 0
    private var lastCoverage: Double?
    init(log: DiagnosticLog = .shared) {
        self.log = log
        super.init(); SCContentSharingPicker.shared.add(self)
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.stop(reason:"Screen reading stopped for sleep. Click Start after waking.") }
        }
    }
    func chooseMonitor() {
        stop(reason:"Choose the monitor containing your table."); choosing = true
        delivered = 0; lastCoverage = nil
        log.write("picker_opened",["mode":"singleDisplay","global_permission_preflight":"\(CGPreflightScreenCaptureAccess())"])
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleDisplay]; config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config; picker.isActive = true; picker.present(using:.display)
    }
    func stop(reason: String = "Stopped. Click Start to watch your monitor.") {
        log.write("capture_stopped",["reason":reason,"delivered_frames":"\(delivered)"])
        generation = UUID(); running = false; choosing = false
        sink?.receive = nil; sink?.status = nil; sink?.interrupted = nil; sink = nil
        if let stream { Task { try? await stream.stopCapture() } }; stream = nil
        display = nil
        previousExclusions = []
        if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil
        SCContentSharingPicker.shared.isActive = false; onInvalidated?(reason)
    }
    private func start(_ selected: SCContentFilter) async {
        let token = generation
        log.write("picker_selected",["style":"\(selected.style.rawValue)","display_count":"\(selected.includedDisplays.count)","window_count":"\(selected.includedWindows.count)"])
        guard selected.style == .display, let selectedDisplay = selected.includedDisplays.first else { stop(reason:"Select a monitor in Apple's screen-sharing picker."); return }
        do {
            display = selectedDisplay
            let config = SCStreamConfiguration()
            let scale = min(Double(selected.pointPixelScale),3840/max(1,selected.contentRect.width))
            config.width = max(1,Int(selected.contentRect.width*scale)); config.height = max(1,Int(selected.contentRect.height*scale))
            config.minimumFrameInterval = CMTime(value:1,timescale:2)
            config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
            log.write("capture_configured",["width":"\(config.width)","height":"\(config.height)","pixel_scale":"\(scale)","display_width":"\(selectedDisplay.frame.width)","display_height":"\(selectedDisplay.frame.height)"])
            let sink = FrameSink()
            let logger = log
            sink.status = { raw in logger.write("stream_frame_status",["status_code":"\(raw)"]) }
            sink.interrupted = { [weak self] in
                Task { @MainActor in
                    guard let self, self.running, self.generation == token else { return }
                    self.log.write("stream_content_unavailable")
                    self.onInvalidated?("Screen content paused or unavailable. Waiting for a new frame…")
                }
            }
            sink.receive = { [weak self] image,time,source in
                Task { @MainActor in
                    guard let self, self.running, self.generation == token else { return }
                    self.deliver(image,time:time,source:source)
                }
            }
            let stream = SCStream(filter:selected,configuration:config,delegate:self)
            try stream.addStreamOutput(sink,type:.screen,sampleHandlerQueue:DispatchQueue(label:"handreader.capture",qos:.userInitiated))
            self.sink = sink; self.stream = stream
            try await stream.startCapture()
            guard generation == token else { try? await stream.stopCapture(); return }
            running = true; lastDelivered = .distantPast
            log.write("capture_started",["capture_mode":"picker_stream_only"])
            activity = ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Continuously detect cards on the selected monitor")
            onStarted?()
        } catch {
            guard generation == token else { return }
            log.write("capture_error",["domain":(error as NSError).domain,"code":"\((error as NSError).code)","message":error.localizedDescription])
            stop(reason:"Screen capture unavailable: \(error.localizedDescription)")
        }
    }
    private func deliver(_ image: CGImage,time: Date,source: String) {
        guard time.timeIntervalSince(lastDelivered) >= 0.4, let display else { return }
        lastDelivered = time
        let mainHeight = NSScreen.screens.first?.frame.height ?? display.frame.height
        // Also ignore a still-open previous reader version, so it cannot become a false card source.
        let readerPIDs = Set(NSWorkspace.shared.runningApplications.filter { ["local.livecardreader","local.macpokercoach"].contains($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
        let windows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]]) ?? []
        let geometry = windows.compactMap { info -> CaptureGeometry.Window? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = info[kCGWindowBounds as String] as? [String:Any], let rect = CGRect(dictionaryRepresentation:bounds as CFDictionary),
                  (info[kCGWindowLayer as String] as? Int ?? 0) >= 0 else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }
            // System sharing borders/overlays can span a display while being mostly transparent.
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            return CaptureGeometry.Window(bounds:rect,isReader:readerPIDs.contains(pid),opaque:alpha >= 0.99 && layer == 0)
        }
        var current = CaptureGeometry.visibleReaderRegions(geometry,display:display.frame)
        if windows.isEmpty {
            current = NSApp.windows.filter { $0.isVisible && !$0.isMiniaturized && $0.isOnActiveSpace && $0.occlusionState.contains(.visible) }.compactMap {
                CaptureGeometry.excludedRegion(window:$0.frame,display:display.frame,mainScreenHeight:mainHeight)
            }
        }
        let exclusions = previousExclusions+current
        previousExclusions = current
        delivered += 1
        let coverage = CaptureGeometry.coveredFraction(exclusions)
        log.write("frame_received",["source":source,"frame":"\(delivered)","width":"\(image.width)","height":"\(image.height)","excluded_regions":"\(exclusions.count)","excluded_fraction":String(format:"%.4f",coverage)])
        if lastCoverage == nil || abs((lastCoverage ?? 0)-coverage) > 0.05 {
            log.write("reader_exclusion_changed",["excluded_fraction":String(format:"%.4f",coverage),"onscreen_metadata_windows":"\(geometry.count)"])
            lastCoverage = coverage
        }
        onFrame?(image,time,exclusions)
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker,didCancelFor stream: SCStream?) {
        Task { @MainActor in if self.choosing { self.stop(reason:"Monitor selection cancelled. Click Start to try again.") } }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker,didUpdateWith filter: SCContentFilter,for stream: SCStream?) {
        Task { @MainActor in guard self.choosing else { return }; self.choosing = false; await self.start(filter) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.stop(reason:"Screen-sharing picker failed: \(error.localizedDescription)") }
    }
    nonisolated func stream(_ stream: SCStream,didStopWithError error: Error) {
        Task { @MainActor in guard self.stream === stream else { return }; self.stop(reason:"Screen reading stopped: \(error.localizedDescription)") }
    }
}
