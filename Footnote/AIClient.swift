import Foundation

// MARK: - Configuration

/// DIRECT mode: the app talks to OpenRouter's chat-completions API itself. The key is embedded in
/// the app (owner-approved, free key). Only transcript TEXT and question/context are ever sent —
/// never audio. The model is instructed to return ONLY a JSON object matching the decoder's shape.
enum AIConfig {
    /// OpenRouter chat-completions endpoint.
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Embedded OpenRouter key (owner-approved, free key).
    static let apiKey = "__OPENROUTER_KEY__"

    /// Model used for both structuring and Ask.
    static let model = "openai/gpt-4o-mini"

    static let structureMaxTokens = 1200
    static let askMaxTokens = 800
    static let temperature = 0.2

    /// Network timeout so a stalled call can never hang the structuring UI forever.
    static let timeout: TimeInterval = 30

    /// Per-user, app-side daily cap on AI calls. Successful calls count against it.
    static let dailyCallLimit = 25
}

// MARK: - Wire types (what the model returns inside choices[0].message.content)

struct StructuredResult: Codable {
    var title: String
    var summary: String
    var decisions: [String]
    var actionItems: [WireActionItem]
    var openQuestions: [String]
    var buriedPromise: String?

    enum CodingKeys: String, CodingKey {
        case title, summary, decisions, actionItems, openQuestions, buriedPromise
        // Tolerate the alternate field name from the spec's prompt.
        case oneLineSummary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary))
            ?? (try? c.decode(String.self, forKey: .oneLineSummary)) ?? ""
        decisions = (try? c.decode([String].self, forKey: .decisions)) ?? []
        actionItems = (try? c.decode([WireActionItem].self, forKey: .actionItems)) ?? []
        openQuestions = (try? c.decode([String].self, forKey: .openQuestions)) ?? []
        buriedPromise = try? c.decode(String.self, forKey: .buriedPromise)
    }

    // Encoding kept for tests / round-trips.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(decisions, forKey: .decisions)
        try c.encode(actionItems, forKey: .actionItems)
        try c.encode(openQuestions, forKey: .openQuestions)
        try c.encodeIfPresent(buriedPromise, forKey: .buriedPromise)
    }

    init(title: String, summary: String, decisions: [String],
         actionItems: [WireActionItem], openQuestions: [String], buriedPromise: String?) {
        self.title = title
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.buriedPromise = buriedPromise
    }

    /// Validate that the structured result is non-degenerate enough to render as a real note.
    var isUsable: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !decisions.isEmpty || !actionItems.isEmpty
    }
}

struct WireActionItem: Codable {
    var text: String = ""
    var owner: String? = nil
    var due: String? = nil

    enum CodingKeys: String, CodingKey { case text, owner, due, dueDate }

    init(text: String = "", owner: String? = nil, due: String? = nil) {
        self.text = text; self.owner = owner; self.due = due
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        owner = try? c.decode(String.self, forKey: .owner)
        due = (try? c.decode(String.self, forKey: .due))
            ?? (try? c.decode(String.self, forKey: .dueDate))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(owner, forKey: .owner)
        try c.encodeIfPresent(due, forKey: .due)
    }
}

/// Grounded answer for the Ask tab.
struct AskResult: Codable {
    var answer: String = ""
    var citations: [WireCitation] = []
}

struct WireCitation: Codable {
    var recordingID: String = ""
    var segmentStart: Double = 0
    var snippet: String = ""

    enum CodingKeys: String, CodingKey { case recordingID, segmentStart, snippet }

    init(recordingID: String = "", segmentStart: Double = 0, snippet: String = "") {
        self.recordingID = recordingID
        self.segmentStart = segmentStart
        self.snippet = snippet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordingID = (try? c.decode(String.self, forKey: .recordingID)) ?? ""
        // The model may return the timestamp as a number or a string.
        if let d = try? c.decode(Double.self, forKey: .segmentStart) {
            segmentStart = d
        } else if let s = try? c.decode(String.self, forKey: .segmentStart) {
            segmentStart = Double(s) ?? 0
        } else {
            segmentStart = 0
        }
        snippet = (try? c.decode(String.self, forKey: .snippet)) ?? ""
    }
}

// MARK: - Errors

