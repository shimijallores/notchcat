import Foundation

struct APIError: Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Talks to notchcat-server. Knows nothing about tasks or tokens beyond what each call is given.
struct SyncAPI {
    let baseURL: URL
    var session: URLSession = .shared

    /// Parses what the user typed. Plain http is only allowed for a server on this Mac.
    static func normalizedURL(_ text: String) -> URL? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty else { return nil }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if url.scheme == "https" || (url.scheme == "http" && isLocal) { return url }
        return nil
    }

    // MARK: Auth

    func signUp(accessKey: String, username: String, password: String, device: String) async throws -> TokenPair {
        try await send("POST", "/v1/auth/signup",
                       body: ["access_key": accessKey, "username": username, "password": password, "device_name": device])
    }

    func login(username: String, password: String, device: String) async throws -> TokenPair {
        try await send("POST", "/v1/auth/login", body: ["username": username, "password": password, "device_name": device])
    }

    func refresh(_ refreshToken: String) async throws -> TokenPair {
        try await send("POST", "/v1/auth/refresh", body: ["refresh_token": refreshToken])
    }

    func logout(refreshToken: String) async {
        struct Empty: Decodable {}
        _ = try? await send("POST", "/v1/auth/logout", body: ["refresh_token": refreshToken]) as Empty?
    }

    // MARK: Sync

    func push(_ changes: [WireChange], accessToken: String) async throws -> PushResult {
        try await send("POST", "/v1/sync/push", body: PushBody(tasks: changes), token: accessToken)
    }

    func pull(cursor: Int, accessToken: String) async throws -> PullResult {
        try await send("GET", "/v1/sync/pull?cursor=\(cursor)&limit=500", token: accessToken)
    }

    // MARK: Plumbing

    private func send<T: Decodable>(_ method: String, _ path: String, body: (some Encodable)? = nil as [String: String]?,
                                    token: String? = nil) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw APIError(status: 0, message: "Bad server address") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, message: "No response from the server") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.message(from: data, status: http.statusCode))
        }
        if T.self == Empty.self || data.isEmpty, let empty = Empty() as? T { return empty }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Empty: Decodable {}

    /// FastAPI sends `{"detail": "text"}`, or a list of validation problems for malformed input.
    private static func message(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = object["detail"] as? String { return text }
            if let list = object["detail"] as? [[String: Any]], let first = list.first, let msg = first["msg"] as? String {
                return msg.replacingOccurrences(of: "Value error, ", with: "")
            }
        }
        return status >= 500 ? "The server had a problem. Try again in a moment." : "Request failed (\(status))"
    }
}
