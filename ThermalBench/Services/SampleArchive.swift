// ThermalBench - Sample Archive
// Streams raw telemetry samples to per-run JSONL files on disk instead of
// inlining the whole array into SwiftData. Long tests no longer drop the
// oldest samples and the database stays small.
//
// Layout: <Application Support>/Silemetry/Runs/<uuid>/samples.jsonl
// One TelemetrySample JSON per line. Legacy runs (inline JSON in
// RunRecord.dataDirectory) remain readable via load(from:).
import Foundation

enum SampleArchive {

    /// Flush buffer size — kept small so disk writes stay cheap and bounded.
    static let batchSize = 500

    /// Diagnostics for an archive load — lets callers cross-check the file on
    /// disk against the stored summary instead of trusting the stored status.
    struct ArchiveLoadResult {
        let samples: [TelemetrySample]
        let totalLines: Int
        let malformedLines: Int
        let fileExists: Bool
        /// Non-nil when the file could not be read (I/O error mid-stream).
        let readError: String?
        /// True when the run is file-backed (new format) rather than inline JSON.
        let isFileBacked: Bool

        /// Runtime-effective raw-data status: a stored "complete" is downgraded
        /// when the file disagrees with the summary.
        /// - missing / unreadable file → unavailable (nothing to draw)
        /// - malformed, truncated, or duplicated lines → partial
        /// - legacy inline runs cannot be cross-checked → stored status
        func effectiveRawStatus(stored: RawDataStatus, expectedSamples: Int) -> RawDataStatus {
            guard isFileBacked else { return stored }
            guard stored == .complete else { return stored }
            if !fileExists || readError != nil { return .unavailable }
            if malformedLines > 0 || totalLines != expectedSamples { return .partial }
            return .complete
        }
    }

    static var runsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Silemetry/Runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Staging area for delete transactions: sample directories are moved here
    /// before the SwiftData record is deleted, then purged on success or
    /// restored on failure so DB and files never diverge permanently.
    static var trashDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Silemetry/Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func directory(for uuid: String) -> URL {
        runsDirectory.appendingPathComponent(uuid, isDirectory: true)
    }

    static func samplesFile(for uuid: String) -> URL {
        directory(for: uuid).appendingPathComponent("samples.jsonl")
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Append a batch of samples to the run's JSONL file (creates dir/file).
    /// Throws on failure so callers never silently lose data.
    static func append(_ samples: [TelemetrySample], uuid: String) throws {
        guard !samples.isEmpty else { return }
        let dir = directory(for: uuid)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = samplesFile(for: uuid)
        let lines = try samples.map { try encoder.encode($0) }
            .map { String(data: $0, encoding: .utf8) ?? "" }
        guard !lines.isEmpty else { return }
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        if let fh = try? FileHandle(forWritingTo: file) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            try fh.write(contentsOf: data)
        } else {
            try data.write(to: file)
        }
    }

    /// Load all samples for a run. Handles both new file-backed and legacy
    /// inline-JSON storage.
    static func load(from run: RunRecord) -> [TelemetrySample] {
        load(dataDirectory: run.dataDirectory)
    }

    /// Load samples from a stored data directory string (file path for new
    /// runs, inline JSON for legacy runs). String-only so it can be called
    /// from background tasks without touching SwiftData objects.
    static func load(dataDirectory path: String) -> [TelemetrySample] {
        loadDetailed(dataDirectory: path).samples
    }

    /// Load samples plus file diagnostics (line counts, existence, read errors).
    static func loadDetailed(dataDirectory path: String) -> ArchiveLoadResult {
        guard !path.isEmpty else {
            return ArchiveLoadResult(samples: [], totalLines: 0, malformedLines: 0,
                                     fileExists: false, readError: nil, isFileBacked: false)
        }

        // New format: absolute path to samples.jsonl — stream-decode it so a
        // corrupted line never silently drops data without being counted.
        if path.hasPrefix("/") {
            let file = URL(fileURLWithPath: path)
            let exists = FileManager.default.fileExists(atPath: path)
            if exists {
                let (samples, total, malformed, readError) = decodeJSONLStreaming(file)
                return ArchiveLoadResult(samples: samples, totalLines: total, malformedLines: malformed,
                                         fileExists: true, readError: readError, isFileBacked: true)
            }
            return ArchiveLoadResult(samples: [], totalLines: 0, malformedLines: 0,
                                     fileExists: false, readError: nil, isFileBacked: true)
        }

        // Legacy format: inline JSON array
        guard let json = path.data(using: .utf8),
              let samples = try? decoder.decode([TelemetrySample].self, from: json) else {
            return ArchiveLoadResult(samples: [], totalLines: 0, malformedLines: 0,
                                     fileExists: false, readError: nil, isFileBacked: false)
        }
        return ArchiveLoadResult(samples: samples, totalLines: samples.count, malformedLines: 0,
                                 fileExists: false, readError: nil, isFileBacked: false)
    }

