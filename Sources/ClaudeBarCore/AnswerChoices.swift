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

    /// A 409 from Cat Office in plain words: the dialog closed or changed, it isn't on screen, the prompt lacks that
    /// choice, or Cat Office can't type into this session (also any text it doesn't know).
    static func conflict(_ error: String) -> String {
        let e = error.lowercased()
        if e.hasPrefix("nothing to answer") || e.hasPrefix("the open dialog is a") || e == "the question changed"
            || e == "the session has ended" {
            return "That question closed or changed before your answer got there"
        }
        if e.hasSuffix("is not on screen") { return "The question isn't on screen in its terminal" }
        if e.contains("has no \"yes-always\" option") { return "This prompt has no Always allow" }
        if e.contains("prompt has no \"") { return "This prompt has no such choice: answer it in its terminal" }
        return "Cat Office can't answer this session: answer it in its terminal"
    }

    /// Why an answer didn't go through, in plain words.
    public static func refusal(status: Int?, error: String?) -> String {
        guard let status else { return "Couldn't reach Cat Office" }
        if status == 409 { return conflict(error ?? "") }
        if let error, !error.isEmpty { return error }
        return "Cat Office couldn't send it (error \(status))"
    }
}
