import SwiftUI

/// Today's calendar events (read-only) merged with NotchCat's own timed reminders.
struct EventsCard: View {
    @ObservedObject var calendar: CalendarStore
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    private struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date?
        let isReminder: Bool
        let isAllDay: Bool
    }

    private func items() -> [Item] {
        var out: [Item] = calendar.events.map {
            Item(id: "e-" + $0.id, title: $0.title, start: $0.start, end: $0.end, isReminder: false, isAllDay: $0.isAllDay)
        }
        if settings.data.showRemindersInEvents {
            out += store.reminders(on: Date()).map {
                Item(id: "r-" + $0.id.uuidString, title: $0.title, start: $0.remindAt!, end: nil, isReminder: true, isAllDay: false)
            }
        }
        return out.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            let list = items()
            if list.isEmpty {
                emptyState
            } else {
                // Re-evaluate "Happening now" every 30 seconds.
                TimelineView(.periodic(from: .now, by: 30)) { tl in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(list) { row($0, now: tl.date) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            connectionFooter
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(Theme.slate)
        .onAppear { calendar.refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
            Text("Today").font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
        .opacity(0.85)
    }

    private func row(_ item: Item, now: Date) -> some View {
        let happeningNow = !item.isReminder && !item.isAllDay && item.start <= now && now < (item.end ?? item.start)
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.isReminder ? Theme.amber : Theme.ink.opacity(0.55))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if item.isReminder { Image(systemName: "bell.fill").font(.system(size: 8.5)) }
                    Text(timeText(item))
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.65)
                }
                if happeningNow {
                    Text("Happening now")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.ink))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.3)))
        .opacity(item.isReminder || item.isAllDay || (item.end ?? item.start) >= now ? 1 : 0.5)
    }

    private func timeText(_ item: Item) -> String {
        if item.isAllDay { return "All day" }
        let start = item.start.formatted(.dateTime.hour().minute())
        guard let end = item.end else { return start }
        return "\(start) – \(end.formatted(.dateTime.hour().minute()))"
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: calendar.access == .authorized ? "calendar.badge.checkmark" : "calendar")
                .font(.system(size: 26, weight: .light))
                .opacity(0.45)
            Text(calendar.access == .authorized ? "Nothing scheduled today." : "No reminders today.")
                .font(.system(size: 12, weight: .medium)).opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var connectionFooter: some View {
        switch calendar.access {
        case .authorized:
            EmptyView()
        case .notDetermined:
            footerButton("Connect Calendar") { calendar.requestAccess() }
        case .denied:
            footerButton("Allow in System Settings") { calendar.openPrivacySettings() }
        case .unavailable:
            Text("Calendar needs the packaged app (build-app.sh).")
                .font(.system(size: 10, weight: .medium))
                .opacity(0.55)
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 28)
                .background(Capsule().fill(Theme.ink))
        }
        .buttonStyle(.plain)
    }
}
