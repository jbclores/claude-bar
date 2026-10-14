# ClaudeBar Sessions (Jump, Answer, Today's Recap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From ClaudeBar, open any session in Cat Office or its terminal, answer a waiting one, and see today's recap.

**Architecture:** Pure Core units — `PendingPrompt` decoding, `AnswerChoices` (prompt → buttons → Cat Office's
`AnswerRequest`), `CatOfficeActions` (POST /answer), `SessionLog`/`TodayRecap` — tested on their own. A small Cat
Office patch adds `?agent=<id>`. The app wires them into the hover card (kept open while the pointer is on it, and
excluded from the room's zoom clicks), the office list's waiting row, a "Show terminal" finder (pid → tty →
Terminal/iTerm via AppleScript), and a recap line on Projects.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, Swift Testing, SwiftUI, Network framework (test server);
Cat Office: TypeScript, React, node:test via `npx tsx --test`.

**Spec:** `docs/superpowers/specs/2026-10-14-claudebar-sessions-design.md`

## Global Constraints

- The real Cat Office folder `~/Documents/projects/cat-ai-office-with-art-20261006-1038` is READ-ONLY. Patch work happens in temp copies (`/tmp/sess-orig` pristine, `/tmp/sess-work` patched, node_modules symlinked); `patches/cat-office.patch` is regenerated with `scripts/make-cat-office-patch.sh`.
- Tests never touch the real `~/.claude`, `~/.config/claude-bar`, a real Cat Office, or the installed app; click tests run with side effects off.
- Answer endpoint: `POST <base>/__agents/<id>/answer`, header `x-cat-office-token`, JSON body exactly Cat Office's `AnswerRequest`: `{"kind":"permission","choice":"yes"|"yes-always"|"no"}`, `{"kind":"question","answers":[{"optionIndexes":[i]}]}`, `{"kind":"plan","choice":"approve"|"reject"}`.
- Wording, exactly: "Allow this command?" (tool `Bash`), "Allow this edit?" (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`), else "Allow <tool>?"; buttons "Allow", "Always allow", "Deny"; "Claude proposes a plan" with "Approve", "Reject"; "Answer in Cat Office"; "Open in Cat Office"; "Show terminal"; "Sent".
- 409 from /answer → "Cat Office can't answer this session: answer it in its terminal". Other failures → "Couldn't reach Cat Office" (network) or Cat Office's own `error` text.
- Recap line, exactly: "4 sessions finished · 2h 10m working · busiest: claude-bar"; "1 session finished"; no "busiest" with fewer than two projects; hidden when nothing happened today.
- Session log: `~/.claude/claude-bar/sessions-today.jsonl`, kept 2 days.
- Sentence case; match the surrounding style; doc comments on new types.

## Review Focus

1. A waiting session whose question changes or closes between the snapshot and the click (Cat Office 409): the row shows the plain reason and the jump links, never a stuck "Sent". (Task 2 test `refusalsReadPlainly`; Task 6 checks the row after an error.)
2. The pointer moving from a cat onto its card: the card stays; leaving both closes it; the card's buttons get the click, not the room's zoom. (Task 6 click test clicks a card button.)
3. A session working across midnight: today's working time counts from midnight, not from yesterday's start. (Task 4 test `spansAcrossMidnightCountFromMidnight`.)
4. A pid without a terminal (Orca, VS Code, a headless worker): no "Show terminal" link, no AppleScript run. (Task 6: `TerminalFinder.tty(of:)` nil → link hidden; unit test on the parse.)
5. An `?agent=` id that isn't (or is no longer) in the office: Cat Office opens as usual and drops the parameter. (Task 5 test.)

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/ClaudeBarCore/PendingPrompt.swift` (new) | `PendingPrompt` + decoding; `OfficeAgent.pendingPrompt`, `OfficeAgent.pid` |
| `Sources/ClaudeBarCore/AnswerChoices.swift` (new) | What to show for a prompt; the AnswerRequest JSON; error wording |
| `Sources/ClaudeBarCore/CatOfficeActions.swift` (new) | POST /answer; `CatOfficeClient.bridge` (current URL + token) |
| `Sources/ClaudeBarCore/SessionLog.swift` (new) | Working spans and finishes; `TodayRecap` |
| `Sources/ClaudeBar/TerminalFinder.swift` (new) | pid → tty → bring Terminal / iTerm forward |
| `Sources/ClaudeBar/Views/SessionViews.swift` (new) | Answer buttons view, jump links, recap line |
| `Sources/ClaudeBar/AppState.swift`, `RoomZoom.swift`, `Views/OfficePeekView.swift`, `Views/OfficeSectionView.swift`, `Views/DropdownView.swift`, `RenderPeek.swift` | Wiring, sticky card, list row, Projects line, renders, click test |
| Cat Office (temp copy): `src/agents/live/agent-link.ts` (new), `src/components/mission/MissionControl.tsx`, `tests/sim/agent-link.test.ts` (new) | `?agent=<id>` |
| `scripts/make-cat-office-patch.sh` | Add the two new Cat Office files to FILES |

---

### Task 1: Decode what a waiting session waits on

**Files:** Create `Sources/ClaudeBarCore/PendingPrompt.swift`; Modify `Sources/ClaudeBarCore/OfficeAgent.swift`; Test `Tests/ClaudeBarCoreTests/PendingPromptTests.swift`

**Interfaces — Produces:**
```swift
public enum PendingPrompt: Equatable, Sendable {
    public struct Option: Equatable, Sendable { public var label: String; public var description: String }
    public struct Question: Equatable, Sendable { public var question: String; public var header: String; public var multiSelect: Bool; public var options: [Option] }
    case question([Question])
    case permission(tool: String, input: String)
    case plan(String)
}
// OfficeAgent: public var pendingPrompt: PendingPrompt?   public var pid: Int32?
```

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct PendingPromptTests {
    func agent(_ json: String) throws -> OfficeAgent { try JSONDecoder().decode(OfficeAgent.self, from: Data(json.utf8)) }

    @Test func decodesEachKind() throws {
        let p = try agent(#"{"id":"a","status":"waiting","pid":4242,"pendingPrompt":{"kind":"permission","tool":"Bash","input":"npm run build"}}"#)
        #expect(p.pendingPrompt == .permission(tool: "Bash", input: "npm run build"))
        #expect(p.pid == 4242)
        let q = try agent(#"{"id":"a","status":"waiting","pendingPrompt":{"kind":"question","questions":[{"question":"Which auth?","header":"Auth","multiSelect":false,"options":[{"label":"OAuth","description":"Sign in"},{"label":"Token","description":"Paste"}]}]}}"#)
        #expect(q.pendingPrompt == .question([.init(question: "Which auth?", header: "Auth", multiSelect: false,
                                                     options: [.init(label: "OAuth", description: "Sign in"), .init(label: "Token", description: "Paste")])]))
        let plan = try agent(#"{"id":"a","status":"waiting","pendingPrompt":{"kind":"plan","plan":"# Plan\nDo it"}}"#)
        #expect(plan.pendingPrompt == .plan("# Plan\nDo it"))
    }

    @Test func missingOrUnknownIsNil() throws {
        #expect(try agent(#"{"id":"a","status":"idle"}"#).pendingPrompt == nil)
        #expect(try agent(#"{"id":"a","status":"waiting","pendingPrompt":null}"#).pendingPrompt == nil)
        #expect(try agent(#"{"id":"a","status":"waiting","pendingPrompt":{"kind":"something-new"}}"#).pendingPrompt == nil)
        #expect(try agent(#"{"id":"a","status":"idle","pid":null}"#).pid == nil)
    }
}
```

- [ ] **Step 2:** `swift test --filter PendingPromptTests` — Expected: FAIL to compile (no `PendingPrompt`).
- [ ] **Step 3: Implement** — `PendingPrompt.swift`:

```swift
import Foundation

/// What a waiting session waits on (Cat Office's pendingPrompt, read from its transcript): a question with options,
/// a tool call to allow, or a plan to approve.
public enum PendingPrompt: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Decodable {
        public var label: String
        public var description: String
        public init(label: String, description: String) { self.label = label; self.description = description }
    }
    public struct Question: Equatable, Sendable, Decodable {
        public var question: String
        public var header: String
        public var multiSelect: Bool
        public var options: [Option]
        public init(question: String, header: String, multiSelect: Bool, options: [Option]) {
            self.question = question; self.header = header; self.multiSelect = multiSelect; self.options = options
        }
    }
    case question([Question])
    case permission(tool: String, input: String)
    case plan(String)
}

