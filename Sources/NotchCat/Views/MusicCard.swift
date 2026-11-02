import SwiftUI

/// Now playing from Spotify or Apple Music, tinted with the album art's color.
struct MusicCard: View {
    @ObservedObject var music: MusicService

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 11, weight: .semibold))
                Text("Now playing").font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                if let np = music.nowPlaying {
                    Text(np.source.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .opacity(0.6)
                }
            }
            .opacity(0.85)

            if let np = music.nowPlaying {
                player(np)
            } else {
                emptyState
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(music.tint ?? Theme.rose)
        .animation(.easeOut(duration: 0.3), value: music.tint)
    }

    // MARK: Player

    private func player(_ np: NowPlaying) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            ArtworkView(image: music.artwork)
                .frame(maxWidth: 112, maxHeight: 112)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

            VStack(spacing: 1) {
                Text(np.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(np.artist.isEmpty ? np.album : np.artist)
                    .font(.system(size: 11.5, weight: .medium))
                    .opacity(0.65)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            ProgressRow(np: np) { music.seek(toFraction: $0) }

            controls(np)

            if music.automationDenied { deniedNote }
            Spacer(minLength: 0)
        }
    }

    private func controls(_ np: NowPlaying) -> some View {
        HStack(spacing: 18) {
            transport("backward.fill", size: 14) { music.previousTrack() }
            Button { music.togglePlayPause() } label: {
                Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.ink))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            transport("forward.fill", size: 14) { music.nextTrack() }
        }
        .opacity(music.automationDenied ? 0.4 : 1)
        .disabled(music.automationDenied)
    }

    private func transport(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var deniedNote: some View {
        Button { music.openAutomationSettings() } label: {
            Text("Allow control in System Settings")
                .font(.system(size: 10.5, weight: .semibold))
                .underline()
                .opacity(0.7)
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "music.quarternote.3").font(.system(size: 26)).opacity(0.4)
            Text("Nothing playing")
                .font(.system(size: 12.5, weight: .semibold))
                .opacity(0.65)
            ForEach(MusicSource.allCases.filter(\.isInstalled), id: \.self) { source in
                Button { music.open(source) } label: {
                    Text("Open \(source.displayName)")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.ink.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 28)).opacity(0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Elapsed time, a seekable bar, and the total. Only ticks while a track is playing.
private struct ProgressRow: View {
    let np: NowPlaying
    let onSeek: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let position = np.position(at: tl.date)
            let fraction = np.duration > 0 ? position / np.duration : 0
            HStack(spacing: 6) {
                Text(Self.format(position)).frame(width: 34, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.ink.opacity(0.14))
                        Capsule().fill(Theme.ink.opacity(0.8))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                        onSeek(g.location.x / max(geo.size.width, 1))
                    })
                }
                .frame(height: 14)
                Text(Self.format(np.duration)).frame(width: 34, alignment: .leading)
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .opacity(0.7)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The small album-art chip that sits beside the notch while music plays.
struct MusicChipView: View {
    @ObservedObject var music: MusicService
    @ObservedObject var ui: PillUIState
    let height: () -> CGFloat
    let onTap: () -> Void

    var body: some View {
        let h = height()
        HStack(spacing: 6) {
            ArtworkView(image: music.artwork, cornerRadius: 5)
                .frame(width: h - 8, height: h - 8)
            EqualizerBars(playing: music.nowPlaying?.isPlaying ?? false)
                .frame(width: 14, height: h * 0.4)
        }
        .padding(.horizontal, 6)
        .frame(width: MusicChipView.width(height: h), height: h)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .scaleEffect(x: ui.shown ? 1 : 0.12, y: ui.shown ? 1 : 0.7, anchor: .leading)
        .opacity(ui.shown ? 1 : 0)
        .animation(.spring(duration: 0.30, bounce: 0.1), value: ui.shown)
    }

    static func width(height: CGFloat) -> CGFloat { (height - 8) + 14 + 6 + 12 }
}

/// Three bars that bounce while music plays and rest while it is paused.
private struct EqualizerBars: View {
    let playing: Bool
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Theme.amber)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(y: playing ? (phase ? [1.0, 0.45, 0.8][i] : [0.35, 1.0, 0.4][i]) : 0.3, anchor: .bottom)
                    .animation(playing
                               ? .easeInOut(duration: [0.45, 0.6, 0.5][i]).repeatForever(autoreverses: true)
                               : .easeOut(duration: 0.2), value: phase)
            }
        }
        .onAppear { phase = true }
        .onChange(of: playing) { _, now in if now { phase.toggle() } }
    }
}
