import Foundation

/// One answer button: its title, what it means (hover), and the AnswerRequest JSON Cat Office expects for it.
public struct AnswerButton: Equatable, Sendable {
    public var title: String
    public var help: String?
    public var request: Data
}

/// What ClaudeBar shows for a waiting session's prompt, and the buttons that answer it through Cat Office
/// (POST /__agents/<id>/answer). No buttons: it can only be answered in Cat Office.
public struct AnswerChoices: Equatable, Sendable {
    public var prompt: String
    public var detail: String?
    public var buttons: [AnswerButton]

    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    public static func of(_ p: PendingPrompt) -> AnswerChoices {
        switch p {
        case let .permission(tool, input):
            let prompt = tool == "Bash" ? "Allow this command?" : editTools.contains(tool) ? "Allow this edit?" : "Allow \(tool)?"
            return AnswerChoices(prompt: prompt, detail: input.isEmpty ? nil : input, buttons: [
                button("Allow", ["kind": "permission", "choice": "yes"]),
                button("Always allow", ["kind": "permission", "choice": "yes-always"]),
                button("Deny", ["kind": "permission", "choice": "no"]),
            ])
        case let .question(questions):
            guard let q = questions.first else { return AnswerChoices(prompt: "Claude has a question", detail: nil, buttons: []) }
            guard questions.count == 1, !q.multiSelect else { return AnswerChoices(prompt: q.question, detail: nil, buttons: []) }
            return AnswerChoices(prompt: q.question, detail: nil, buttons: q.options.enumerated().map { i, o in
                var b = button(o.label, ["kind": "question", "answers": [["optionIndexes": [i]]]])
                b.help = o.description.isEmpty ? nil : o.description
                return b
            })
        case let .plan(plan):
            let first = plan.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }.map { String($0.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            return AnswerChoices(prompt: "Claude proposes a plan", detail: first, buttons: [
                button("Approve", ["kind": "plan", "choice": "approve"]),
                button("Reject", ["kind": "plan", "choice": "reject"]),
            ])
        }
    }

    private static func button(_ title: String, _ body: [String: Any]) -> AnswerButton {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return AnswerButton(title: title, help: nil, request: data)
    }

    /// Why an answer didn't go through, in plain words.
    public static func refusal(status: Int?, error: String?) -> String {
        guard let status else { return "Couldn't reach Cat Office" }
        if status == 409 { return "Cat Office can't answer this session: answer it in its terminal" }
        if let error, !error.isEmpty { return error }
        return "Cat Office couldn't send it (error \(status))"
    }
}