extension PendingPrompt: Decodable {
    private enum Keys: String, CodingKey { case kind, questions, tool, input, plan }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "question": self = .question(try c.decode([Question].self, forKey: .questions))
        case "permission": self = .permission(tool: try c.decode(String.self, forKey: .tool), input: try c.decodeIfPresent(String.self, forKey: .input) ?? "")
        case "plan": self = .plan(try c.decode(String.self, forKey: .plan))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind")
        }
    }
}
```

In `OfficeAgent`: add `public var pendingPrompt: PendingPrompt?` and `public var pid: Int32?`; add `pendingPrompt, pid` to `CodingKeys`; in `init(from:)`:
`pendingPrompt = (try? c.decodeIfPresent(PendingPrompt.self, forKey: .pendingPrompt)) ?? nil` and
`pid = (try? c.decodeIfPresent(Int32.self, forKey: .pid)) ?? nil`.

- [ ] **Step 4:** `swift test --filter PendingPromptTests` — PASS (2); `swift test` — all pass.
- [ ] **Step 5: Commit** — `git commit -m "feat: read what a waiting session waits on (Cat Office's pendingPrompt) and its pid"`

### Task 2: What to show, and what to send

**Files:** Create `Sources/ClaudeBarCore/AnswerChoices.swift`; Test `Tests/ClaudeBarCoreTests/AnswerChoicesTests.swift`

**Interfaces — Consumes:** `PendingPrompt` (Task 1). **Produces:**
```swift
public struct AnswerChoices: Equatable, Sendable {
    public struct Button: Equatable, Sendable { public var title: String; public var help: String?; public var body: [String: AnyCodable-free JSON as Data] }
}
```
Concretely:
```swift
public struct AnswerButton: Equatable, Sendable { public var title: String; public var help: String?; public var request: Data }
public struct AnswerChoices: Equatable, Sendable {
    public var prompt: String        // "Allow this command?", the question, or "Claude proposes a plan"
    public var detail: String?       // the input summary, or the plan's first line
    public var buttons: [AnswerButton]   // empty: answer in Cat Office
    public static func of(_ p: PendingPrompt) -> AnswerChoices
    public static func refusal(status: Int?, error: String?) -> String
}
```

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct AnswerChoicesTests {
    func json(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    @Test func permissionsByTool() {
        let bash = AnswerChoices.of(.permission(tool: "Bash", input: "npm run build"))
        #expect(bash.prompt == "Allow this command?" && bash.detail == "npm run build")
        #expect(bash.buttons.map(\.title) == ["Allow", "Always allow", "Deny"])
        #expect(bash.buttons.map { json($0.request) } == [
            #"{"choice":"yes","kind":"permission"}"#, #"{"choice":"yes-always","kind":"permission"}"#, #"{"choice":"no","kind":"permission"}"#])
        #expect(AnswerChoices.of(.permission(tool: "Edit", input: "a.swift")).prompt == "Allow this edit?")
        #expect(AnswerChoices.of(.permission(tool: "WebFetch", input: "x")).prompt == "Allow WebFetch?")
    }

    @Test func oneSingleQuestionGetsItsOptions() {
        let q = PendingPrompt.Question(question: "Which auth?", header: "Auth", multiSelect: false,
                                       options: [.init(label: "OAuth", description: "Sign in"), .init(label: "Token", description: "Paste")])
        let c = AnswerChoices.of(.question([q]))
        #expect(c.prompt == "Which auth?" && c.buttons.map(\.title) == ["OAuth", "Token"])
        #expect(c.buttons[1].help == "Paste")
        #expect(json(c.buttons[1].request) == #"{"answers":[{"optionIndexes":[1]}],"kind":"question"}"#)
        var multi = q
        multi.multiSelect = true
        #expect(AnswerChoices.of(.question([multi])).buttons.isEmpty, "multi-pick: answer in Cat Office")
        #expect(AnswerChoices.of(.question([q, q])).buttons.isEmpty, "several questions: answer in Cat Office")
    }

    @Test func plans() {
        let c = AnswerChoices.of(.plan("# Add login\n\nSteps…"))
        #expect(c.prompt == "Claude proposes a plan" && c.detail == "Add login")
        #expect(c.buttons.map(\.title) == ["Approve", "Reject"])
        #expect(json(c.buttons[0].request) == #"{"choice":"approve","kind":"plan"}"#)
    }

    @Test func refusalsReadPlainly() {
        #expect(AnswerChoices.refusal(status: 409, error: "no terminal") == "Cat Office can't answer this session: answer it in its terminal")
        #expect(AnswerChoices.refusal(status: nil, error: nil) == "Couldn't reach Cat Office")
        #expect(AnswerChoices.refusal(status: 400, error: "answers don't fit") == "answers don't fit")
        #expect(AnswerChoices.refusal(status: 500, error: nil) == "Cat Office couldn't send it (error 500)")
    }
}
```

