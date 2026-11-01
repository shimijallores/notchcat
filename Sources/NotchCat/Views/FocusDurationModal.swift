import SwiftUI

struct FocusDurationModal: View {
    let initialMinutes: Int
    let allowsClear: Bool
    let onSave: (Int) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var minutes: Int = 25

    private let presets = [15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Focus duration")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { m in
                    Button { minutes = m } label: {
                        Text("\(m)m")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .frame(width: 50, height: 30)
                            .background(Capsule().fill(minutes == m ? Theme.amber : Color.white.opacity(0.09)))
                            .foregroundStyle(minutes == m ? Theme.ink : .white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Custom")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                HStack(spacing: 0) {
                    stepButton("minus") { minutes = max(1, minutes - 5) }
                    Text("\(minutes) min")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 78)
                    stepButton("plus") { minutes = min(240, minutes + 5) }
                }
                .background(Capsule().fill(Color.white.opacity(0.09)))
            }

            HStack(spacing: 8) {
                if allowsClear {
                    Button("Remove limit", action: onClear)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                Button { onSave(minutes) } label: {
                    Text("Save")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.amber))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 292)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.housingRaised))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .onAppear { minutes = min(max(initialMinutes, 1), 240) }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
    }
}
