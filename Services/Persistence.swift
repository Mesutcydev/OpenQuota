import Foundation

/// One point on an account's usage sparkline.
struct HistoryPoint: Codable, Hashable, Identifiable {
    var id: Date { date }
    var date: Date
    var value: Double
    var unit: MetricUnit
    /// Share of the allowance consumed at this moment, when there is a limit.
    /// Optional so history written before pace forecasts still decodes.
    var fraction: Double? = nil
    /// Balance left at this moment, for burn-rate projection.
    var remaining: Double? = nil
}

/// Plain JSON files in Application Support. There is no server and no sync —
/// everything the app knows lives on the device.
///
/// Writes are serialised onto a background queue: history is rewritten on
/// every successful refresh, and encoding a few hundred points on the main
/// thread would land in the middle of a scroll or a pull-to-refresh animation.
/// Reads stay synchronous and only ever happen at launch, before any write
/// from this session can be in flight.
enum Persistence {
    private static let writeQueue = DispatchQueue(
        label: "ai.openquota.persistence", qos: .utility)

    private static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("OpenQuota", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Never let the next save overwrite a file we could not read —
            // for accounts.json that would orphan every keychain entry. Keep
            // the unreadable copy aside for recovery.
            let aside = directory.appendingPathComponent(file + ".corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        let folder = directory
        writeQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(
                to: folder.appendingPathComponent(file), options: .atomic)
        }
    }
}
