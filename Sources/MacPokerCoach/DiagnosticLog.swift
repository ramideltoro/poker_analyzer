import Foundation

/// Local metadata-only JSONL logs. No pixels, card values, OCR text, URLs, or window titles.
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    static let disabled = DiagnosticLog(enabled:false)
    let fileURL: URL?
    private let queue = DispatchQueue(label:"cardreader.diagnostics",qos:.utility)
    private let encoder = JSONEncoder()
    private var handle: FileHandle?
    private var bytes = 0
    private var part = 0
    private let limit: Int
    private let session: String
    private let directory: URL?
    struct Record: Codable { var timestamp: String; var event: String; var fields: [String:String] }

    init(directory: URL? = nil,enabled: Bool = true,limit: Int = 5_000_000) {
        self.limit = limit
        session = "session-"+ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")+"-"+UUID().uuidString.prefix(8)
        guard enabled else { fileURL = nil; self.directory = nil; return }
        let folder = directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LiveCardReader/Logs",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let url = folder.appendingPathComponent(session+".jsonl")
            guard FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw CocoaError(.fileWriteUnknown) }
            handle = try FileHandle(forWritingTo:url); fileURL = url; self.directory = folder
            encoder.outputFormatting = [.sortedKeys]
        } catch { fileURL = nil; self.directory = nil }
    }
    func write(_ event: String,_ fields: [String:String] = [:]) {
        guard fileURL != nil else { return }
        let date = Date()
        queue.async { [self] in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            let record = Record(timestamp:formatter.string(from:date),event:event,fields:fields)
            guard var data = try? encoder.encode(record) else { return }; data.append(10)
            do {
                if bytes+data.count > limit, let directory {
                    try handle?.close(); part = part%2+1; bytes = 0
                    let url = directory.appendingPathComponent(session+"-part\(part).jsonl")
                    FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600])
                    handle = try FileHandle(forWritingTo:url)
                }
                try handle?.write(contentsOf:data); bytes += data.count
            } catch { /* Logging must never interrupt capture. */ }
        }
    }
    func flush() { queue.sync { try? handle?.synchronize() } }
    deinit { try? handle?.close() }
}