- [ ] **Step 2:** `swift test --filter AnswerChoicesTests` — FAIL to compile.
- [ ] **Step 3: Implement**

```swift
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
```

- [ ] **Step 4:** `swift test --filter AnswerChoicesTests` — PASS (4); `swift test` — all pass.
- [ ] **Step 5: Commit** — `git commit -m "feat: answer choices for a waiting prompt, and the request Cat Office expects"`

### Task 3: Send the answer

**Files:** Create `Sources/ClaudeBarCore/CatOfficeActions.swift`; Modify `Sources/ClaudeBarCore/CatOfficeClient.swift` (keep the live `BridgeInfo`); Test `Tests/ClaudeBarCoreTests/CatOfficeActionsTests.swift`

**Interfaces — Produces:**
```swift
public enum CatOfficeActions {
    /// nil on success, else the plain-words refusal (AnswerChoices.refusal).
    public static func answer(_ request: Data, agentId: String, bridge: BridgeInfo, session: URLSession = .shared) async -> String?
}
// CatOfficeClient: public var bridge: BridgeInfo? — the url + token of the feed it follows now (set in follow(_:)).
```

- [ ] **Step 1: Failing test** — a local HTTP server on 127.0.0.1 (Network framework) that records one request and answers with a chosen status:

```swift
import Foundation
import Network
import Testing
@testable import ClaudeBarCore

/// A one-request HTTP server on 127.0.0.1: records what it got, answers `status` with `body`.
final class OneShotServer: @unchecked Sendable {
    let listener: NWListener
    private(set) var received = ""
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(status: Int, body: String) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [unowned self] conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                self.received = String(decoding: data ?? Data(), as: UTF8.self)
                let reply = "HTTP/1.1 \(status) X\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                conn.send(content: Data(reply.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.start(queue: .global())
    }

    func waitReady() async throws { for _ in 0..<50 where port == 0 { try await Task.sleep(nanoseconds: 20_000_000) } }
}

@Suite struct CatOfficeActionsTests {
    @Test func postsTheAnswerWithTheToken() async throws {
        let server = try OneShotServer(status: 200, body: #"{"ok":true}"#)
        defer { server.listener.cancel() }
        try await server.waitReady()
        let bridge = BridgeInfo(url: URL(string: "http://127.0.0.1:\(server.port)")!, token: "t0k3n")
        let request = Data(#"{"choice":"yes","kind":"permission"}"#.utf8)
        let result = await CatOfficeActions.answer(request, agentId: "sess-1", bridge: bridge)
        #expect(result == nil)
        #expect(server.received.hasPrefix("POST /__agents/sess-1/answer "))
        #expect(server.received.lowercased().contains("x-cat-office-token: t0k3n"))
        #expect(server.received.hasSuffix(#"{"choice":"yes","kind":"permission"}"#))
    }

    @Test func aRefusalComesBackInPlainWords() async throws {
        let server = try OneShotServer(status: 409, body: #"{"error":"no terminal"}"#)
        defer { server.listener.cancel() }
        try await server.waitReady()
        let bridge = BridgeInfo(url: URL(string: "http://127.0.0.1:\(server.port)")!, token: "t")
        #expect(await CatOfficeActions.answer(Data("{}".utf8), agentId: "x", bridge: bridge)
                == "Cat Office can't answer this session: answer it in its terminal")
        let nobody = BridgeInfo(url: URL(string: "http://127.0.0.1:1")!, token: "t")
        #expect(await CatOfficeActions.answer(Data("{}".utf8), agentId: "x", bridge: nobody) == "Couldn't reach Cat Office")
    }
}
```

