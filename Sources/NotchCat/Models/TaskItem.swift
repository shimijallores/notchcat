import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    /// Start of the day this task belongs to.
    var day: Date
    /// Optional focus time limit, in minutes.
    var timeLimitMinutes: Int?
    var createdAt = Date()
    var completedAt: Date?
}
