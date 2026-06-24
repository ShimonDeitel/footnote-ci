import SwiftUI

struct RecordView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @StateObject private var recorder = Recorder()

    @AppStorage("footnote.defaultContext") private var defaultContextRaw = RecordingContext.meeting.rawValue
    @AppStorage("footnote.tone") private var toneRaw = StructuringTone.concise.rawValue

    @State private var context: RecordingContext = .meeting
    @State private var processing = false
    @State private var finishedRecordingID: UUID?
    @State private var showPermissionAlert = false

    var switchToNotes: () -> Void = {}

    private var tone: StructuringTone { StructuringTone(rawValue: toneRaw) ?? .concise }

    var body: some View {
        NavigationStack {
            ZStack {
                FootnoteBackground()
                content
            }
            .navigationTitle("Footnote")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $finishedRecordingID) { id in
                if let rec = appModel.recording(id: id) {
                    NoteDetailView(recording: rec, justFinished: true)
                }
            }
            .alert("Permission needed", isPresented: $showPermissionAlert) {
                Button("Open Settings") { openSettings() }
                Button("Not now", role: .cancel) { }
            } message: {
                Text(recorder.permissionMessage ?? "Microphone and speech access are required to record.")
            }
            .onAppear { context = RecordingContext(rawValue: defaultContextRaw) ?? .meeting }
        }
    }

    @ViewBuilder private var content: some View {
        if processing {
            processingView
        } else {
            VStack(spacing: 0) {
                contextPicker
                    .padding(.top, 8)
                Spacer(minLength: 0)
                recordHero
                Spacer(minLength: 0)
                transcriptStrip
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Context picker

    private var contextPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecordingContext.allCases) { c in
                    Button {
                        Haptics.tap(); context = c
                    } label: { ContextChip(context: c, selected: context == c) }
                    .buttonStyle(.plain)
                    .disabled(recorder.state != .idle)
                }
            }
            .padding(.vertical, 4)
        }
        .opacity(recorder.state == .idle ? 1 : 0.5)
    }

    // MARK: Hero record control

    private var recordHero: some View {
        VStack(spacing: 28) {
            // Elapsed timer (only meaningful while recording).
            Text(TimeFmt.clock(recorder.elapsed))
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(recorder.state == .recording ? .primary : .secondary)
                .contentTransition(.numericText())

            // Waveform.
            WaveformView(levels: recorder.levels, active: recorder.state == .recording)
                .frame(height: 84)
                .opacity(recorder.state == .recording ? 1 : 0.35)
                .animation(.easeOut(duration: 0.15), value: recorder.levels)

            // Big tap-to-record button.
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .stroke(Color.footnoteAccent.opacity(0.25), lineWidth: 5)
                        .frame(width: 116, height: 116)
                    if recorder.state == .recording {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.footnoteAccent)
                            .frame(width: 38, height: 38)
                    } else {
                        Circle()
                            .fill(Color.footnoteAccent)
                            .frame(width: 96, height: 96)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.state == .recording ? "Stop recording" : "Start recording")

            Text(recorder.state == .recording ? "Tap to stop — your note is being written"
                                              : "Tap to record \(context.label.lowercased())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Live transcript strip

    @ViewBuilder private var transcriptStrip: some View {
        if recorder.state == .recording {
            ScrollView {
                Text(recorder.liveTranscript.isEmpty ? "Listening…" : recorder.liveTranscript)
                    .font(.callout)
                    .foregroundStyle(recorder.liveTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(height: 120)
            .background(Color.footnoteCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 12)
        } else {
            // Idle helper showing free-tier status.
            idleFooter.padding(.bottom, 12)
        }
    }

    private var idleFooter: some View {
        VStack(spacing: 4) {
            if store.isPro {
                Label("Pro — every recording auto-structures", systemImage: "checkmark.seal.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("\(appModel.freeStructuredRemaining) of \(AppModel.freeStructureLimit) free auto-structured notes left")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Processing screen (shown briefly while structuring)

    private var processingView: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Writing your note…")
                .font(.title3.weight(.semibold))
            Text("Turning the transcript into decisions, action items and the one promise you'd forget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Actions

    private func toggleRecording() {
        switch recorder.state {
        case .idle:
            Task {
                let ok = await recorder.start()
                if !ok && recorder.permissionDenied { showPermissionAlert = true }
            }
        case .recording:
            finish()
        case .finishing:
            break
        }
    }

    private func finish() {
        let result = recorder.stop()
        processing = true
        Task {
            let rec = appModel.createRecording(
                context: context, duration: result.duration,
                audioFileName: result.fileName, transcript: result.transcript,
                segments: result.segments)
            await appModel.structure(rec, tone: tone)
            processing = false
            finishedRecordingID = rec.id
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