- [ ] **Step 2:** `swift test --filter CatOfficeActionsTests` — FAIL to compile.
- [ ] **Step 3: Implement**

```swift
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
```

In `CatOfficeClient`: add `private let live = LockedBox<BridgeInfo?>(nil)` and `public var bridge: BridgeInfo? { live.get() }`; in `follow(_:)` after `current.set(info.url)`: `live.set(info)`.

- [ ] **Step 4:** `swift test --filter CatOfficeActionsTests` — PASS (2); `swift test` — all pass.
- [ ] **Step 5: Commit** — `git commit -m "feat: send an answer to Cat Office (POST /answer with the token)"`

### Task 4: The session log and today's recap

**Files:** Create `Sources/ClaudeBarCore/SessionLog.swift`; Test `Tests/ClaudeBarCoreTests/SessionLogTests.swift`

**Interfaces — Produces:**
```swift
public struct SessionEvent: Codable, Equatable, Sendable { public var at: Date; public var key: String; public var project: String; public var working: Bool; public var finished: Bool }
public struct SessionLog: Equatable, Sendable {
    public private(set) var events: [SessionEvent]
    public static var defaultFile: URL   // ~/.claude/claude-bar/sessions-today.jsonl
    public mutating func update(_ sessions: [(key: String, project: String, status: AgentStatus)], now: Date) -> Bool  // true when events were added
    public static func load(_ file: URL) -> SessionLog; public func save(_ file: URL) throws
}
public struct TodayRecap: Equatable, Sendable {
    public var finished: Int; public var working: TimeInterval; public var busiest: String?
    public static func of(_ log: SessionLog, now: Date, calendar: Calendar) -> TodayRecap
    public var line: String?   // nil when nothing happened
}
```

