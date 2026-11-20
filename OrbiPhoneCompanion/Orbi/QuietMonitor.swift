import Foundation

// BEGIN SOUND STATE
/// Pure sound-to-wake logic, shared by the microphone and the preview.
struct NoiseWakeState {
    private(set) var progress: Double = 0
    private var lastTimestamp: TimeInterval?
    var cooldownUntil: TimeInterval = 0

    mutating func reset(cooldownUntil: TimeInterval = 0) {
        progress = 0
        lastTimestamp = nil
        self.cooldownUntil = cooldownUntil
    }

    /// Returns true only when sustained loud input has fully woken Orbi.
    mutating func update(level: Double, threshold: Double, timestamp: TimeInterval) -> Bool {
        let elapsed = min(0.25, max(0, timestamp - (lastTimestamp ?? timestamp)))
        lastTimestamp = timestamp
        guard timestamp >= cooldownUntil else { return false }
        if level >= threshold {
            progress = min(1, progress + elapsed / 3)
        } else if level > threshold * 0.6 {
            let target = min(0.65, (level / threshold - 0.6) * 1.6)
            progress += (target - progress) * min(1, elapsed * 1.8)
        } else {
            progress = max(0, progress - elapsed / 5)
        }
        return progress >= 1
    }
}

enum OrbiPhase {
    case sleeping, waking, angry, shushing, returningToSleep

    var isPerforming: Bool {
        self == .angry || self == .shushing || self == .returningToSleep
    }

    var caption: String? {
        switch self {
        case .sleeping, .waking: return nil
        case .angry: return "I'm trying to sleep!"
        case .shushing: return "Silence!"
        case .returningToSleep: return "Back to sleep."
        }
    }
}
// END SOUND STATE

import AVFoundation
import Combine
import WatchKit

