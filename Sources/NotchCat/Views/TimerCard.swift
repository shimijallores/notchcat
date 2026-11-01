import SwiftUI

struct TimerCard: View {
    @ObservedObject var ui: PanelUIState
    @ObservedObject var store: TaskStore
    @ObservedObject var timer: FocusTimer

    var body: some View {
        VStack(spacing: 0) {
            // Label row
            HStack(spacing: 6) {
                Image(systemName: "timer").font(.system(size: 11, weight: .semibold))
                Text(linkedTitle ?? "Focus")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .opacity(0.7)

            Spacer(minLength: 4)

            if timer.state == .finished {
                finishedBody
            } else {
                clockBody
            }

            Spacer(minLength: 4)

            controls
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .card(Theme.lavender)
    }

    private var linkedTitle: String? { store.task(id: timer.linkedTaskID)?.title }

    // MARK: Clock

    private var clockBody: some View {
        VStack(spacing: 8) {
            SevenSegmentClock(text: timer.remaining.clockString, maxWidth: 216, maxHeight: 66)
                .opacity(timer.state == .paused ? 0.55 : 1)

            Text(statusText)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(1.2)
                .opacity(0.6)

            ProgressBar(value: timer.progress)
                .frame(height: 4)
                .padding(.horizontal, 6)
        }
    }

    private var statusText: String {
        switch timer.state {
        case .idle: return "Ready"
        case .running: return "Remaining"
        case .paused: return "Paused"
        case .finished: return "Time's up"
        }
    }

    private var finishedBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.ink.opacity(0.8))
            Text("Time's up")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Nice work. Take a breath.")
                .font(.system(size: 11.5))
                .opacity(0.6)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if timer.state == .finished {
            HStack(spacing: 8) {
                PrimaryButton(title: "+ Add 5 min", icon: nil) { timer.addTime(seconds: 300) }
                SecondaryButton(title: "Done", icon: "checkmark") { timer.reset() }
            }
        } else {
            HStack(spacing: 8) {
                PrimaryButton(title: timer.state == .running ? "Pause" : (timer.state == .paused ? "Resume" : "Start"),
                              icon: timer.state == .running ? "pause.fill" : "play.fill") {
                    timer.toggle()
                }
                if timer.isActive {
                    SecondaryButton(title: nil, icon: "arrow.counterclockwise") { timer.reset() }
                        .help("Reset")
                } else {
                    SecondaryButton(title: "Set time", icon: "clock") { ui.modal = .timerDuration }
                }
            }
        }
    }
}

private struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.12))
                Capsule().fill(Theme.ink.opacity(0.75))
                    .frame(width: max(4, geo.size.width * value))
                    .animation(.linear(duration: 0.25), value: value)
            }
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(Theme.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String?
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11.5, weight: .semibold))
                if let title { Text(title).font(.system(size: 12.5, weight: .semibold, design: .rounded)) }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, title == nil ? 0 : 12)
            .frame(width: title == nil ? 34 : nil, height: 34)
            .background(Capsule().fill(Theme.ink.opacity(0.10)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
