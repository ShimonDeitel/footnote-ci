import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store

    @AppStorage("footnote.theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("footnote.defaultContext") private var defaultContextRaw = RecordingContext.meeting.rawValue
    @AppStorage("footnote.tone") private var toneRaw = StructuringTone.concise.rawValue

    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var restoreMessage: String?
    @State private var bulkExport: String?

    private var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        nonmutating set { themeRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                recordingSection
                structuringSection
                appearanceSection
                exportSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(item: Binding(get: { bulkExport.map { ExportItem(text: $0) } },
                                 set: { bulkExport = $0?.text })) { item in
                ShareSheet(items: [item.text])
            }
            .alert("Delete all data?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { appModel.deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every recording, transcript and note from this device. This can't be undone.")
            }
        }
    }

    // MARK: Pro

    private var proSection: some View {
        Section {
            if store.isPro {
                Label("Footnote Pro is active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.footnoteAccent)
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Footnote Pro").font(.headline)
                            Text("Unlimited structuring · Ask · Commitments")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.pricePerMonth).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.footnoteAccent)
                    }
                }
            }
            Button("Restore Purchases") {
                Task {
                    await store.restore()
                    restoreMessage = store.isPro ? "Pro restored." : "No purchase found to restore."
                }
            }
            if let restoreMessage {
                Text(restoreMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Recording

    private var recordingSection: some View {
        Section("Recording") {
            Picker("Default context", selection: $defaultContextRaw) {
                ForEach(RecordingContext.allCases) { c in
                    Label(c.label, systemImage: c.symbol).tag(c.rawValue)
                }
            }
        }
    }

    // MARK: Structuring

    private var structuringSection: some View {
        Section {
            if store.isPro {
                Picker("Structuring tone", selection: $toneRaw) {
                    ForEach(StructuringTone.allCases) { t in Text(t.label).tag(t.rawValue) }
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Text("Structuring tone")
                        Spacer()
                        Text("Concise").foregroundStyle(.secondary)
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(Color.footnoteAccent)
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Structuring")
        } footer: {
            Text(store.isPro
                 ? "Concise keeps notes tight; Detailed captures more nuance."
                 : "Free notes use the Concise tone. Pro unlocks Detailed.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { themeRaw },
                set: { themeRaw = $0 })) {
                ForEach(AppTheme.allCases) { t in Text(t.label).tag(t.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            Button {
                if store.isPro {
                    bulkExport = MarkdownExport.archive(appModel.allRecordings())
                } else {
                    showPaywall = true
                }
            } label: {
                HStack {
                    Label("Export all notes (Markdown)", systemImage: "square.and.arrow.up.on.square")
                    Spacer()
                    if !store.isPro {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(Color.footnoteAccent)
                    }
                }
            }
            .tint(.primary)
        } header: {
            Text("Export")
        } footer: {
            Text(store.isPro
                 ? "Export your entire archive as one Markdown file."
                 : "Single notes export from the share button. Bulk export is a Pro feature.")
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete all data", systemImage: "trash")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Audio and transcription stay on your device. Only de-identified note text is sent to structure your notes — never your audio.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            HStack { Text("Notes"); Spacer(); Text("\(appModel.totalRecordings)").foregroundStyle(.secondary) }
            Link(destination: URL(string: "https://shimondeitel.github.io/footnote-site/terms")!) {
                Label("Terms of Use", systemImage: "doc.text")
            }
            Link(destination: URL(string: "https://shimondeitel.github.io/footnote-site/privacy")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            HStack { Text("Version"); Spacer(); Text("1.0").foregroundStyle(.secondary) }
        }
    }
}

private struct ExportItem: Identifiable { let id = UUID(); let text: String }
