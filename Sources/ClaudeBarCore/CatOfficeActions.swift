import Foundation

/// What ClaudeBar asks Cat Office to do for a session: answer its open dialog (POST /__agents/<id>/answer).
public enum CatOfficeActions {
    /// Sends `request` (an AnswerRequest) for `agentId`; nil when Cat Office took it, else why not in plain words.
    public static func answer(_ request: Data, agentId: String, bridge: BridgeInfo, session: URLSession = .shared) async -> String? {
        let id = agentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agentId
        var r = URLRequest(url: bridge.url.appendingPathComponent("__agents/\(id)/answer"), timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue(bridge.token, forHTTPHeaderField: "x-cat-office-token")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = request
        guard let (data, response) = try? await session.data(for: r), let http = response as? HTTPURLResponse else {
            return AnswerChoices.refusal(status: nil, error: nil)
        }
        if (200..<300).contains(http.statusCode) { return nil }
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        return AnswerChoices.refusal(status: http.statusCode, error: error)
    }
}
