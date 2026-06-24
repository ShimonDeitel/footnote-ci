import Foundation
import SwiftData
import SwiftUI

/// App state: owns the LOCAL-ONLY SwiftData store, runs the structuring pipeline (transcript ->
/// AIClient -> StructuredNote), and exposes cross-archive rollups for the Commitments tab. Pro is
/// always read from `store` (StoreKit), never persisted here.
@MainActor
final class AppModel: ObservableObject {
    let container: ModelContainer
    weak var store: Store?

    /// Notes the free tier has structured, by recording id — used to enforce the rolling free limit.
    @Published private(set) var lastProcessedError: String?

    /// Free tier may structure this many recordings before Pro is required.
    static let freeStructureLimit = 5

    private let kFreeStructured = "footnote.free.structuredCount"

    init(container: ModelContainer) {
        self.container = container
        AudioStore.ensureDirectory()
        #if DEBUG
        seedIfRequested()
        #endif
    }

    // MARK: Container (LOCAL-ONLY — no CloudKit, no iCloud entitlement)

    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Recording.self, TranscriptSegment.self, StructuredNote.self,
            ActionItem.self, AskTurn.self
        ])
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: local) { return c }
        // Last resort so the app never crashes on launch: in-memory store.
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }

    var context: ModelContext { container.mainContext }

    // MARK: Recordings

    func allRecordings() -> [Recording] {
        let d = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func recording(id: UUID) -> Recording? {
        let d = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(d))?.first
    }

    /// Insert a freshly captured recording (audio already written to disk by the recorder).
    @discardableResult
    func createRecording(context ctx: RecordingContext,
                         duration: Double,
                         audioFileName: String,
                         transcript: String,
                         segments: [(text: String, start: Double, end: Double)]) -> Recording {
        let rec = Recording(context: ctx, durationSeconds: duration,
                            audioFileName: audioFileName, transcript: transcript)
        self.context.insert(rec)
        var segs: [TranscriptSegment] = []
        for s in segments {
            let seg = TranscriptSegment(text: s.text, startTime: s.start, endTime: s.end)
            seg.recording = rec
            self.context.insert(seg)
            segs.append(seg)
        }
        rec.segments = segs
        try? self.context.save()
        return rec
    }

    func deleteRecording(_ rec: Recording) {
        if let url = rec.audioURL { try? FileManager.default.removeItem(at: url) }
        context.delete(rec)
        try? context.save()
    }

    // MARK: Structuring pipeline

    /// True when the free tier still has structuring credits left (or the user is Pro).
    var canStructureForFree: Bool {
        if store?.isPro == true { return true }
        return freeStructuredCount < Self.freeStructureLimit
    }

    var freeStructuredCount: Int { UserDefaults.standard.integer(forKey: kFreeStructured) }
    var freeStructuredRemaining: Int { max(0, Self.freeStructureLimit - freeStructuredCount) }

    /// Run the AI structuring pass for a recording. On any failure the recording is still saved with
    /// its raw transcript and a gentle error message — the app is never bricked.
    func structure(_ rec: Recording, tone: StructuringTone) async {
        lastProcessedError = nil

        // Gate: free tier has a rolling limit; Pro is unlimited.
        if store?.isPro != true, freeStructuredCount >= Self.freeStructureLimit {
            rec.isProcessed = true
            rec.processingError = "Free structuring limit reached. Upgrade to Footnote Pro to auto-structure every recording."
            try? context.save()
            return
        }

        let transcript = rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            rec.isProcessed = true
            rec.processingError = "Nothing was transcribed. Here is the empty recording — you can re-record any time."
            try? context.save()
            return
        }

        do {
            let result = try await AIClient.shared.structure(
                transcript: transcript, context: rec.context, tone: tone)
            applyStructuredResult(result, to: rec)
            if store?.isPro != true {
                UserDefaults.standard.set(freeStructuredCount + 1, forKey: kFreeStructured)
            }
        } catch AIError.rateLimited {
            // Per-user daily AI cap hit: keep the transcript, tell the user it resets tomorrow.
            rec.processingError = "Daily AI limit reached — resets tomorrow. Here's your full transcript in the meantime."
            lastProcessedError = rec.processingError
        } catch {
            // Graceful fallback: keep the transcript, tell the user softly.
            rec.processingError = "Couldn't auto-structure this one — here's your full transcript. Tap to retry."
            lastProcessedError = rec.processingError
        }
        rec.isProcessed = true
        try? context.save()
    }

    private func applyStructuredResult(_ r: StructuredResult, to rec: Recording) {
        let note = StructuredNote(
            title: r.title.isEmpty ? rec.context.label : r.title,
            oneLineSummary: r.summary,
            decisions: r.decisions,
            openQuestions: r.openQuestions,
            buriedPromise: r.buriedPromise?.isEmpty == true ? nil : r.buriedPromise)
        note.recording = rec
        context.insert(note)

        var items: [ActionItem] = []
        for a in r.actionItems {
            let item = ActionItem(text: a.text, owner: a.owner,
                                  dueDate: parseDue(a.due))
            item.note = note
            context.insert(item)
            items.append(item)
        }
        note.actionItems = items
        rec.note = note
        rec.processingError = nil
    }

    /// Best-effort parse of a loose due-date string (ISO date or natural-ish "2025-07-01").
    private func parseDue(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        for fmt in ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d, yyyy", "MMMM d, yyyy"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    // MARK: Cross-archive rollups (Commitments tab)

    /// Every open (not done) action item across the whole archive, sorted by due date.
    func openActionItems() -> [ActionItem] {
        let d = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.isDone == false })
        let items = (try? context.fetch(d)) ?? []
        return items.sorted {
            ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt)
        }
    }

    func completedActionItemsCount() -> Int {
        let d = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.isDone == true })
        return (try? context.fetchCount(d)) ?? 0
    }

    /// Every buried promise across the archive (note + promise text).
    func buriedPromises() -> [(note: StructuredNote, promise: String)] {
        let d = FetchDescriptor<StructuredNote>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let notes = (try? context.fetch(d)) ?? []
        return notes.compactMap { n in
            guard let p = n.buriedPromise, !p.isEmpty else { return nil }
            return (n, p)
        }
    }

    func toggle(_ item: ActionItem) {
        item.isDone.toggle()
        try? context.save()
    }

    // MARK: Ask history

    func askTurns() -> [AskTurn] {
        let d = FetchDescriptor<AskTurn>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(d)) ?? []
    }

    func recordAsk(question: String, answer: String, citations: [Citation]) {
        let turn = AskTurn(question: question, answer: answer, citations: citations)
        context.insert(turn)
        try? context.save()
    }

    func clearAskHistory() {
        for t in askTurns() { context.delete(t) }
        try? context.save()
    }

    // MARK: Delete all data

    func deleteAllData() {
        try? context.delete(model: Recording.self)
        try? context.delete(model: TranscriptSegment.self)
        try? context.delete(model: StructuredNote.self)
        try? context.delete(model: ActionItem.self)
        try? context.delete(model: AskTurn.self)
        try? context.save()
        AudioStore.deleteAll()
        UserDefaults.standard.removeObject(forKey: kFreeStructured)
    }

    // MARK: Stats (for Settings + empty states)

    var totalRecordings: Int {
        (try? context.fetchCount(FetchDescriptor<Recording>())) ?? 0
    }

    // MARK: DEBUG seeding (compiled out of Release)

    #if DEBUG
    private func seedIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["FOOTNOTE_SEED"] == "1" else { return }
        let ctx = context
        if ((try? ctx.fetch(FetchDescriptor<Recording>()))?.isEmpty ?? true) {
            let rec = Recording(context: .meeting, durationSeconds: 1432,
                                audioFileName: "", transcript: SampleData.transcript)
            ctx.insert(rec)
            let seg = TranscriptSegment(text: SampleData.transcript, startTime: 0, endTime: 1432)
            seg.recording = rec; ctx.insert(seg); rec.segments = [seg]

            let note = StructuredNote(
                title: "Q3 Pricing Review",
                oneLineSummary: "Team aligned on a $12 tier and agreed to ship the new paywall before the 15th.",
                decisions: ["Launch the $12 mid tier", "Keep the free plan capped at 5 notes"],
                openQuestions: ["Do we grandfather existing annual users?"],
                buriedPromise: "You promised to send the updated pricing deck to the design team by Friday.")
            note.recording = rec; ctx.insert(note)
            let a1 = ActionItem(text: "Send updated pricing deck to design", owner: "You",
                                dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now))
            let a2 = ActionItem(text: "Draft grandfathering policy", owner: "Priya",
                                dueDate: Calendar.current.date(byAdding: .day, value: 5, to: .now))
            a1.note = note; a2.note = note; ctx.insert(a1); ctx.insert(a2)
            note.actionItems = [a1, a2]
            rec.note = note; rec.isProcessed = true
            try? ctx.save()
        }
    }

    enum SampleData {
        static let transcript = "Okay so the main thing today is the Q3 pricing. We looked at the numbers and the twelve dollar tier tested best. Let's launch it. Free plan stays capped at five notes. One open question is whether we grandfather the existing annual users. Oh and I'll send the updated pricing deck to the design team by Friday."
    }
    #endif
}

// MARK: - Structuring tone (Pro control)

enum StructuringTone: String, CaseIterable, Identifiable, Codable {
    case concise, detailed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
