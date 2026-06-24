import Foundation
import SwiftData

// MARK: - Recording context

/// The kind of session being recorded. Tunes how the transcript is structured.
enum RecordingContext: String, CaseIterable, Identifiable, Codable {
    case meeting, lecture, call, oneOnOne

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meeting: return "Meeting"
        case .lecture: return "Lecture"
        case .call: return "Call"
        case .oneOnOne: return "1:1"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: return "person.3.fill"
        case .lecture: return "graduationcap.fill"
        case .call: return "phone.fill"
        case .oneOnOne: return "person.2.fill"
        }
    }
}

// MARK: - SwiftData models
// Every stored property has a default value and there are NO unique constraints, so the schema
// stays simple and local-only safe. Relationships use optionals / arrays with sane defaults.

/// One captured session: the audio file, its on-device transcript, and (once processed) a note.
@Model
final class Recording {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var contextRaw: String = RecordingContext.meeting.rawValue
    var durationSeconds: Double = 0
    /// Relative file name inside the app's Recordings folder (not an absolute URL, so it survives
    /// container path changes between launches).
    var audioFileName: String = ""
    var transcript: String = ""
    var isProcessed: Bool = false
    var processingError: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.recording)
    var segments: [TranscriptSegment]? = []

    @Relationship(deleteRule: .cascade, inverse: \StructuredNote.recording)
    var note: StructuredNote? = nil

    init(id: UUID = UUID(),
         createdAt: Date = .now,
         context: RecordingContext = .meeting,
         durationSeconds: Double = 0,
         audioFileName: String = "",
         transcript: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.contextRaw = context.rawValue
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.transcript = transcript
    }

    var context: RecordingContext {
        get { RecordingContext(rawValue: contextRaw) ?? .meeting }
        set { contextRaw = newValue.rawValue }
    }

    /// Absolute URL for the audio file, resolved against the current Recordings directory.
    var audioURL: URL? {
        guard !audioFileName.isEmpty else { return nil }
        return AudioStore.recordingsDirectory.appendingPathComponent(audioFileName)
    }

    var displayTitle: String {
        if let t = note?.title, !t.isEmpty { return t }
        return context.label
    }

    var durationText: String { TimeFmt.clock(durationSeconds) }

    /// Sorted segments for scrubbing / citations.
    var orderedSegments: [TranscriptSegment] {
        (segments ?? []).sorted { $0.startTime < $1.startTime }
    }
}

/// A time-stamped chunk of transcript, used for the audio scrubber sync and Ask citations.
@Model
final class TranscriptSegment {
    var id: UUID = UUID()
    var text: String = ""
    var startTime: Double = 0
    var endTime: Double = 0
    var recording: Recording? = nil

    init(id: UUID = UUID(), text: String = "", startTime: Double = 0, endTime: Double = 0) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// The structured brief produced from a transcript by the AI pass.
@Model
final class StructuredNote {
    var id: UUID = UUID()
    var title: String = ""
    var oneLineSummary: String = ""
    var decisions: [String] = []
    var openQuestions: [String] = []
    var buriedPromise: String? = nil
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ActionItem.note)
    var actionItems: [ActionItem]? = []

    var recording: Recording? = nil

    init(id: UUID = UUID(),
         title: String = "",
         oneLineSummary: String = "",
         decisions: [String] = [],
         openQuestions: [String] = [],
         buriedPromise: String? = nil,
         createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.oneLineSummary = oneLineSummary
        self.decisions = decisions
        self.openQuestions = openQuestions
        self.buriedPromise = buriedPromise
        self.createdAt = createdAt
    }

    var orderedActionItems: [ActionItem] {
        (actionItems ?? []).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}

/// A single actionable to-do extracted from a note. Surfaced both inside the note and rolled up
/// across the whole archive in the Commitments tab.
@Model
final class ActionItem {
    var id: UUID = UUID()
    var text: String = ""
    var owner: String? = nil
    var dueDate: Date? = nil
    var isDone: Bool = false
    var sourceSegmentStart: Double? = nil
    var createdAt: Date = Date.now
    var note: StructuredNote? = nil

    init(id: UUID = UUID(),
         text: String = "",
         owner: String? = nil,
         dueDate: Date? = nil,
         isDone: Bool = false,
         sourceSegmentStart: Double? = nil,
         createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.owner = owner
        self.dueDate = dueDate
        self.isDone = isDone
        self.sourceSegmentStart = sourceSegmentStart
        self.createdAt = createdAt
    }

    var ownerChip: String? {
        guard let owner, !owner.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return owner
    }
}

/// A Codable citation pointing back to a specific recording + moment.
struct Citation: Codable, Hashable, Identifiable {
    var id = UUID()
    var recordingID: UUID
    var segmentStart: Double
    var snippet: String

    enum CodingKeys: String, CodingKey { case recordingID, segmentStart, snippet }
}

/// One question/answer turn in the Ask tab, persisted so the archive conversation survives launches.
@Model
final class AskTurn {
    var id: UUID = UUID()
    var question: String = ""
    var answer: String = ""
    /// Citations stored as Codable JSON (kept simple for the local store).
    var citationsData: Data = Data()
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), question: String = "", answer: String = "",
         citations: [Citation] = [], createdAt: Date = .now) {
        self.id = id
        self.question = question
        self.answer = answer
        self.citationsData = (try? JSONEncoder().encode(citations)) ?? Data()
        self.createdAt = createdAt
    }

    var citations: [Citation] {
        get { (try? JSONDecoder().decode([Citation].self, from: citationsData)) ?? [] }
        set { citationsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

// MARK: - Time formatting helpers

enum TimeFmt {
    /// "m:ss" or "h:mm:ss" for a duration in seconds.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func due(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }
}
