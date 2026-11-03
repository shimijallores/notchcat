import Foundation

/// The notepad: one long-lived note that is never reset, autosaved to SQLite.
@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore(db: .shared)

    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
        }
    }

    private let repo: NoteRepository
    private var saveWork: DispatchWorkItem?

    init(db: Database) {
        let repo = NoteRepository(db: db)
        self.repo = repo
        if let saved = repo.loadMain() {
            text = saved
        } else {
            // First run with the long-lived note: bring over anything written in the old per-day notepad.
            let merged = Self.merge(repo.legacyDailyNotes())
            repo.saveMain(merged)
            text = merged
        }
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        repo.saveMain(text)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// A single old note is used as is; several are stacked oldest first, each under its date.
    static func merge(_ notes: [(day: Date, body: String)]) -> String {
        guard notes.count > 1 else { return notes.first?.body ?? "" }
        return notes.map { note in
            "— \(note.day.formatted(.dateTime.month(.abbreviated).day().year())) —\n\(note.body)"
        }.joined(separator: "\n\n")
    }
}
