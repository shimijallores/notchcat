import Foundation

/// The daily notepad: one note per calendar day, autosaved to SQLite.
@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore(db: .shared)

    @Published var text: String {
        didSet {
            guard text != oldValue, !isLoading else { return }
            scheduleSave()
        }
    }

    private let repo: NoteRepository
    private var day: Date
    private var isLoading = false
    private var saveWork: DispatchWorkItem?

    init(db: Database) {
        repo = NoteRepository(db: db)
        day = Calendar.current.startOfDay(for: Date())
        text = repo.body(for: day)
    }

    var currentDay: Date { day }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Switches to the new day's note after midnight.
    func rollOverIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != day else { return }
        flush()
        day = today
        isLoading = true
        text = repo.body(for: day)
        isLoading = false
        objectWillChange.send()
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        repo.save(text, for: day)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
