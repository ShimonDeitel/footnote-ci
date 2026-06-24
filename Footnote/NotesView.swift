import SwiftUI
import SwiftData

struct NotesView: View {
    @EnvironmentObject var appModel: AppModel
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var search = ""
    @State private var contextFilter: RecordingContext?
    @State private var onlyOpenItems = false

    var body: some View {
        NavigationStack {
            ZStack {
                FootnoteBackground()
                if recordings.isEmpty {
                    EmptyStateView(
                        symbol: "doc.text",
                        title: "No notes yet",
                        message: "Record a meeting, lecture or call. The moment you stop, it's already a structured note.")
                } else {
                    list
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $search, prompt: "Search notes and transcripts")
            .toolbar { filterMenu }
        }
    }

    private var filtered: [Recording] {
        recordings.filter { rec in
            if let cf = contextFilter, rec.context != cf { return false }
            if onlyOpenItems {
                let hasOpen = (rec.note?.actionItems ?? []).contains { !$0.isDone }
                if !hasOpen { return false }
            }
            if !search.isEmpty {
                let hay = (rec.displayTitle + " " + rec.transcript + " "
                           + (rec.note?.oneLineSummary ?? "")).lowercased()
                if !hay.contains(search.lowercased()) { return false }
            }
            return true
        }
    }

    private var grouped: [(String, [Recording])] {
        let cal = Calendar.current
        var today: [Recording] = [], week: [Recording] = [], earlier: [Recording] = []
        for r in filtered {
            if cal.isDateInToday(r.createdAt) { today.append(r) }
            else if cal.isDate(r.createdAt, equalTo: .now, toGranularity: .weekOfYear) { week.append(r) }
            else { earlier.append(r) }
        }
        var sections: [(String, [Recording])] = []
        if !today.isEmpty { sections.append(("Today", today)) }
        if !week.isEmpty { sections.append(("This Week", week)) }
        if !earlier.isEmpty { sections.append(("Earlier", earlier)) }
        return sections
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.0) { section in
                    Section {
                        ForEach(section.1) { rec in
                            NavigationLink {
                                NoteDetailView(recording: rec, justFinished: false)
                            } label: {
                                NoteCard(recording: rec)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(section.0).font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .background(Color(uiColor: .systemBackground).opacity(0.95))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Context", selection: $contextFilter) {
                    Text("All contexts").tag(RecordingContext?.none)
                    ForEach(RecordingContext.allCases) { c in
                        Label(c.label, systemImage: c.symbol).tag(RecordingContext?.some(c))
                    }
                }
                Toggle("Has open action items", isOn: $onlyOpenItems)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle"
                      + ((contextFilter != nil || onlyOpenItems) ? ".fill" : ""))
            }
        }
    }
}

// MARK: - Note card

struct NoteCard: View {
    let recording: Recording

    private var openCount: Int {
        (recording.note?.actionItems ?? []).filter { !$0.isDone }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: recording.context.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.footnoteAccent)
                Text(recording.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if let summary = recording.note?.oneLineSummary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if recording.note == nil {
                Text(recording.processingError ?? recording.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let promise = recording.note?.buriedPromise, !promise.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill").font(.caption2)
                    Text(promise).font(.caption).lineLimit(1)
                }
                .foregroundStyle(Color.footnoteAccent)
            }

            HStack(spacing: 8) {
                MetaChip(symbol: "calendar", text: TimeFmt.relative(recording.createdAt))
                MetaChip(symbol: "clock", text: recording.durationText)
                if openCount > 0 {
                    MetaChip(symbol: "checklist", text: "\(openCount) open", tint: Color.footnoteAccent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .footnoteCard()
    }
}
