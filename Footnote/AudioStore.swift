import Foundation

/// On-disk location for recorded audio. Files live under Documents/Recordings and are referenced by
/// relative file name from the `Recording` model so they survive container path changes.
enum AudioStore {
    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Recordings", isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: recordingsDirectory, withIntermediateDirectories: true)
    }

    static func newFileName() -> String {
        "rec-\(UUID().uuidString).m4a"
    }

    static func url(for fileName: String) -> URL {
        recordingsDirectory.appendingPathComponent(fileName)
    }

    static func deleteAll() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }
}
