import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()

    let recording: Recording
    var justFinished: Bool

    @AppStorage("footnote.tone") private var toneRaw = StructuringTone.concise.rawValue
    @State private var showTranscript = false
    @State private var retrying = false
    @State private var shareText: String?
    @State private var showPaywall = false

    private var tone: StructuringTone { StructuringTone(rawValue: toneRaw) ?? .concise }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let note = recording.note {
                    structuredSections(note)
                } else {
                    fallbackSection
                }
                audioSection
                transcriptSection
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .background(FootnoteBackground())
        .navigationTitle(recording.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shareText = MarkdownExport.note(recording) } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: Binding(get: { shareText.map { ShareItem(text: $0) } },
                             set: { shareText = $0?.text })) { item in
            ShareSheet(items: [item.text])
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { player.load(url: recording.audioURL) }
        .onDisappear { player.stop() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(recording.context.label, systemImage: recording.context.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.footnoteAccent)
                Spacer()
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let summary = recording.note?.oneLineSummary, !summary.isEmpty {
                Text(summary)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let promise = recording.note?.buriedPromise, !promise.isEmpty {
                BuriedPromiseBanner(text: promise)
            }
        }
    }

    // MARK: Structured sections

    @ViewBuilder private func structuredSections(_ note: StructuredNote) -> some View {
        if !note.decisions.isEmpty {
            section("Decisions", symbol: "checkmark.seal") {
                ForEach(Array(note.decisions.enumerated()), id: \.offset) { _, d in
                    bullet(d)
                }
            }
        }

        let items = note.orderedActionItems
        if !items.isEmpty {
            section("Action Items", symbol: "checklist") {
                ForEach(items) { item in
                    ActionItemRow(item: item) { appModel.toggle(item) }
                }
            }
        }

        if !note.openQuestions.isEmpty {
            section("Open Questions", symbol: "questionmark.circle") {
                ForEach(Array(note.openQuestions.enumerated()), id: \.offset) { _, q in
                    bullet(q)
                }
            }
        }
    }

    // MARK: Fallback (structuring failed or pending)

    private var fallbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(Color.footnoteAccent)
                Text(recording.processingError ?? "This recording hasn't been structured yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .footnoteCard()

            if !appModel.canStructureForFree && store.isPro == false {
                Button { showPaywall = true } label: {
                    Label("Upgrade to auto-structure", systemImage: "sparkles")
                }
                .prominentButton()
            } else {
                Button(action: retry) {
                    if retrying { ProgressView() }
                    else { Label("Try structuring again", systemImage: "arrow.clockwise") }
                }
                .prominentButton()
                .disabled(retrying)
            }
        }
    }

    // MARK: Audio scrubber synced to transcript

    @ViewBuilder private var audioSection: some View {
        if player.hasAudio {
            VStack(alignment: .leading, spacing: 10) {
                FootnoteSectionHeader(title: "Playback", symbol: "waveform")
                HStack(spacing: 14) {
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.footnoteAccent)
                    }
                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }),
                               in: 0...max(0.1, player.duration))
                        .tint(.footnoteAccent)
                        HStack {
                            Text(TimeFmt.clock(player.currentTime)).font(.caption).monospacedDigit()
                            Spacer()
                            Text(TimeFmt.clock(player.duration)).font(.caption).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .footnoteCard()
            }
        }
    }

    // MARK: Transcript (synced highlight)

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { showTranscript.toggle() }
            } label: {
                HStack {
                    FootnoteSectionHeader(title: "Full Transcript", symbol: "text.alignleft")
                    Spacer()
                    Image(systemName: showTranscript ? "chevron.up" : "chevron.down")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showTranscript {
                let segments = recording.orderedSegments
                if segments.isEmpty {
                    Text(recording.transcript.isEmpty ? "No transcript." : recording.transcript)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .footnoteCard()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(segments) { seg in
                            Button {
                                player.seek(to: seg.startTime)
                                if !player.isPlaying { player.togglePlay() }
                            } label: {
                                Text(seg.text)
                                    .font(.callout)
                                    .foregroundStyle(isActive(seg) ? Color.footnoteAccent : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .footnoteCard()
                }
            }
        }
    }

    private func isActive(_ seg: TranscriptSegment) -> Bool {
        player.isPlaying && player.currentTime >= seg.startTime && player.currentTime < seg.endTime
    }

    // MARK: Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FootnoteSectionHeader(title: title, symbol: symbol)
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .footnoteCard()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color.footnoteAccent).frame(width: 6, height: 6).padding(.top, 6)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func retry() {
        retrying = true
        Task {
            await appModel.structure(recording, tone: tone)
            retrying = false
        }
    }
}

// MARK: - Action item row

struct ActionItemRow: View {
    let item: ActionItem
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: { Haptics.tap(); toggle() }) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.footnoteAccent : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.callout)
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let owner = item.ownerChip {
                        MetaChip(symbol: "person", text: owner)
                    }
                    if let due = TimeFmt.due(item.dueDate) {
                        MetaChip(symbol: "calendar", text: due, tint: Color.footnoteAccent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Share sheet

private struct ShareItem: Identifiable { let id = UUID(); let text: String }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