enum AIError: Error, LocalizedError {
    case badResponse
    case http(Int)
    case decoding
    case unusable
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .badResponse: return "No response from the structuring service."
        case .http(let code): return "Structuring service returned \(code)."
        case .decoding: return "Couldn't read the structured result."
        case .unusable: return "The structured result was empty."
        case .rateLimited: return "Daily AI limit reached — resets tomorrow."
        }
    }
}

// MARK: - Daily rate limit (per-user, app-side)

/// Simple UserDefaults daily cap on AI calls, keyed by yyyy-MM-dd. Successful calls increment it.
/// When the cap is exceeded the client throws `.rateLimited` before any network call is made.
enum AIRateLimiter {
    private static let countKey = "footnote.ai.daily.count"
    private static let dayKey = "footnote.ai.daily.day"

    private static var today: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Reset the counter when the day rolls over.
    private static func rollIfNeeded(_ d: UserDefaults) {
        if d.string(forKey: dayKey) != today {
            d.set(today, forKey: dayKey)
            d.set(0, forKey: countKey)
        }
    }

    /// Current number of AI calls used today.
    static func usedToday(_ d: UserDefaults = .standard) -> Int {
        rollIfNeeded(d)
        return d.integer(forKey: countKey)
    }

    /// True if another AI call is allowed today.
    static func canCall(_ d: UserDefaults = .standard) -> Bool {
        usedToday(d) < AIConfig.dailyCallLimit
    }

    /// Record a successful AI call against today's quota.
    static func recordCall(_ d: UserDefaults = .standard) {
        rollIfNeeded(d)
        d.set(d.integer(forKey: countKey) + 1, forKey: countKey)
    }
}

// MARK: - OpenRouter wire envelope

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatRequest: Encodable {
    struct ResponseFormat: Encodable { let type: String }
    let model: String
    let messages: [ChatMessage]
    let response_format: ResponseFormat
    let max_tokens: Int
    let temperature: Double
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
    }
    let choices: [Choice]
}

// MARK: - Client

