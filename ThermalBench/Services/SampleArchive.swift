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

    static var runsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Silemetry/Runs", isDirectory: true)
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
        let path = run.dataDirectory
        guard !path.isEmpty else { return [] }

        // New format: absolute path to samples.jsonl
        if path.hasPrefix("/") {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let decoded = decodeJSONL(data)
                if !decoded.isEmpty { return decoded }
            }
        }

        // Legacy format: inline JSON array
        guard let json = path.data(using: .utf8),
              let samples = try? decoder.decode([TelemetrySample].self, from: json) else {
            return []
        }
        return samples
    }

    static func decodeJSONL(_ data: Data) -> [TelemetrySample] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [TelemetrySample] = []
        out.reserveCapacity(text.count / 200)
        for line in text.split(separator: "\n") {
            if let s = try? decoder.decode(TelemetrySample.self, from: Data(line.utf8)) {
                out.append(s)
            }
        }
        return out
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
}
