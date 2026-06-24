import SwiftUI
import SwiftData

struct CommitmentsView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store

    // Observe action items so toggles + new notes refresh the rollup live.
    @Query private var allItems: [ActionItem]
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                FootnoteBackground()
                if store.isPro {
                    proContent
                } else {
                    lockedContent
                }
            }
            .navigationTitle("Commitments")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    // MARK: Pro content

    private var openItems: [ActionItem] {
        allItems.filter { !$0.isDone }
            .sorted { ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt) }
    }

    private var promises: [(note: StructuredNote, promise: String)] { appModel.buriedPromises() }

    @ViewBuilder private var proContent: some View {
        if openItems.isEmpty && promises.isEmpty {
            EmptyStateView(
                symbol: "checkmark.circle",
                title: "All clear",
                message: "Every action item is done. New commitments from your recordings show up here automatically.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !promises.isEmpty {
                        FootnoteSectionHeader(title: "Buried Promises", symbol: "bookmark.fill")
                            .padding(.horizontal, 4)
                        ForEach(Array(promises.enumerated()), id: \.offset) { _, p in
                            promiseCard(p.note, p.promise)
                        }
                    }
                    FootnoteSectionHeader(title: "Open Action Items", symbol: "checklist")
                        .padding(.horizontal, 4).padding(.top, promises.isEmpty ? 0 : 8)
                    if openItems.isEmpty {
                        Text("No open action items.").font(.subheadline)
                            .foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                    ForEach(openItems) { item in
                        commitmentCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    private func commitmentCard(_ item: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionItemRow(item: item) { appModel.toggle(item) }
            if let rec = item.note?.recording {
                NavigationLink {
                    NoteDetailView(recording: rec, justFinished: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: rec.context.symbol).font(.caption2)
                        Text("From \(rec.displayTitle)").font(.caption).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .footnoteCard()
    }

    private func promiseCard(_ note: StructuredNote, _ promise: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BuriedPromiseBanner(text: promise)
            if let rec = note.recording {
                NavigationLink {
                    NoteDetailView(recording: rec, justFinished: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: rec.context.symbol).font(.caption2)
                        Text("From \(rec.displayTitle)").font(.caption).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Locked (free tier)

    private var lockedContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.footnoteAccent)
                    Text("Your accountability list")
                        .font(.title2.weight(.bold))
                    Text("Every open action item and buried promise from all your notes, pulled into one list sorted by due date. Open it each morning to see what you owe and to whom.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 40)

                // Show a teaser count so the value is concrete.
                let count = allItems.filter { !$0.isDone }.count
                if count > 0 {
                    Text("You have \(count) open action item\(count == 1 ? "" : "s") waiting.")
                        .font(.headline)
                        .foregroundStyle(Color.footnoteAccent)
                }

                Button { showPaywall = true } label: {
                    Label("Unlock Commitments with Pro", systemImage: "sparkles")
                }
                .prominentButton()
                .padding(.top, 4)
            }
            .padding(20)
        }
    }
}
