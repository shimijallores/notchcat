import Foundation

/// A JSON scalar, as it travels to and from the server.
enum JSONValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let v) = self { return v } else { return nil } }
    var bool: Bool? { if case .bool(let v) = self { return v } else { return nil } }
    var int: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return v == v.rounded() ? Int(v) : nil
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    var isNull: Bool { if case .null = self { return true } else { return false } }

    // Optional builders, so a missing value becomes JSON null.
    static func from(_ v: Int?) -> JSONValue { v.map { .int($0) } ?? .null }
    static func from(_ v: Date?) -> JSONValue { v.map { .double($0.timeIntervalSince1970) } ?? .null }
}

// MARK: - Wire format (see notchcat-server/app/schemas.py)

struct WireChange: Codable {
    let collection: String
    let id: String
    let fields: [String: JSONValue]
    let fieldTs: [String: Int64]
    /// For the note only: the server version this edit was made on top of.
    var baseSeq: Int?

    enum CodingKeys: String, CodingKey { case collection, id, fields, fieldTs = "field_ts", baseSeq = "base_seq" }
}

struct PushBody: Codable {
    var changes: [WireChange]
}

struct WireRecord: Codable {
    let collection: String
    let id: String
    let fields: [String: JSONValue]
    let fieldTs: [String: Int64]
    let seq: Int

    enum CodingKeys: String, CodingKey { case collection, id, fields, fieldTs = "field_ts", seq }
}

struct WireRejected: Codable {
    let collection: String
    let id: String
    let reason: String
}

struct PushResult: Codable {
    let records: [WireRecord]
    let rejected: [WireRejected]
    let conflicts: [WireRecord]
}

struct PullResult: Codable {
    let records: [WireRecord]
    let cursor: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey { case records, cursor, hasMore = "has_more" }
}

struct AuthUser: Codable {
    let id: String
    let username: String
}

struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", user
    }
}

// MARK: - Local bookkeeping

/// What this Mac knows about a task's sync state.
struct TaskSyncMeta: Equatable {
    /// When each field was last edited, in epoch milliseconds (the winner of a conflict is the newer edit).
    var fieldTs: [String: Int64] = [:]
    /// Fields edited here that the server has not confirmed yet.
    var dirty: Set<String> = []
    /// The task was deleted here (or on another device); the row is gone but this remembers it.
    var deleted = false
}
