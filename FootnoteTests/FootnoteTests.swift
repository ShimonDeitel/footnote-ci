import XCTest
@testable import Footnote

final class FootnoteTests: XCTestCase {

    // MARK: AIClient JSON parsing (robust to field-name variants + missing fields)

    func testStructuredResultDecodesCanonical() throws {
        let json = """
        {
          "title": "Q3 Pricing Review",
          "summary": "Aligned on the $12 tier.",
          "decisions": ["Launch the $12 tier"],
          "actionItems": [{"text": "Send deck", "owner": "You", "due": "2025-07-01"}],
          "openQuestions": ["Grandfather annual users?"],
          "buriedPromise": "Send pricing deck Friday."
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(StructuredResult.self, from: json)
        XCTAssertEqual(r.title, "Q3 Pricing Review")
        XCTAssertEqual(r.summary, "Aligned on the $12 tier.")
        XCTAssertEqual(r.decisions, ["Launch the $12 tier"])
        XCTAssertEqual(r.actionItems.count, 1)
        XCTAssertEqual(r.actionItems.first?.owner, "You")
        XCTAssertEqual(r.actionItems.first?.due, "2025-07-01")
        XCTAssertEqual(r.buriedPromise, "Send pricing deck Friday.")
        XCTAssertTrue(r.isUsable)
    }

    func testStructuredResultDecodesAlternateFieldNames() throws {
        // The spec prompt uses `oneLineSummary` and `dueDate`; the client should tolerate both.
        let json = """
        {
          "title": "Standup",
          "oneLineSummary": "Shipped the fix.",
          "decisions": [],
          "actionItems": [{"text": "Ship", "dueDate": "2025-07-02"}],
          "openQuestions": []
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(StructuredResult.self, from: json)
        XCTAssertEqual(r.summary, "Shipped the fix.")
        XCTAssertEqual(r.actionItems.first?.due, "2025-07-02")
    }

    func testEmptyResultIsNotUsable() throws {
        let json = """
        {"title": "", "summary": "", "decisions": [], "actionItems": [], "openQuestions": []}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(StructuredResult.self, from: json)
        XCTAssertFalse(r.isUsable)
    }

    // MARK: Citation Codable round-trip

    func testCitationRoundTrip() throws {
        let c = Citation(recordingID: UUID(), segmentStart: 42.5, snippet: "hello")
        let data = try JSONEncoder().encode([c])
        let back = try JSONDecoder().decode([Citation].self, from: data)
        XCTAssertEqual(back.first?.segmentStart, 42.5)
        XCTAssertEqual(back.first?.snippet, "hello")
    }

    // MARK: Time formatting

    func testClockFormatting() {
        XCTAssertEqual(TimeFmt.clock(0), "0:00")
        XCTAssertEqual(TimeFmt.clock(65), "1:05")
        XCTAssertEqual(TimeFmt.clock(3661), "1:01:01")
    }

    // MARK: Context mapping

    func testContextLabels() {
        XCTAssertEqual(RecordingContext.oneOnOne.label, "1:1")
        XCTAssertEqual(RecordingContext.meeting.symbol, "person.3.fill")
        XCTAssertEqual(RecordingContext(rawValue: "lecture"), .lecture)
    }
}