/// Calls OpenRouter directly with the embedded key, builds the prompt IN THE APP, and decodes the
/// model's JSON into the existing structured types. Only transcript TEXT is ever sent (never audio).
/// Robust: every failure path throws a typed error so callers can fall back gracefully (raw transcript).
final class AIClient {
    static let shared = AIClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = AIConfig.timeout
            cfg.timeoutIntervalForResource = AIConfig.timeout
            self.session = URLSession(configuration: cfg)
        }
    }

    /// Structuring pass. Builds a strong system prompt + transcript user message, calls OpenRouter,
    /// decodes `choices[0].message.content` into the validated brief.
    func structure(transcript: String, context: RecordingContext, tone: StructuringTone) async throws -> StructuredResult {
        guard AIRateLimiter.canCall() else { throw AIError.rateLimited }

        let system = Self.structureSystemPrompt(context: context, tone: tone)
        let user = "TRANSCRIPT:\n\(transcript)"

        let content = try await chat(system: system, user: user, maxTokens: AIConfig.structureMaxTokens)
        let result: StructuredResult = try decodeContent(content)
        guard result.isUsable else { throw AIError.unusable }
        AIRateLimiter.recordCall()
        return result
    }

    /// Ask-across-archive. Builds a grounded-answer prompt from the question + locally-retrieved
    /// chunks, calls OpenRouter, decodes the answer + citations.
    func ask(question: String, chunks: [(recordingID: UUID, segmentStart: Double, text: String)]) async throws -> AskResult {
        guard AIRateLimiter.canCall() else { throw AIError.rateLimited }

        let system = Self.askSystemPrompt
        let user = Self.askUserMessage(question: question, chunks: chunks)

        let content = try await chat(system: system, user: user, maxTokens: AIConfig.askMaxTokens)
        let result: AskResult = try decodeContent(content)
        AIRateLimiter.recordCall()
        return result
    }

    // MARK: Prompts (built in the app)

    private static func structureSystemPrompt(context: RecordingContext, tone: StructuringTone) -> String {
        let toneLine = tone == .detailed
            ? "Be thorough: capture nuance, include secondary decisions, and write a 2-3 sentence summary."
            : "Be concise: keep the summary to one tight sentence and only list the most important items."
        return """
        You are an expert note-taker that turns a raw \(context.label.lowercased()) transcript into a clean, structured brief.
        \(toneLine)

        Return ONLY a single JSON object — no markdown, no prose, no code fences — with EXACTLY this shape:
        {
          "title": string,              // a short, specific title for this \(context.label.lowercased()) (max ~8 words)
          "summary": string,            // a plain-language summary of what happened
          "decisions": [string],        // concrete decisions that were made (empty array if none)
          "actionItems": [              // every task someone agreed to do
            { "text": string, "owner": string | null, "due": string | null }  // "due" as YYYY-MM-DD when a date is implied, else null
          ],
          "openQuestions": [string],    // unresolved questions raised (empty array if none)
          "buriedPromise": string | null // ONE personal commitment the speaker made that is easy to forget, phrased as a reminder; null if none
        }

        Rules:
        - Extract owners and due dates when stated or clearly implied. If a weekday or relative date is mentioned, resolve it to a concrete YYYY-MM-DD when reasonable, otherwise leave "due" null.
        - Always produce a non-empty "title" and "summary".
        - actionItems must include at least every clear commitment in the transcript.
        - Output valid JSON only.
        """
    }

    private static let askSystemPrompt = """
    You answer questions strictly from the provided transcript excerpts of the user's own recordings.
    Only use the supplied context. If the answer is not in the context, say you couldn't find it in the recordings.

    Return ONLY a single JSON object — no markdown, no prose, no code fences — with EXACTLY this shape:
    {
      "answer": string,
      "citations": [
        { "recordingID": string, "segmentStart": number, "snippet": string }
      ]
    }

    Use the recordingID and segmentStart values EXACTLY as given in the context for any excerpt you cite.
    Keep "snippet" to a short quoted phrase from that excerpt. Output valid JSON only.
    """

    private static func askUserMessage(question: String,
                                       chunks: [(recordingID: UUID, segmentStart: Double, text: String)]) -> String {
        var ctx = "CONTEXT EXCERPTS:\n"
        if chunks.isEmpty {
            ctx += "(none)\n"
        } else {
            for c in chunks {
                ctx += "- recordingID=\(c.recordingID.uuidString) segmentStart=\(c.segmentStart): \(c.text)\n"
            }
        }
        return ctx + "\nQUESTION: \(question)"
    }

    // MARK: Transport

    /// One chat-completions round-trip. Returns the model's `content` string (expected to be JSON).
    private func chat(system: String, user: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: AIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(AIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        // OpenRouter likes attribution headers; harmless if ignored.
        req.setValue("https://github.com/shimondeitel/footnote", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Footnote", forHTTPHeaderField: "X-Title")

        let body = ChatRequest(
            model: AIConfig.model,
            messages: [ChatMessage(role: "system", content: system),
                       ChatMessage(role: "user", content: user)],
            response_format: .init(type: "json_object"),
            max_tokens: maxTokens,
            temperature: AIConfig.temperature)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AIError.badResponse
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw AIError.http(http.statusCode) }

        let envelope: ChatResponse
        do {
            envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIError.decoding
        }
        guard let content = envelope.choices.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.badResponse
        }
        return content
    }

    /// Tolerant decode of the model's JSON content into a target type. Strips an accidental code
    /// fence and falls back to the first {...} object if the model wrapped the JSON in prose.
    private func decodeContent<R: Decodable>(_ content: String) throws -> R {
        let candidates = Self.jsonCandidates(from: content)
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(R.self, from: data) {
                return decoded
            }
        }
        throw AIError.decoding
    }

    /// Produce progressively-cleaned JSON candidates from a raw model string.
    private static func jsonCandidates(from content: String) -> [String] {
        var out: [String] = []
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        out.append(trimmed)

        // Strip ```json ... ``` fences if present.
        if trimmed.hasPrefix("```") {
            var s = trimmed
            if let firstNewline = s.firstIndex(of: "\n") { s = String(s[s.index(after: firstNewline)...]) }
            if let fence = s.range(of: "```", options: .backwards) { s = String(s[..<fence.lowerBound]) }
            out.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // First balanced-ish {...} slice.
        if let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}"), open < close {
            out.append(String(trimmed[open...close]))
        }
        return out
    }
}
