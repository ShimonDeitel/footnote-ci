import SwiftUI

struct AskView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store

    @State private var query = ""
    @State private var turns: [AskTurn] = []
    @State private var asking = false
    @State private var showPaywall = false
    @State private var previewUsed = false
    @State private var errorText: String?

    private let suggestions = [
        "What did I commit to this week?",
        "Every deadline I agreed to",
        "What were the objections to the new pricing?",
        "What did I promise the design team?"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                FootnoteBackground()
                VStack(spacing: 0) {
                    transcriptArea
                    inputBar
                }
            }
            .navigationTitle("Ask")
            .toolbar {
                if !turns.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { appModel.clearAskHistory(); turns = [] }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { turns = appModel.askTurns() }
        }
    }

    // MARK: Transcript

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if turns.isEmpty {
                        intro
                    }
                    ForEach(turns) { turn in
                        AskTurnView(turn: turn, recordingFor: appModel.recording(id:))
                            .id(turn.id)
                    }
                    if asking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Searching your archive…").font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.footnoteAccent)
                Text("Ask across every note")
                    .font(.title2.weight(.bold))
                Text("Your recordings become a searchable second memory. Ask in plain language and get an answer with citations back to the exact moment.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                FootnoteSectionHeader(title: "Try asking")
                ForEach(suggestions, id: \.self) { s in
                    Button { query = s; submit() } label: {
                        HStack {
                            Text(s).font(.callout)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color.footnoteCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !store.isPro {
                Text(previewUsed
                     ? "You've used your free preview. Footnote Pro unlocks unlimited Ask."
                     : "Free preview: one answer. Footnote Pro unlocks unlimited Ask across your archive.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your archive…", text: $query, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.footnoteCard, in: Capsule())
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSubmit ? Color.footnoteAccent : .secondary)
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var canSubmit: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !asking
    }

    // MARK: Submit

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }

        // Gating: free tier gets one preview answer.
        if !store.isPro && previewUsed {
            showPaywall = true
            return
        }

        query = ""
        errorText = nil
        asking = true
        Haptics.tap()

        Task {
            let chunks = ArchiveRetriever.retrieve(query: q, appModel: appModel)
            do {
                let result = try await AIClient.shared.ask(question: q, chunks: chunks)
                let citations = result.citations.compactMap { wc -> Citation? in
                    guard let uuid = UUID(uuidString: wc.recordingID) else { return nil }
                    return Citation(recordingID: uuid, segmentStart: wc.segmentStart, snippet: wc.snippet)
                }
                appModel.recordAsk(question: q, answer: result.answer, citations: citations)
            } catch {
                // Graceful local fallback so Ask is never a dead end without the Worker.
                let answer = ArchiveRetriever.localAnswer(query: q, chunks: chunks)
                let citations = chunks.prefix(3).map {
                    Citation(recordingID: $0.recordingID, segmentStart: $0.segmentStart,
                             snippet: String($0.text.prefix(120)))
                }
                appModel.recordAsk(question: q, answer: answer, citations: Array(citations))
            }
            turns = appModel.askTurns()
            asking = false
            if !store.isPro { previewUsed = true }
        }
    }
}

// MARK: - Single turn view

struct AskTurnView: View {
    let turn: AskTurn
    let recordingFor: (UUID) -> Recording?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 40)
                Text(turn.question)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.footnoteAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(turn.answer.isEmpty ? "No answer." : turn.answer)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.footnoteCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !turn.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(turn.citations) { c in
                        if let rec = recordingFor(c.recordingID) {
                            NavigationLink {
                                NoteDetailView(recording: rec, justFinished: false)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "quote.opening").font(.caption2)
                                    Text("\(rec.displayTitle) · \(TimeFmt.clock(c.segmentStart))")
                                        .font(.caption).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption2)
                                }
                                .foregroundStyle(Color.footnoteAccent)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.footnoteField, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Local retrieval

/// Tiny on-device retriever: scores segments by keyword overlap with the query so the Worker gets
/// the most relevant chunks (and so Ask still gives a useful local answer if the Worker is offline).
enum ArchiveRetriever {
    struct Chunk { let recordingID: UUID; let segmentStart: Double; let text: String }

    @MainActor
    static func retrieve(query: String, appModel: AppModel, limit: Int = 12)
    -> [(recordingID: UUID, segmentStart: Double, text: String)] {
        let terms = tokenize(query)
        var scored: [(Double, (recordingID: UUID, segmentStart: Double, text: String))] = []
        for rec in appModel.allRecordings() {
            let segs = rec.orderedSegments
            if segs.isEmpty, !rec.transcript.isEmpty {
                let score = overlap(tokenize(rec.transcript), terms)
                if score > 0 {
                    scored.append((score, (rec.id, 0, String(rec.transcript.prefix(400)))))
                }
                continue
            }
            for seg in segs {
                let score = overlap(tokenize(seg.text), terms)
                if score > 0 { scored.append((score, (rec.id, seg.startTime, seg.text))) }
            }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map { $0.1 }
    }

    /// A readable local answer when the Worker is unavailable — stitches the top matches together.
    static func localAnswer(query: String,
                            chunks: [(recordingID: UUID, segmentStart: Double, text: String)]) -> String {
        guard !chunks.isEmpty else {
            return "I couldn't find anything in your notes for that yet. Try recording a few sessions first, or rephrase the question."
        }
        let joined = chunks.prefix(3).map { "• \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
        return "Here's what I found across your notes:\n\n\(joined)\n\nConnect Footnote Pro for a fully synthesized answer."
    }

    private static func tokenize(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }

    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        Double(a.intersection(b).count)
    }
}
