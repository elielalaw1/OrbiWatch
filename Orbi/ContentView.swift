import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = QuietMonitor()
    @State private var settingsVisible = false
    @Environment(\.scenePhase) private var scenePhase
    private let gold = Color(red: 1, green: 0.7664, blue: 0.0812)

    var body: some View {
        ZStack {
            OrbiFace(phase: monitor.phase, wakeProgress: monitor.wakeProgress)
                .ignoresSafeArea()

        }
        .contentShape(Rectangle())
        .onLongPressGesture { settingsVisible = true }
        .accessibilityAction(named: "Quiet settings") { settingsVisible = true }
        .sheet(isPresented: $settingsVisible) { settings }
        .task {
            #if targetEnvironment(simulator)
            if CommandLine.arguments.contains("--preview-story") {
                monitor.previewStory()
                return
            }
            if CommandLine.arguments.contains("--preview-sleep") { return }
            #endif
            await monitor.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                #if targetEnvironment(simulator)
                if CommandLine.arguments.contains("--preview-story") || CommandLine.arguments.contains("--preview-sleep") { return }
                #endif
                Task { await monitor.start() }
            } else if phase == .background {
                monitor.stop()
            }
        }
        .alert("Orbi", isPresented: Binding(
            get: { monitor.message != nil },
            set: { if !$0 { monitor.dismissMessage() } }
        )) {
            Button("OK") { monitor.dismissMessage() }
            Button("Settings") { monitor.dismissMessage(); settingsVisible = true }
        } message: {
            Text(monitor.message ?? "")
        }
        .preferredColorScheme(.dark)
        ._statusBarHidden(true)
        .tint(gold)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quiet settings").font(.headline)
                Text(monitor.isListening ? "Listening for sound" : "Listening paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sound limit · \(Int((monitor.threshold * 100).rounded()))")
                    .font(.caption)
                    .monospacedDigit()
                Slider(value: $monitor.threshold, in: 0.15...0.9, step: 0.05)
                    .accessibilityLabel("Sound limit. Lower values react to quieter sounds.")
                ProgressView(value: monitor.level)
                    .accessibilityLabel("Relative sound level")
                Text("Small sounds only stir Orbi. Sustained loud sounds wake him up angry. Then he asks for silence and goes back to sleep.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Say ‘Silence’", isOn: $monitor.voiceEnabled).font(.caption)
                Button(monitor.isListening ? "Pause listening" : "Start listening") {
                    if monitor.isListening { monitor.stop() }
                    else { Task { await monitor.start() } }
                }
                .disabled(monitor.isStarting || monitor.phase.isPerforming || monitor.isDemonstrating)
                Button("Preview story") {
                    settingsVisible = false
                    monitor.previewStory()
                }
                .disabled(monitor.phase.isPerforming || monitor.isStarting || monitor.isDemonstrating)
                Text("Keep Orbi open to listen. Audio stays on your watch and is never saved. The sound level is relative, not calibrated decibels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Done") { settingsVisible = false }
            }
            .padding(.horizontal, 4)
        }
    }
}
