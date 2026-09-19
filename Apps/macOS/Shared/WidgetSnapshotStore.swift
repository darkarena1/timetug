import Foundation
import TimeTugCore

/// Reads and writes the agenda snapshot in the App Group container. The app writes; widgets read.
struct WidgetSnapshotStore {
    enum StoreError: Error { case noContainer }

    static let fileName = "agenda-snapshot.json"

    let directory: URL?

    init(directory: URL? = AppGroup.containerURL) { self.directory = directory }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func write(_ snapshot: WidgetSnapshot) throws {
        guard let fileURL else { throw StoreError.noContainer }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
