import XCTest
import SwiftData
@testable import Footnote

/// In-memory model + logic tests for the structuring and rollup flows.
@MainActor
final class FootnoteLogicTests: XCTestCase {

    private func makeModel() -> AppModel {
        let schema = Schema([Recording.self, TranscriptSegment.self, StructuredNote.self,
                             ActionItem.self, AskTurn.self])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: cfg)
        return AppModel(container: container)
    }

    func testCreateRecordingPersistsSegments() {
        let m = makeModel()
        let rec = m.createRecording(context: .call, duration: 30, audioFileName: "x.m4a",
                                    transcript: "hello world",
                                    segments: [("hello", 0, 1), ("world", 1, 2)])
        XCTAssertEqual(rec.context, .call)
        XCTAssertEqual(rec.orderedSegments.count, 2)
        XCTAssertEqual(m.allRecordings().count, 1)
        XCTAssertNotNil(m.recording(id: rec.id))
    }

    func testActionItemRollupSortsByDueDate() {
        let m = makeModel()
        let rec = m.createRecording(context: .meeting, duration: 10, audioFileName: "",
                                    transcript: "t", segments: [])
        let note = StructuredNote(title: "T", oneLineSummary: "s")
        note.recording = rec
        m.context.insert(note)
        rec.note = note

        let soon = ActionItem(text: "soon", dueDate: Date().addingTimeInterval(100))
        let later = ActionItem(text: "later", dueDate: Date().addingTimeInterval(10_000))
        let undated = ActionItem(text: "undated", dueDate: nil)
        for i in [soon, later, undated] { i.note = note; m.context.insert(i) }
        note.actionItems = [later, undated, soon]
        try? m.context.save()

        let open = m.openActionItems()
        XCTAssertEqual(open.first?.text, "soon")
        XCTAssertEqual(open.dropFirst().first?.text, "later")
    }

    func testToggleMarksDone() {
        let m = makeModel()
        let note = StructuredNote()
        m.context.insert(note)
        let item = ActionItem(text: "do it")
        item.note = note
        m.context.insert(item)
        try? m.context.save()

        XCTAssertEqual(m.openActionItems().count, 1)
        m.toggle(item)
        XCTAssertEqual(m.openActionItems().count, 0)
        XCTAssertEqual(m.completedActionItemsCount(), 1)
    }

    func testBuriedPromisesCollected() {
        let m = makeModel()
        let rec = m.createRecording(context: .meeting, duration: 10, audioFileName: "",
                                    transcript: "t", segments: [])
        let note = StructuredNote(title: "T", buriedPromise: "Send the deck Friday")
        note.recording = rec
        m.context.insert(note)
        rec.note = note
        try? m.context.save()

        let promises = m.buriedPromises()
        XCTAssertEqual(promises.count, 1)
        XCTAssertEqual(promises.first?.promise, "Send the deck Friday")
    }

    func testAskHistoryPersists() {
        let m = makeModel()
        m.recordAsk(question: "what did I promise?", answer: "to send the deck",
                    citations: [Citation(recordingID: UUID(), segmentStart: 5, snippet: "deck")])
        let turns = m.askTurns()
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.citations.count, 1)
        m.clearAskHistory()
        XCTAssertTrue(m.askTurns().isEmpty)
    }

    func testLocalRetrievalScoresOverlap() {
        let m = makeModel()
        _ = m.createRecording(context: .meeting, duration: 10, audioFileName: "",
                              transcript: "we discussed the new pricing tier and design budget",
                              segments: [("we discussed the new pricing tier", 0, 5),
                                         ("and the design budget", 5, 8)])
        let chunks = ArchiveRetriever.retrieve(query: "pricing tier", appModel: m)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.first?.text.contains("pricing") ?? false)
    }

    func testMarkdownExportContainsSections() {
        let m = makeModel()
        let rec = m.createRecording(context: .meeting, duration: 60, audioFileName: "",
                                    transcript: "raw transcript", segments: [])
        let note = StructuredNote(title: "Pricing", oneLineSummary: "Aligned.",
                                  decisions: ["Launch $12"], buriedPromise: "Send deck")
        note.recording = rec
        m.context.insert(note)
        rec.note = note
        let item = ActionItem(text: "Send deck", owner: "You")
        item.note = note
        m.context.insert(item)
        note.actionItems = [item]
        try? m.context.save()

        let md = MarkdownExport.note(rec)
        XCTAssertTrue(md.contains("# Pricing"))
        XCTAssertTrue(md.contains("## Decisions"))
        XCTAssertTrue(md.contains("## Action Items"))
        XCTAssertTrue(md.contains("Buried Promise"))
    }
}
