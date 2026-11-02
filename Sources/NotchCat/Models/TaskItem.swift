import Foundation

struct TaskItem: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    /// Start of the day this task currently sits on (moves forward when it rolls over).
    var day: Date
    /// Start of the day it was originally planned for. Used by Insights ("planned" vs "completed").
    var plannedDay: Date
    /// Optional focus time limit, in minutes.
    var timeLimitMinutes: Int?
    /// When to remind, and whether that reminder has already fired.
    var remindAt: Date?
    var reminded = false
    var createdAt = Date()
    var completedAt: Date?

    init(title: String, day: Date, timeLimitMinutes: Int? = nil) {
        self.title = title
        self.day = day
        self.plannedDay = day
        self.timeLimitMinutes = timeLimitMinutes
    }

    init(id: UUID, title: String, isDone: Bool, day: Date, plannedDay: Date, timeLimitMinutes: Int?,
         remindAt: Date?, reminded: Bool, createdAt: Date, completedAt: Date?) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.day = day
        self.plannedDay = plannedDay
        self.timeLimitMinutes = timeLimitMinutes
        self.remindAt = remindAt
        self.reminded = reminded
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

/// One finished or abandoned focus session, for Insights.
struct FocusSession {
    var taskID: UUID?
    var startedAt: Date
    /// Seconds the timer was actually running (paused and asleep time excluded).
    var activeSeconds: Int
    var plannedSeconds: Int
    var completed: Bool
}

/// A row in the Insights history list.
struct FinishedTask: Identifiable, Equatable {
    let id: UUID
    let title: String
    let completedAt: Date
    let plannedDay: Date
    let timeLimitMinutes: Int?
    /// Total focus time recorded against this task.
    let focusSeconds: Int
}
