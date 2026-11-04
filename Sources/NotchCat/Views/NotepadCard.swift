import SwiftUI
import AppKit

/// Long-lived scratchpad for ideas; it is never reset. ⌘↵ turns the line under the cursor into a task.
struct NotepadCard: View {
    @ObservedObject var notes: NoteStore
    @ObservedObject var store: TaskStore
    @State private var flash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text").font(.system(size: 11, weight: .semibold))
                Text("Notepad").font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .opacity(0.8)

            ZStack(alignment: .topLeading) {
                NoteEditor(text: $notes.text) { line in
                    store.add(title: line, day: .today)
                    withAnimation(.easeOut(duration: 0.15)) { flash = "Added to Today" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { flash = nil }
                    }
                    return true
                }
                if notes.text.isEmpty {
                    Text("Write something down…")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.4)
                        .padding(.top, 2)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Text("\(notes.wordCount) \(notes.wordCount == 1 ? "word" : "words")")
                Spacer()
                Text(flash ?? "⌘↵ makes a task")
                    .foregroundStyle(flash == nil ? Theme.ink : Color(red: 0.12, green: 0.4, blue: 0.2))
                    .fontWeight(flash == nil ? .medium : .semibold)
            }
            .font(.system(size: 10.5, weight: .medium))
            .opacity(flash == nil ? 0.5 : 0.9)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(Theme.sand)
    }
}

// MARK: - AppKit text view (SwiftUI's TextEditor can't tell us the cursor's line before macOS 15)

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    /// Called with the trimmed line text; return true if a task was created.
    var onConvertLine: (String) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let tv = NoteTextView()
        tv.delegate = context.coordinator
        tv.onConvertLine = { line in context.coordinator.parent.onConvertLine(line) }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 13, weight: .medium)
        tv.textColor = NSColor(Theme.ink)
        tv.insertionPointColor = NSColor(Theme.ink)
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        init(_ parent: NoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

final class NoteTextView: NSTextView {
    var onConvertLine: ((String) -> Bool)?

    // The panel never activates the app, so accept the first click to place the cursor.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.contains(.command) {
            convertCurrentLine()
            return
        }
        super.keyDown(with: event)
    }

    private func convertCurrentLine() {
        let ns = string as NSString
        guard ns.length > 0 else { return }
        let lineRange = ns.lineRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0))
        var contentRange = lineRange
        let raw = ns.substring(with: lineRange)
        if raw.hasSuffix("\n") { contentRange.length -= 1 }

        let line = ns.substring(with: contentRange).trimmingCharacters(in: .whitespaces)
        // Lines marked ✓ by older versions were converted already; don't create duplicates.
        guard !line.isEmpty, !line.hasPrefix("✓"), onConvertLine?(line) == true else { return }

        // The line now lives in Tasks, so remove it from the note (undo brings it back).
        var removal = lineRange
        if !raw.hasSuffix("\n"), removal.location > 0 {
            // Last line has no newline of its own: take the one before it so no blank line is left behind.
            removal.location -= 1
            removal.length += 1
        }
        if shouldChangeText(in: removal, replacementString: "") {
            replaceCharacters(in: removal, with: "")
            didChangeText()
        }
    }
}
