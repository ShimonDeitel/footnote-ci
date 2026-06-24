import Foundation
import AVFoundation
import Speech
import SwiftUI

/// Records audio with AVAudioEngine and transcribes it live on-device with SFSpeechRecognizer.
/// Publishes elapsed time, a rolling meter level (for the waveform), the live transcript, and the
/// final time-stamped segments on stop. All permission handling is honest and graceful.
@MainActor
final class Recorder: NSObject, ObservableObject {

    enum State: Equatable { case idle, recording, finishing }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var liveTranscript: String = ""
    /// Rolling normalized power samples (0...1) for the waveform, newest at the end.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.04, count: 48)
    @Published var permissionDenied = false
    @Published var permissionMessage: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var audioFile: AVAudioFile?
    private var fileName: String = ""
    private var startDate: Date?
    private var timer: Timer?

    /// Captured segments (built from the live recognition result on stop).
    private var capturedSegments: [(text: String, start: Double, end: Double)] = []

    // MARK: Permissions

    /// Requests mic + speech permission. Returns true only if both are granted.
    func requestPermissions() async -> Bool {
        let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        guard mic else {
            permissionDenied = true
            permissionMessage = "Microphone access is off. Turn it on in Settings to record."
            return false
        }
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speech else {
            permissionDenied = true
            permissionMessage = "Speech recognition is off. Turn it on in Settings to get transcripts."
            return false
        }
        permissionDenied = false
        return true
    }

    // MARK: Start / stop

    func start() async -> Bool {
        guard state == .idle else { return false }
        guard await requestPermissions() else { return false }

        capturedSegments = []
        liveTranscript = ""
        elapsed = 0
        levels = Array(repeating: 0.04, count: 48)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            permissionMessage = "Couldn't start the audio session."
            return false
        }

        // Prepare the recognition request (on-device when supported).
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        // Prepare the audio file for persistence.
        AudioStore.ensureDirectory()
        fileName = AudioStore.newFileName()
        let url = AudioStore.url(for: fileName)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            audioFile = nil // recording still works for transcription; audio playback just won't be saved
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            try? self.audioFile?.write(from: buffer)
            let level = Recorder.normalizedPower(from: buffer)
            Task { @MainActor in self.pushLevel(level) }
        }

        // Start recognition.
        task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.liveTranscript = result.bestTranscription.formattedString
                    self.capturedSegments = result.bestTranscription.segments.map {
                        ($0.substring, $0.timestamp, $0.timestamp + $0.duration)
                    }
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanup()
            permissionMessage = "Couldn't start recording."
            return false
        }

        startDate = Date()
        state = .recording
        startTimer()
        Haptics.soft()
        return true
    }

    struct Result {
        let fileName: String
        let duration: Double
        let transcript: String
        let segments: [(text: String, start: Double, end: Double)]
    }

    /// Stops recording and returns the captured result. Caller persists it via AppModel.
    func stop() -> Result {
        state = .finishing
        timer?.invalidate(); timer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let duration = elapsed
        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        // If recognition produced no timed segments, fall back to one whole-recording segment.
        var segments = capturedSegments
        if segments.isEmpty, !transcript.isEmpty {
            segments = [(transcript, 0, duration)]
        }

        let result = Result(fileName: audioFile != nil ? fileName : "",
                            duration: duration, transcript: transcript, segments: segments)
        cleanup()
        Haptics.success()
        return result
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !fileName.isEmpty { try? FileManager.default.removeItem(at: AudioStore.url(for: fileName)) }
        cleanup()
    }

    private func cleanup() {
        audioFile = nil
        request = nil
        task = nil
        state = .idle
    }

    // MARK: Internals

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if let start = self.startDate { self.elapsed = Date().timeIntervalSince(start) }
            }
        }
    }

    private func pushLevel(_ level: CGFloat) {
        var l = levels
        l.removeFirst()
        l.append(max(0.04, min(1, level)))
        levels = l
    }

    /// Convert a PCM buffer to a normalized 0...1 loudness value for the waveform.
    nonisolated static func normalizedPower(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.04 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0.04 }
        var sum: Float = 0
        for i in 0..<count { let s = channelData[i]; sum += s * s }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.000_000_1))
        // Map roughly -50dB...0dB to 0...1.
        let clamped = max(-50, min(0, db))
        return CGFloat((clamped + 50) / 50)
    }
}