Rules: `update` compares with the last known status per key (kept in memory, `private var last: [String: AgentStatus]`; the first sight of a key records nothing unless it is working — then a `working: true` event). working → anything else: an event `working: false, finished: (new status is idle or ended)`. not-working → working: `working: true`. A key that disappears while working: `working: false, finished: false`. Trim events older than 2 days.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SessionLogTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// 2027-01-15 08:00 UTC.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    @Test func spansAndFinishes() {
        var log = SessionLog()
        _ = log.update([("a", "claude-bar", .idle)], now: at(0))
        _ = log.update([("a", "claude-bar", .working)], now: at(10))
        _ = log.update([("a", "claude-bar", .waiting)], now: at(40))     // stops working, not finished
        _ = log.update([("a", "claude-bar", .working)], now: at(45))
        _ = log.update([("a", "claude-bar", .idle), ("b", "turbo", .working)], now: at(60))
        _ = log.update([("b", "turbo", .ended)], now: at(70))
        let r = TodayRecap.of(log, now: at(80), calendar: utc)
        #expect(r.finished == 2)
        #expect(r.working == (30 + 15 + 10) * 60)
        #expect(r.busiest == "claude-bar")
        #expect(r.line == "2 sessions finished · 55m working · busiest: claude-bar")
    }

    @Test func spansAcrossMidnightCountFromMidnight() {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(-9 * 60))   // yesterday 23:00
        _ = log.update([("a", "p", .idle)], now: at(-7 * 60))       // today 01:00
        let r = TodayRecap.of(log, now: at(0), calendar: utc)
        #expect(r.working == 3600 && r.finished == 1 && r.busiest == nil)
        #expect(r.line == "1 session finished · 1h working")
    }

    @Test func anOpenSpanCountsToNowAndNothingHidesTheLine() {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(0))
        #expect(TodayRecap.of(log, now: at(130), calendar: utc).line == "0 sessions finished · 2h 10m working")
        #expect(TodayRecap.of(SessionLog(), now: at(0), calendar: utc).line == nil)
    }

    @Test func trimsToTwoDaysAndRoundTrips() throws {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(-3 * 24 * 60))
        _ = log.update([("a", "p", .idle)], now: at(0))
        #expect(log.events.count == 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-sess-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sessions-today.jsonl")
        try log.save(file)
        #expect(SessionLog.load(file).events == log.events)
    }
}
```

- [ ] **Step 2:** `swift test --filter SessionLogTests` — FAIL to compile.
- [ ] **Step 3: Implement**

```swift
import Foundation

/// A session starting or stopping work (finished: it went idle or ended, not waiting).
public struct SessionEvent: Codable, Equatable, Sendable {
    public var at: Date
    public var key: String
    public var project: String
    public var working: Bool
    public var finished: Bool
}

/// ClaudeBar's log of sessions starting and stopping work (~/.claude/claude-bar/sessions-today.jsonl), 2 days kept:
/// enough for today's recap across midnight.
public struct SessionLog: Equatable, Sendable {
    public private(set) var events: [SessionEvent] = []
    private var last: [String: (status: AgentStatus, project: String)] = [:]
    static let keepFor: TimeInterval = 2 * 86_400

    public init(events: [SessionEvent] = []) { self.events = events }
    public static func == (a: SessionLog, b: SessionLog) -> Bool { a.events == b.events }

    public static var defaultFile: URL { Paths.home.appendingPathComponent(".claude/claude-bar/sessions-today.jsonl") }

    /// Notes who started or stopped working since the last update. True when events were added.
    @discardableResult
    public mutating func update(_ sessions: [(key: String, project: String, status: AgentStatus)], now: Date) -> Bool {
        let before = events.count
        var seen = Set<String>()
        for s in sessions {
            seen.insert(s.key)
            let was = last[s.key]?.status
            let working = s.status == .working
            if working, was != .working {
                events.append(SessionEvent(at: now, key: s.key, project: s.project, working: true, finished: false))
            } else if !working, was == .working {
                events.append(SessionEvent(at: now, key: s.key, project: s.project, working: false,
                                           finished: s.status == .idle || s.status == .ended))
            }
            last[s.key] = (s.status, s.project)
        }
        for (key, info) in last where !seen.contains(key) {
            if info.status == .working {
                events.append(SessionEvent(at: now, key: key, project: info.project, working: false, finished: false))
            }
            last[key] = nil
        }
        events.removeAll { now.timeIntervalSince($0.at) > Self.keepFor }
        return events.count != before
    }

    public static func load(_ file: URL) -> SessionLog {
        guard let data = try? Data(contentsOf: file) else { return SessionLog() }
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        return SessionLog(events: data.split(separator: UInt8(ascii: "\n")).compactMap { try? d.decode(SessionEvent.self, from: Data($0)) })
    }