/// Measures sound in memory and stops the microphone during Orbi's own speech.
@MainActor
final class QuietMonitor: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var isDemonstrating = false
    @Published private(set) var phase: OrbiPhase = .sleeping
    @Published private(set) var wakeProgress: Double = 0
    @Published private(set) var level: Double = 0
    @Published private(set) var message: String?
    @Published var threshold: Double {
        didSet {
            UserDefaults.standard.set(threshold, forKey: "soundThreshold")
            wakeState.reset()
            wakeProgress = 0
        }
    }
    @Published var voiceEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceEnabled, forKey: "voiceEnabled") }
    }

    private var engine: AVAudioEngine?
    private let speech = AVSpeechSynthesizer()
    private var storyTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var wakeState = NoiseWakeState()
    private var generation = 0
    private var interruptionObserver: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard
        threshold = defaults.object(forKey: "soundThreshold") == nil
            ? 0.58 : min(0.9, max(0.15, defaults.double(forKey: "soundThreshold")))
        voiceEnabled = defaults.object(forKey: "voiceEnabled") == nil
            ? true : defaults.bool(forKey: "voiceEnabled")
        interruptionObserver = NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.stop()
                self?.message = "Audio was interrupted. Open Quiet settings to start again."
            }
    }

    func start() async {
        guard !isStarting, !isListening, !phase.isPerforming, !isDemonstrating else { return }
        message = nil
        isStarting = true
        generation += 1
        let currentGeneration = generation
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard currentGeneration == generation else { return }
        isStarting = false
        guard granted else {
            message = "Allow Microphone access for Orbi in Settings, then start listening. You can still preview the story."
            return
        }
        do {
            try beginCapture()
        } catch {
            stop()
            message = "Microphone unavailable. \(error.localizedDescription)"
        }
    }

    func stop() {
        generation += 1
        isStarting = false
        isListening = false
        isDemonstrating = false
        storyTask?.cancel()
        storyTask = nil
        demoTask?.cancel()
        demoTask = nil
        speech.stopSpeaking(at: .immediate)
        endCapture()
        phase = .sleeping
        wakeProgress = 0
        level = 0
        wakeState.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func previewStory() {
        guard !phase.isPerforming, !isStarting, !isDemonstrating else { return }
        let resumeListening = isListening
        generation += 1
        let currentGeneration = generation
        endCapture()
        wakeState.reset()
        wakeProgress = 0
        level = 0
        phase = .sleeping
        isDemonstrating = true
        demoTask = Task { [weak self] in
            do {
                // Feed the same sound gate as the real microphone, from quiet to loud.
                for step in 0..<110 {
                    try await Task.sleep(for: .milliseconds(80))
                    guard let self, self.generation == currentGeneration else { return }
                    let input = min(1, Double(step) / 55) * min(1, self.threshold + 0.3)
                    self.updateSound(input, timestamp: ProcessInfo.processInfo.systemUptime,
                                     resumeListening: resumeListening)
                    if self.phase.isPerforming { return }
                }
            } catch { return }
        }
    }

    func dismissMessage() { message = nil }

    private func beginCapture() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Orbi", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input is available."
            ])
        }
        let captureGeneration = generation
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Double = 0
            var squares: Double = 0
            for index in 0..<count {
                let value = Double(samples[index])
                sum += value
                squares += value * value
            }
            let mean = sum / Double(count)
            let rms = sqrt(max(0, squares / Double(count) - mean * mean))
            let decibelsFS = 20 * log10(max(rms, 0.000_001))
            let normalized = min(1, max(0, (decibelsFS + 65) / 55))
            let timestamp = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, self.generation == captureGeneration, self.isListening,
                      !self.phase.isPerforming,
                      ProcessInfo.processInfo.systemUptime - timestamp < 0.5 else { return }
                self.updateSound(normalized, timestamp: timestamp, resumeListening: true)
            }
        }
        do {
            newEngine.prepare()
            try newEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        engine = newEngine
        isListening = true
    }

    private func endCapture() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    private func updateSound(_ input: Double, timestamp: TimeInterval, resumeListening: Bool) {
        level = 0.7 * level + 0.3 * input
        let fullyAwake = wakeState.update(level: level, threshold: threshold, timestamp: timestamp)
        wakeProgress = wakeState.progress
        phase = wakeProgress > 0.025 ? .waking : .sleeping
        if fullyAwake { beginReaction(resumeListening: resumeListening) }
    }

    private func beginReaction(resumeListening: Bool) {
        generation += 1
        let currentGeneration = generation
        demoTask?.cancel()
        demoTask = nil
        endCapture()
        phase = .angry
        wakeProgress = 1
        level = 0
        WKInterfaceDevice.current().play(.notification)
        storyTask = Task { [weak self] in
            guard let self else { return }
            do {
                if self.voiceEnabled {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default)
                    try session.setActive(true)
                }
                try await self.say("Hey! I'm trying to sleep!", volume: 1, pitch: 0.8)
                try Task.checkCancellation()
                self.phase = .shushing
                try await self.say("Silence! Please keep it down!", volume: 0.95, pitch: 0.9)
                try Task.checkCancellation()
                self.phase = .returningToSleep
                try await self.say("I'm going back to sleep. Good night.", volume: 0.55, pitch: 0.9)
                try await Task.sleep(for: .seconds(2))
                guard self.generation == currentGeneration else { return }
                self.phase = .sleeping
                self.wakeProgress = 0
                self.isDemonstrating = false
                self.wakeState.reset(cooldownUntil: ProcessInfo.processInfo.systemUptime + 10)
                if resumeListening {
                    try self.beginCapture()
                } else {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            } catch is CancellationError {
                return
            } catch {
                self.stop()
                self.message = "Audio unavailable. \(error.localizedDescription)"
            }
        }
    }

    private func say(_ text: String, volume: Float, pitch: Float) async throws {
        guard voiceEnabled else {
            try await Task.sleep(for: .seconds(3))
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        speech.speak(utterance)
        // Wait for speech completion so the next line never cuts this one off.
        let start = ProcessInfo.processInfo.systemUptime
        repeat {
            try await Task.sleep(for: .milliseconds(100))
            if ProcessInfo.processInfo.systemUptime - start > 12 { break }
        } while speech.isSpeaking || ProcessInfo.processInfo.systemUptime - start < 1.5
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        try await Task.sleep(for: .milliseconds(500))
    }
}
