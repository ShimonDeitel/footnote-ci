import Foundation
import AVFoundation
import SwiftUI

/// Plays back a recording's audio and publishes the current time so the transcript can highlight the
/// active segment (transcript-synced scrubber). Degrades gracefully when no audio file exists.
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var hasAudio = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL?) {
        stop()
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            hasAudio = false
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            hasAudio = true
        } catch {
            hasAudio = false
        }
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            startTimer()
            Haptics.tap()
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        let t = max(0, min(time, player.duration))
        player.currentTime = t
        currentTime = t
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        hasAudio = false
        stopTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if let p = self.player { self.currentTime = p.currentTime }
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }
}
