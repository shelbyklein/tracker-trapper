import Foundation
import CryptoKit
import Darwin

public struct SessionWatch: Codable, Identifiable, Equatable, Sendable {
    public var id: String { runID }
    public let runID: String
    public let sourcePath: String
    public let format: SessionFormat
    public let sessionID: String
    public var offset: UInt64
    public var fileIdentity: String
    public var anchor: String
    public var status: String
    public var lastObservedAt: Date?
    public var lastSummary: String?
}

/// Runs outside the agent, inside the menu-bar app. Sources are explicitly
/// linked, opened read-only, and checkpointed separately from the plan store.
public actor SessionWatcher {
    private let store: TrackerStore
    public let stateURL: URL
    private let maxChunk = 2 * 1024 * 1024

    public init(store: TrackerStore, stateURL: URL? = nil) {
        self.store = store
        self.stateURL = stateURL ?? store.url.deletingPathExtension().appendingPathExtension("watchers.json")
    }

    public func link(runID: String, sourcePath: String, format: SessionFormat) async throws -> SessionWatch {
        let snapshot = try await store.read()
        guard let run = snapshot.runs.first(where: { $0.id == runID }) else {
            throw StoreError.notFound("run \(runID)")
        }
        guard sourcePath.hasPrefix("/"), sourcePath.hasSuffix(".jsonl") else { throw StoreError.conflict("select an absolute session .jsonl path") }
        let path = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().path
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? file.close() }
        let session = try sourceSession(file, format: format)
        let descriptor = try lock(); defer { unlock(descriptor) }
        var watches = try load()
        if let existing = watches.first(where: { $0.runID == runID && $0.sourcePath == path && $0.sessionID == session && $0.format == format }) { return existing }
        guard !watches.contains(where: { watch in
            watch.runID != runID && watch.sessionID == session && watch.format == format && snapshot.runs.contains { $0.id == watch.runID && $0.status == .active }
        }) else { throw StoreError.conflict("this session is already linked to another active run; unlink it first") }
        let offset = try file.seekToEnd()
        // Start at EOF: attaching never replays historical task completions.
        let watch = SessionWatch(runID: runID, sourcePath: path, format: format, sessionID: session, offset: offset,
                                 fileIdentity: try identity(path), anchor: try anchor(file, offset: offset), status: run.status == .active ? "Watching — waiting for new session output" : "Stopped — run is not active")
        watches.removeAll { $0.runID == runID }; watches.append(watch)
        try save(watches)
        return watch
    }

    public func unlink(runID: String) throws {
        let descriptor = try lock(); defer { unlock(descriptor) }
        var watches = try load(); watches.removeAll { $0.runID == runID }; try save(watches)
    }

    public func reports() throws -> [SessionWatch] {
        let descriptor = try lock(); defer { unlock(descriptor) }
        return try load()
    }

    public func poll() async throws -> [SessionWatch] {
        // Nonblocking sidecar lock also prevents two app instances replaying
        // the same batch. Store event IDs make a crash before checkpoint safe.
        let descriptor = try lock(); defer { unlock(descriptor) }
        var watches = try load()
        let before = watches
        let snapshot = try await store.read()
        for index in watches.indices {
            guard let run = snapshot.runs.first(where: { $0.id == watches[index].runID }), run.status == .active else {
                watches[index].status = "Stopped — run is not active"; continue
            }
            do { watches[index] = try await consume(watches[index]) }
            catch { watches[index].status = "Cannot watch: \(error.localizedDescription)" }
        }
        if watches != before { try save(watches) }
        return watches
    }

    private func consume(_ original: SessionWatch) async throws -> SessionWatch {
        var watch = original
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: watch.sourcePath)); defer { try? file.close() }
        let fileID = try identity(watch.sourcePath)
        let size = try file.seekToEnd()
        guard try sourceSession(file, format: watch.format) == watch.sessionID else { throw StoreError.conflict("session identity changed; relink the correct session") }
        let anchorChanged = size >= watch.offset ? try anchor(file, offset: watch.offset) != watch.anchor : true
        if fileID != watch.fileIdentity || size < watch.offset || anchorChanged {
            watch.fileIdentity = fileID; watch.offset = size; watch.anchor = try anchor(file, offset: size)
            watch.status = "Source replaced/truncated — watching new output; history skipped"
            return watch
        }
        guard size > watch.offset else {
            if watch.status.hasPrefix("Cannot watch:") { watch.status = "Watching — source recovered" }
            return watch
        }
        try file.seek(toOffset: watch.offset)
        let chunk = try file.read(upToCount: maxChunk) ?? Data()
        guard let lastNewline = chunk.lastIndex(of: 10) else {
            if chunk.count == maxChunk { throw StoreError.conflict("session record exceeds 2 MiB; relink after that record completes") }
            watch.status = "Watching — awaiting a complete session record"
            return watch
        }
        var observations: [SessionObservation] = []
        var consumed = 0
        var malformed = false
        for part in chunk[...lastNewline].split(separator: 10, omittingEmptySubsequences: false).dropLast() {
            let data = Data(part)
            let sourceOffset = watch.offset + UInt64(consumed)
            consumed += data.count + 1
            guard !data.isEmpty else { continue }
            let eventID = "watch:\(watch.runID):\(watch.sessionID):\(sourceOffset):\(digest(data))"
            do {
                if let observation = try SessionObservationParser.parse(data, format: watch.format, sessionID: watch.sessionID, eventID: eventID) {
                    observations.append(observation)
                }
            } catch { malformed = true }
        }
        // Coalesce routine activity in each batch, retaining all explicit
        // completion assertions and the most recent actual activity record.
        let latest = observations.last
        let batch = observations.filter { !$0.completions.isEmpty || $0.id == latest?.id }
        try await store.observe(runID: watch.runID, observations: batch, source: "\(watch.format.rawValue) session \(watch.sessionID)")
        watch.offset += UInt64(consumed)
        watch.anchor = try anchor(file, offset: watch.offset)
        watch.status = malformed ? "Watching — skipped a malformed record" : "Watching session output"
        if let latest {
            watch.lastObservedAt = latest.occurredAt
            watch.lastSummary = latest.message
        }
        return watch
    }

    private func sourceSession(_ file: FileHandle, format: SessionFormat) throws -> String {
        try file.seek(toOffset: 0)
        let header = try file.read(upToCount: 256 * 1024) ?? Data()
        for line in header.split(separator: 10) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let id = SessionObservationParser.identity(record, format: format), !id.isEmpty { return id }
        }
        throw StoreError.conflict("unsupported \(format.rawValue) session header; source must contain its session ID")
    }

    private func identity(_ path: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StoreError.conflict("source must be a regular file") }
        return "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
    }

    private func anchor(_ file: FileHandle, offset: UInt64) throws -> String {
        let count = min(offset, 128)
        try file.seek(toOffset: offset - count)
        return digest(try file.read(upToCount: Int(count)) ?? Data())
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func lock() throws -> Int32 {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(stateURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return descriptor
    }

    private func unlock(_ descriptor: Int32) { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
    private func load() throws -> [SessionWatch] {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SessionWatch].self, from: Data(contentsOf: stateURL))
    }
    private func save(_ watches: [SessionWatch]) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(watches).write(to: stateURL, options: .atomic)
    }
}