    /// Stream-decode a JSONL file line by line (64 KB chunks). The whole file
    /// is never materialized as one String, so peak memory stays around one
    /// line plus the decoded array — important when Compare holds two long
    /// runs at once. Returns decoded samples plus line diagnostics.
    static func decodeJSONLStreaming(_ file: URL) -> (samples: [TelemetrySample], totalLines: Int, malformedLines: Int, readError: String?) {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return ([], 0, 0, "Could not open \(file.lastPathComponent)")
        }
        defer { try? handle.close() }

        var buffer = Data()
        var out: [TelemetrySample] = []
        var total = 0, malformed = 0
        var readError: String?
        let newline = UInt8(ascii: "\n")

        while true {
            let chunk: Data
            do {
                guard let c = try handle.read(upToCount: 64 * 1024), !c.isEmpty else { break }
                chunk = c
            } catch {
                readError = "Read failed: \(error.localizedDescription)"
                break
            }
            buffer.append(chunk)
            var start = buffer.startIndex
            while let nl = buffer[start...].firstIndex(of: newline) {
                let line = buffer[start..<nl]
                if !line.isEmpty {
                    total += 1
                    autoreleasepool {
                        if let s = try? decoder.decode(TelemetrySample.self, from: line) {
                            out.append(s)
                        } else {
                            malformed += 1
                        }
                    }
                }
                start = buffer.index(after: nl)
            }
            if start < buffer.endIndex {
                buffer = Data(buffer[start...])
            } else {
                buffer.removeAll(keepingCapacity: true)
            }
        }
        // Tail line without a trailing newline
        if !buffer.isEmpty {
            total += 1
            autoreleasepool {
                if let s = try? decoder.decode(TelemetrySample.self, from: buffer) {
                    out.append(s)
                } else {
                    malformed += 1
                }
            }
        }
        return (out, total, malformed, readError)
    }

    /// Move a run's sample directory into the staging (trash) area. Returns
    /// the staged location, or nil when the run had no file-backed samples.
    /// The caller either purges it after a successful record deletion or
    /// restores it when the deletion fails — files and DB stay in sync.
    static func stageFiles(for run: RunRecord) -> URL? {
        let dir = directory(for: run.uuid)
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        let staged = trashDirectory.appendingPathComponent(run.uuid, isDirectory: true)
        // Clear a stale leftover from a crashed delete transaction.
        try? FileManager.default.removeItem(at: staged)
        do {
            try FileManager.default.moveItem(at: dir, to: staged)
            return staged
        } catch {
            print("[SampleArchive] stage failed: \(error)")
            return nil
        }
    }

    /// Permanently remove a staged directory after a successful deletion.
    static func purgeStaged(_ staged: URL?) {
        guard let staged else { return }
        try? FileManager.default.removeItem(at: staged)
    }

    /// Move a staged directory back to its canonical run location after a
    /// failed deletion — the record still exists, so its files must too.
    static func restoreStaged(_ staged: URL?) {
        guard let staged else { return }
        let dest = directory(for: staged.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: staged, to: dest)
        } catch {
            print("[SampleArchive] restore failed: \(error)")
        }
    }

    /// Remove a run's sample files (safe no-op for legacy inline storage).
    static func deleteFiles(for run: RunRecord) {
        deleteFiles(uuid: run.uuid)
        let path = run.dataDirectory
        if path.hasPrefix("/") {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        }
    }

    /// Remove sample files for a uuid (used while discarding mid-run data).
    static func deleteFiles(uuid: String) {
        try? FileManager.default.removeItem(at: samplesFile(for: uuid))
        try? FileManager.default.removeItem(at: directory(for: uuid))
    }

    /// True when the run's JSONL file exists and contains data. Used to
    /// distinguish "partial" (some writes landed) from "unavailable" (nothing
    /// was ever persisted) after an archive failure.
    static func hasData(uuid: String) -> Bool {
        let file = samplesFile(for: uuid)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attrs[.size] as? Int, size > 0 else { return false }
        return true
    }
}