    public func save(_ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; e.outputFormatting = .sortedKeys
        let lines = try events.map { String(decoding: try e.encode($0), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Today so far: sessions that finished, time spent working (since midnight; an open span counts to now), and the
/// project with the most of it.
public struct TodayRecap: Equatable, Sendable {
    public var finished: Int
    public var working: TimeInterval
    public var busiest: String?

    public static func of(_ log: SessionLog, now: Date, calendar: Calendar) -> TodayRecap {
        let midnight = calendar.startOfDay(for: now)
        var open: [String: (Date, String)] = [:], byProject: [String: TimeInterval] = [:], finished = 0
        func close(_ key: String, at end: Date) {
            guard let (start, project) = open.removeValue(forKey: key) else { return }
            let span = max(0, min(end, now).timeIntervalSince(max(start, midnight)))
            byProject[project, default: 0] += span
        }
        for e in log.events where e.at <= now {
            if e.working { open[e.key] = (e.at, e.project) } else {
                close(e.key, at: e.at)
                if e.finished, e.at >= midnight { finished += 1 }
            }
        }
        for key in Array(open.keys) { close(key, at: now) }
        let total = byProject.values.reduce(0, +)
        let projects = byProject.filter { $0.value > 0 }
        let busiest = projects.count >= 2 ? projects.max { $0.value < $1.value }?.key : nil
        return TodayRecap(finished: finished, working: total, busiest: busiest)
    }

    /// "4 sessions finished · 2h 10m working · busiest: claude-bar"; nil when nothing happened today.
    public var line: String? {
        guard finished > 0 || working >= 60 else { return nil }
        let m = Int(working / 60), time = m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
        var parts = ["\(finished) session\(finished == 1 ? "" : "s") finished", "\(time) working"]
        if let busiest { parts.append("busiest: \(busiest)") }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4:** `swift test --filter SessionLogTests` — PASS (4); `swift test` — all pass.
- [ ] **Step 5: Commit** — `git commit -m "feat: session log and today's recap"`

### Task 5: Cat Office opens on an agent (`?agent=<id>`) — patch

**Files (temp copies):** `/tmp/sess-work/src/agents/live/agent-link.ts` (new), `/tmp/sess-work/src/components/mission/MissionControl.tsx`, `/tmp/sess-work/tests/sim/agent-link.test.ts` (new); repo: `scripts/make-cat-office-patch.sh` (FILES += the two new files), `patches/cat-office.patch`.

- [ ] **Step 1: Temp copies** (the real folder is read-only):

```bash
CO=~/Documents/projects/cat-ai-office-with-art-20261006-1038
rm -rf /tmp/sess-orig /tmp/sess-work && mkdir -p /tmp/sess-orig /tmp/sess-work
rsync -a --exclude node_modules --exclude .cat-office --exclude .git $CO/ /tmp/sess-work/
rsync -a --exclude node_modules --exclude .cat-office --exclude .git $CO/ /tmp/sess-orig/
(cd /tmp/sess-orig && patch -R -p1 -s < ~/Documents/projects/claude-bar/patches/cat-office.patch)
ln -sfn $CO/node_modules /tmp/sess-work/node_modules
scripts/make-cat-office-patch.sh /tmp/sess-orig /tmp/sess-work && git diff --stat patches/   # Expected: no change
```

- [ ] **Step 2: Failing test** `/tmp/sess-work/tests/sim/agent-link.test.ts`:

```ts
// ?agent=<id>: ClaudeBar's "Open in Cat Office" link opens the page on that agent; the parameter is then dropped.
import assert from 'node:assert/strict';
import { test } from 'node:test';

const { agentParam, withoutAgentParam } = await import('../../src/agents/live/agent-link.ts');

test('agentParam: the id in ?agent=, else null', () => {
  assert.equal(agentParam('?agent=sess-1'), 'sess-1');
  assert.equal(agentParam('?floor=3&agent=a%2Fb'), 'a/b');
  assert.equal(agentParam('?floor=3'), null);
  assert.equal(agentParam('?agent='), null);
});

test('withoutAgentParam: the same address without it', () => {
  assert.equal(withoutAgentParam('http://localhost:5173/?agent=x'), 'http://localhost:5173/');
  assert.equal(withoutAgentParam('http://localhost:5173/?floor=3&agent=x#y'), 'http://localhost:5173/?floor=3#y');
  assert.equal(withoutAgentParam('http://localhost:5173/'), 'http://localhost:5173/');
});
```

Run: `cd /tmp/sess-work && npx tsx --test tests/sim/agent-link.test.ts` — Expected: FAIL (module not found).

- [ ] **Step 3: Implement** `/tmp/sess-work/src/agents/live/agent-link.ts`:

```ts
/*
 * ?agent=<id>: other local apps (ClaudeBar's "Open in Cat Office") open the page on one agent's drawer. Read once
 * when the agents are in; then dropped from the address so a reload doesn't open it again.
 */

/** The agent id in the URL (?agent=sess-1), or null. */
export function agentParam(search = window.location.search): string | null {
  const id = new URLSearchParams(search).get('agent');
  return id ? id : null;
}

/** `href` without its ?agent= parameter. */
export function withoutAgentParam(href = window.location.href): string {
  const url = new URL(href);
  url.searchParams.delete('agent');
  return url.toString();
}
```

In `MissionControl.tsx`, import `{ agentParam, withoutAgentParam }` from `'../../agents/live/agent-link'`, and after `pickAgentId` is defined add:

```tsx
  // ?agent=<id> (ClaudeBar's "Open in Cat Office"): once the agents are in, open that agent's drawer, then drop it.
  const linkedAgent = useRef(agentParam());
  useEffect(() => {
    const id = linkedAgent.current;
    if (!id || agents.length === 0) return;
    linkedAgent.current = null;
    if (agents.some((a) => a.id === id)) pickAgentId(id);
    window.history.replaceState(null, '', withoutAgentParam());
  }, [agents]); // eslint-disable-line react-hooks/exhaustive-deps
```

(`useRef`/`useEffect` are already imported in MissionControl; add them to the React import if not.)

- [ ] **Step 4:** `cd /tmp/sess-work && npx tsx --test tests/sim/agent-link.test.ts` — PASS (2); `npx tsc -p tsconfig.app.json --noEmit` — no errors; `npm run -s test:sim` — all ok.
- [ ] **Step 5: Patch** — add `src/agents/live/agent-link.ts` and `tests/sim/agent-link.test.ts` to FILES in `scripts/make-cat-office-patch.sh` (sorted place), then `scripts/make-cat-office-patch.sh /tmp/sess-orig /tmp/sess-work`; commit; then `scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038` — Expected: all PASS; upgrade a temp copy of the real Cat Office (`rsync` to /tmp/sess-upg, `scripts/patch-cat-office.sh /tmp/sess-upg` → "Took out the older version"), `rm -rf /tmp/sess-upg`.
- [ ] **Step 6: Commit** — `git commit -m "feat(patch): Cat Office opens on an agent with ?agent=<id>"`

### Task 6: The app — jump, answer, recap

**Files:** Create `Sources/ClaudeBar/TerminalFinder.swift`, `Sources/ClaudeBar/Views/SessionViews.swift`; Modify `AppState.swift`, `RoomZoom.swift`, `Views/OfficePeekView.swift` (CatCard, sticky card), `Views/OfficeSectionView.swift` (waiting row), `Views/DropdownView.swift` (Projects recap), `RenderPeek.swift` (render seam, click test), `Resources/Help/guide.html`, `Resources/Help/changes.html`, `README.md`.

**Interfaces — Consumes:** Tasks 1–4. **Produces (AppState):**
```swift
func openInCatOffice(_ agent: OfficeAgent)            // <base>/?agent=<agent.id>
func showTerminal(_ agent: OfficeAgent)               // TerminalFinder
func canShowTerminal(_ agent: OfficeAgent) -> Bool    // pid has a tty and Terminal/iTerm runs
@Published var answerState: [String: AnswerState]     // agent id → .sending / .sent / .failed(String)
func answer(_ agent: OfficeAgent, _ button: AnswerButton)
@Published private(set) var sessionLog: SessionLog
var todayRecap: TodayRecap { TodayRecap.of(sessionLog, now: Date(), calendar: .current) }
enum AnswerState: Equatable { case sending, sent, failed(String) }
```

- [ ] **Step 1: TerminalFinder** — a unit-testable parse plus the AppleScript:

```swift
import AppKit

/// "Show terminal": the session's process → its tty → the Terminal or iTerm tab using it, brought forward.
enum TerminalFinder {
    /// `ps -o tty= -p <pid>` output → "/dev/ttys004"; nil for "??" (no terminal) or nothing.
    static func ttyPath(psOutput: String) -> String? {
        let t = psOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "??" else { return nil }
        return t.hasPrefix("/dev/") ? t : "/dev/" + t
    }

    static func tty(of pid: Int32) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(pid)]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return ttyPath(psOutput: String(decoding: data, as: UTF8.self))
    }

    static var terminalsRunning: [String] {
        ["com.apple.Terminal", "com.googlecode.iterm2"].filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// Brings forward the Terminal / iTerm tab on `tty`. False when none was found.
    @discardableResult
    static func show(tty: String) -> Bool {
        let scripts = [
            "com.apple.Terminal": """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            """,
            "com.googlecode.iterm2": """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      select t
                      activate
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """,
        ]
        for app in terminalsRunning {
            var error: NSDictionary?
            if NSAppleScript(source: scripts[app]!)?.executeAndReturnError(&error).stringValue == "ok" { return true }
        }
        return false
    }
}
```

Add `Tests` for the parse? It is app-target code (no test target) — instead put `ttyPath(psOutput:)` in Core as `TerminalTTY.path(psOutput:)` with a Core test: `"ttys004\n"` → `/dev/ttys004`; `"??"` → nil; `""` → nil. (Write that test first; watch it fail; implement; pass.)

- [ ] **Step 2: AppState wiring**
  - `openInCatOffice`: `var c = URLComponents(url: officeClient.baseURL, resolvingAgainstBaseURL: false)!; c.queryItems = [URLQueryItem(name: "agent", value: agent.id)]; NSWorkspace.shared.open(c.url!)`.
  - `canShowTerminal`: `agent.pid.flatMap(TerminalFinder.tty(of:)) != nil && !TerminalFinder.terminalsRunning.isEmpty` (cache per pid for 10 s to keep hover cheap).
  - `answer`: `guard let bridge = officeClient.bridge else { answerState[agent.id] = .failed("Couldn't reach Cat Office"); return }`; set `.sending`; `Task { let r = await CatOfficeActions.answer(button.request, agentId: agent.id, bridge: bridge); answerState[agent.id] = r.map(AnswerState.failed) ?? .sent }`. When side effects are off (click test), record the request in `@Published private(set) var lastAnswerRequest: (id: String, body: Data)?` and set `.sent` without sending.
  - Clear `answerState[id]` when that agent's `pendingPrompt` changes or it stops waiting (in `officeUpdated`).
  - Session log: load once from `SessionLog.defaultFile` (side effects on), and after each `recompute()` call `sessionLog.update(tracked.map { ($0.key, project, $0.status) }, now:)` using each office agent's `repoName ?? last path component of cwd`; save when it returns true.
- [ ] **Step 3: Sticky, clickable card** — `RoomZoom`: add `var excluded: [CGRect] = []` and make `contains(_:)` return false for points inside any `excluded` rect. In `OfficeRoomView`: keep `@State private var cardAgent: OfficeAgent?` and `@State private var cardRect: CGRect = .zero`; `shown = hovered ?? (pointer.location.map { cardRect.contains($0) } == true ? cardAgent : nil)`; when `hovered` is non-nil set `cardAgent = hovered`; draw `CatCard` for `shown`, report its frame in `.named("office")` into `cardRect` and `zoom.excluded = [cardRect]` (clear both when nothing is shown).
- [ ] **Step 4: Card and row content** — `SessionViews.swift`:
  - `JumpLinks(agent:)`: "Open in Cat Office" (link) and, when `state.canShowTerminal(agent)`, "Show terminal".
  - `AnswerPanel(agent:)`: when `agent.status == .waiting`, `let p = agent.pendingPrompt` and not a spare: `let c = AnswerChoices.of(p)`; text `c.prompt` (callout, semibold), `c.detail` (caption, monospaced for permissions, one line); then by `state.answerState[agent.id]`: `.sent` → "Sent" (Theme.working), `.sending` → small spinner, `.failed(msg)` → msg (Theme.waiting) + JumpLinks; else `c.buttons` as `.borderedProminent` for the first and `.bordered` for the rest (`.controlSize(.small)`, help = button.help), or "Answer in Cat Office" link when `c.buttons` is empty.
  - `CatCard.sessionCard`: add `AnswerPanel(agent:)` above the "Last:" line and `JumpLinks(agent:)` at the bottom.
  - `OfficeCatList`: under a row whose agent is waiting with a prompt, the same `AnswerPanel` indented under the title (the list rows carry `OfficeRow`; pass the `OfficeAgent` by looking it up in `state.office?.agents` by key). Row click: `state.openInCatOffice(agent)`.
  - `ProjectsTabView`: first line, `if let line = state.todayRecap.line { Text(line).font(.caption).foregroundStyle(Theme.secondaryText) }`.
- [ ] **Step 5: Render seam and renders** — `CLAUDEBAR_RENDER_WAITING=<permission|question|plan>` (side effects off): in `officeUpdated`, the first office agent gets `status = .waiting` and a sample `pendingPrompt` of that kind. Render the Office tab for each kind (light + dark), the hover card via `--render-peek` with the pointer over that cat if it can be placed, and Projects with a sample `sessions-today.jsonl` (`CLAUDEBAR_RENDER_SESSIONS=<file>`). Read every PNG.
- [ ] **Step 6: Click test** `--test-answer` (side effects off, `CLAUDEBAR_RENDER_WAITING=permission`): the dropdown offscreen on Office; find the "Allow" button of the waiting row (record its frame with `.target("answer-allow", in: state.shortcutTargets)`), click it, then check `state.lastAnswerRequest` is the first agent's id with body `{"choice":"yes","kind":"permission"}` and the row shows "Sent". PASS/FAIL printed; exit code.
- [ ] **Step 7: Docs** — guide: hover card jump links, answering (Orca sessions; others show the question), recap; changes.html: `sessions-today.jsonl` in the `~/.claude/claude-bar/` row; README click tests: `--test-answer`.
- [ ] **Step 8:** `swift test`; `scripts/build.sh`; the click tests (`--test-tabs`, `--test-zoom`, `--test-setup`, `--test-undo`, `--test-shortcut`, `CLAUDEBAR_NO_DATA=1 --test-start`, `CLAUDEBAR_RENDER_WAITING=permission --test-answer`) — all pass.
- [ ] **Step 9: Commit** — `git commit -m "feat: jump to a session, answer a waiting one, and today's recap"`
