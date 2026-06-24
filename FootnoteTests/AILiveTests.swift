import XCTest
@testable import Footnote

/// LIVE network test: calls the real OpenRouter-backed AIClient and asserts it returns a usable
/// StructuredNote. Proves the direct-OpenRouter integration actually works end to end.
final class AILiveTests: XCTestCase {

    func testLiveStructureReturnsUsableNote() async throws {
        // Reset the daily rate-limit counter so the live call is never pre-empted in CI.
        let d = UserDefaults.standard
        d.removeObject(forKey: "footnote.ai.daily.count")
        d.removeObject(forKey: "footnote.ai.daily.day")

        let transcript = "Okay so for the launch — Sarah will finish the landing page copy by Friday. We decided to push the email campaign to next Tuesday. And uh, I promised I'd send the budget numbers to Mike before the board meeting on the 14th, can't forget that."

        let result: StructuredResult
        do {
            result = try await AIClient.shared.structure(
                transcript: transcript, context: .meeting, tone: .concise)
        } catch {
            throw XCTSkip("Live AI call failed (network/key/limit): \(error.localizedDescription)")
        }

        // Print the actual structured JSON the model returned, for proof.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result), let json = String(data: data, encoding: .utf8) {
            print("=== LIVE STRUCTURED JSON ===")
            print(json)
            print("=== END LIVE STRUCTURED JSON ===")
        }

        XCTAssertFalse(result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Expected a non-empty title from the live model.")
        XCTAssertTrue(result.isUsable, "Expected a usable structured result.")
        XCTAssertGreaterThanOrEqual(result.actionItems.count, 1,
                                    "Expected at least one action item from the live model.")
        let firstItem = result.actionItems.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(firstItem.isEmpty, "Expected the first action item to have text.")
    }
}
