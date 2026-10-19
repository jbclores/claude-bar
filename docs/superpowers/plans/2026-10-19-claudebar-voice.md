# ClaudeBar Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ClaudeBar speaks alerts (after the meow/purr) and listens while ⌃⌥V is held to answer waiting sessions (with a spoken "yes" to confirm), tell status and usage, and read today's recap.

**Architecture:** All decisions live in `ClaudeBarCore` as pure, tested types: settings (`VoiceSettings`), the alert sentences (`SpokenAlert`), transcript → command (`VoiceCommand`), the back-and-forth (`VoiceConversation`) and the status/usage/recap sentences (`VoiceStatus`). The app target adds thin AppKit/AVFoundation/Speech pieces behind two protocols (`SpeechOutput`, `SpeechInput`) and a `VoiceController` that wires them to `AppState`'s existing answer path. A `--test-voice` click test drives the controller with fake speech in and out.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, Swift Testing, SwiftUI + AppKit, AVFoundation (`AVSpeechSynthesizer`, `AVAudioEngine`), Speech (`SFSpeechRecognizer`), Carbon hot keys. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-19-claudebar-voice-design.md`

## Global Constraints

- Nothing leaves the Mac: `SFSpeechRecognitionRequest.requiresOnDeviceRecognition = true`; no network calls added.
- Everything is off at first: `speakAlerts = false`, `sayDetails = false`, `talk = false`; talk shortcut default `ctrl+opt+V`.
- Spoken alerts obey quiet hours and the **Cat sounds** switch (`settings.sounds.on`); talking ignores quiet hours.
- Answers only through `AppState.answer(_:_:prompt:)` (Cat Office `/answer`, bridge token, `expect`). allow, always allow, approve, pick option need a spoken "yes"; deny and reject go at once.
- Tests never use the real microphone, real speech, the real Cat Office, the installed app, `~/.claude`, `~/.config/claude-bar` or `~/.cat-office`.
- Copy is sentence case, plain words, as in the spec's tables; exact sentences below are verbatim.
- Run the app's click tests with a time limit: `(cmd & pid=$!; for i in $(seq 1 60); do kill -0 $pid 2>/dev/null || break; sleep 1; done; kill $pid 2>/dev/null)`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

- A transcript holding both a command and noise ("uh allow it please") → still allow; "yes allow" is allow, not a bare yes. Pinned in Task 3.
- "no" while a confirm is pending → deny is NOT sent for the pending target; it cancels the confirm ("Okay."). A spoken "no" must never turn a pending allow into a deny someone didn't ask for. Pinned in Task 4.
- The prompt changes between the confirm sentence and "yes" → nothing sent, "That question changed; check it again." Pinned in Task 4 (conversation keeps the prompt it confirmed) and Task 8 (click test).
- A waiting session that Cat Office can't answer (not `canBeAnswered`, or a multi-question prompt with no buttons) is never a voice target; "allow" with only such sessions → "Answer that one in Cat Office." Pinned in Task 4.
- Several alerts at once while the listener is open → queued, not spoken over the conversation, capped at 3 + "and N more." Pinned in Task 2 (cap) and Task 6 (hold while listening).

---

### Task 1: Voice settings in the config

**Files:**
- Modify: `Sources/ClaudeBarCore/Config.swift` (the `Config` struct and its JSON parse, next to `sounds`)
- Test: `Tests/ClaudeBarCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Produces: `public struct VoiceSettings: Equatable, Sendable { var speakAlerts = false; var sayDetails = false; var talk = false; var talkShortcut: Shortcut? = .talkStandard }`, `Shortcut.talkStandard = Shortcut(string: "ctrl+opt+V")!`, `Config.voice: VoiceSettings`. JSON: `"voice": {"speakAlerts": Bool, "sayDetails": Bool, "talk": Bool, "shortcut": "ctrl+opt+V" | ""}` (`""` → nil, unparsable → `.talkStandard`), same rules as the top-level `shortcut`.

- [ ] **Step 1: Write the failing tests** `voiceSettingsDefaultOff` (empty config → all false, shortcut `ctrl+opt+V`), `voiceSettingsParse` (`{"voice":{"speakAlerts":true,"sayDetails":true,"talk":true,"shortcut":"ctrl+opt+K"}}` → all true, shortcut string `ctrl+opt+K`; `"shortcut":""` → nil; `"shortcut":"nonsense"` → `ctrl+opt+V`).
- [ ] **Step 2: Run** `swift test --filter ConfigStoreTests` — Expected: FAIL (no `voice`).
- [ ] **Step 3: Implement** `VoiceSettings`, `Shortcut.talkStandard`, `Config.voice` and its parse.
- [ ] **Step 4: Run** `swift test --filter ConfigStoreTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(voice): voice settings in the config`.

### Task 2: Alert sentences

**Files:**
- Create: `Sources/ClaudeBarCore/SpokenAlert.swift`
- Test: `Tests/ClaudeBarCoreTests/SpokenAlertTests.swift`

**Interfaces:**
- Produces:
  - `SpokenAlert.needsYou(name: String, prompt: PendingPrompt?, details: Bool) -> String`
  - `SpokenAlert.finished(name: String, task: String?, details: Bool) -> String`
  - `SpokenAlert.capped(_ sentences: [String], max: Int = 3) -> [String]`
  - `SpokenAlert.words(_ text: String, max: Int) -> String` (first `max` words of the first non-empty line; no "…")

- [ ] **Step 1: Write the failing tests** (`@Suite struct SpokenAlertTests`):
  - `short`: `needsYou(name: "claude-bar", prompt: .permission(tool: "Bash", input: "npm test"), details: false) == "claude-bar needs you."`; `finished(name: "claude-bar", task: "Fix it", details: false) == "claude-bar finished."`
  - `permissionBash`: details on, input `"npm run build && npm test -- --watch=false --reporter=dot"` → `"claude-bar asks: allow npm run build && npm test?"` (6 words)
  - `permissionEdit`: tool `"Edit"`, input `"/Users/x/app/Sources/Login.swift"` → `"claude-bar asks: allow an edit to Login.swift?"`; tool `"WebFetch"`, input `"https://x"` → `"claude-bar asks: allow WebFetch?"`
  - `question`: one question `"Which database should I use?"` → `"claude-bar asks: Which database should I use?"`; a 30-word question is cut to 20 words then `?`
  - `plan`: → `"claude-bar has a plan for you."`
  - `finishedDetails`: task `"Fix the login bug\nmore"` → `"claude-bar finished: Fix the login bug."`; task nil or blank → `"claude-bar finished."`; a 20-word first line → 12 words then `.`
  - `noPromptDetails`: `needsYou(name:"a", prompt: nil, details: true) == "a needs you."`
  - `cap`: 5 sentences → first 3 + `"and 2 more."`; 3 → unchanged; `capped(["x","y","z","w"]).last == "and 1 more."`
- [ ] **Step 2: Run** `swift test --filter SpokenAlertTests` — Expected: FAIL (no `SpokenAlert`).
- [ ] **Step 3: Implement** `SpokenAlert` (an `enum` of static functions). A sentence that already ends in `?`/`.` gets no second one.
- [ ] **Step 4: Run** `swift test --filter SpokenAlertTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(voice): alert sentences`.

### Task 3: Transcript → command

**Files:**
- Create: `Sources/ClaudeBarCore/VoiceCommand.swift`
- Test: `Tests/ClaudeBarCoreTests/VoiceCommandTests.swift`

**Interfaces:**
- Produces:
  - `public struct VoiceTarget: Equatable, Sendable { public var id: String; public var name: String; public var options: [String] }`
  - `public enum VoiceIntent: Equatable, Sendable { case allow, alwaysAllow, deny, approve, reject, option(Int) /* 0-based */, yes, cancel, status, usage, recap, name, none }`
  - `public struct VoiceCommand: Equatable, Sendable { public var intent: VoiceIntent; public var target: String? /* VoiceTarget.id */ }`
  - `VoiceCommand.parse(_ transcript: String, targets: [VoiceTarget]) -> VoiceCommand`
  - `VoiceCommand.normalized(_ s: String) -> String` (lowercase, punctuation and dashes → spaces, single spaces)

Matching order (first hit wins): always allow → deny ("deny", "don't allow", "do not allow", a lone "no") → allow → approve → reject → option → yes → cancel → status → usage → recap → name only → none. A target name anywhere in the transcript sets `target`; a name with no other command gives `.name`.
Name match: normalized name with spaces removed equals, or is prefixed by (unique prefix of at least 3 letters), a run of the transcript's words joined without spaces. Option: "option N", "number N", "the first/second/third/fourth one", "one/two/…/four" alone, or an option label contained in the transcript (labels of all targets; first match). Number words one–nine and ordinals first–ninth.

- [ ] **Step 1: Write the failing tests** (`@Suite struct VoiceCommandTests`, targets `[VoiceTarget(id: "a1", name: "claude-bar", options: []), VoiceTarget(id: "b2", name: "pnp-ufdms-base-admin", options: ["PostgreSQL", "SQLite"])]`):
  - `allowPhrasings`: "Allow", "yes allow", "allow it", "uh allow it please" → `.allow`, target nil
  - `alwaysAllow`: "always allow" → `.alwaysAllow`
  - `denyPhrasings`: "deny", "no", "don't allow", "Do not allow." → `.deny`
  - `planWords`: "approve the plan" → `.approve`; "reject" → `.reject`
  - `options`: "option two" → `.option(1)`; "the first one" → `.option(0)`; "number 3" → `.option(2)`; "SQLite please" → `.option(1)`
  - `confirmAndCancel`: "yes" / "yeah" / "confirm" → `.yes`; "never mind" / "cancel" → `.cancel`
  - `questions`: "what's running" / "status" → `.status`; "how's my usage" → `.usage`; "what did I do today" / "recap" → `.recap`
  - `names`: "allow claude bar" → `.allow`, target "a1"; "pnp ufdms" → `.name`, target "b2"; "claude" → `.name`, "a1" (unique prefix); "deny p" → `.deny`, target nil (prefix too short)
  - `noise`: "the weather is nice" → `.none`; "" → `.none`
- [ ] **Step 2: Run** `swift test --filter VoiceCommandTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `VoiceCommand.parse` as above.
- [ ] **Step 4: Run** `swift test --filter VoiceCommandTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(voice): match what was said to a command`.

### Task 4: The conversation

**Files:**
- Create: `Sources/ClaudeBarCore/VoiceConversation.swift`
- Test: `Tests/ClaudeBarCoreTests/VoiceConversationTests.swift`

**Interfaces:**
- Consumes: `VoiceCommand`, `VoiceIntent` (Task 3), `AnswerChoices.of(_:)` and its `buttons` order (permission: Allow, Always allow, Deny; question: one per option; plan: Approve, Reject).
- Produces:
  - `public struct VoiceWaiting: Equatable, Sendable { public var id: String; public var name: String; public var prompt: PendingPrompt }` — only sessions Cat Office can answer (the app builds it from `canBeAnswered` agents with `status == .waiting` and a `pendingPrompt`).
  - `public enum VoiceReply: Equatable, Sendable { case say(String); case send(agentId: String, prompt: PendingPrompt, button: Int, then: String); case status, usage, recap }` — `button` indexes `AnswerChoices.of(prompt).buttons`; `then` is spoken once Cat Office takes it.
  - `public struct VoiceConversation: Sendable { public init(); public static let expiry: TimeInterval = 20; public mutating func handle(_ command: VoiceCommand, waiting: [VoiceWaiting], now: Date) -> VoiceReply }`

Behaviour (exact sentences):
- Pending state is `.pick(intent, candidates, at)` or `.confirm(agentId, prompt, button, then, at)`; older than `expiry` → dropped before handling.
- `.confirm` pending: `.yes` → `.send(...)` with the stored prompt, state cleared. `.cancel` or a lone deny "no" → `say("Okay.")`, cleared (nothing sent). Anything else → cleared and handled as new.
- `.pick` pending: `.name` (or any intent with a target among the candidates) → continue the stored intent on that target. Else cleared and handled as new.
- Answer intents: candidates = waiting whose prompt fits (allow/alwaysAllow/deny → `.permission`; approve/reject → `.plan`; option → `.question` with buttons and index in range). A command target narrows to it.
  - none waiting at all → `say("Nothing is waiting.")`
  - waiting but none fits → `say("<first waiting name> is asking <has>, not <wants>.")`; has: permission "for permission", question "a question", plan "you to approve a plan"; wants: allow/alwaysAllow/deny "permission", approve/reject "a plan", option "a question". Example: `"claude-bar is asking for permission, not a plan."`
  - a waiting prompt with no buttons (several questions or multi-select) never fits; if it is the only waiting one → `say("Answer that one in Cat Office.")`
  - two or more fit, no target → `say("Two are waiting: claude-bar and pnp-ufdms. Which one?")` (number word up to nine, names joined "a, b and c"), state `.pick`
  - one fits → deny: `.send(button: 2, then: "Denied for <name>.")`; reject: `.send(button: 1, then: "Rejected <name>'s plan.")`; allow: confirm `"Allow <SpokenAlert.words(input, max: 6)> for <name>? Say yes."` then "Allowed."; alwaysAllow: `"Always allow <cmd> for <name>? Say yes."` then "Always allowed."; approve: `"Approve <name>'s plan? Say yes."` then "Approved."; option i: `"Answer '<label>' for <name>? Say yes."` then "Answered." — non-Bash permissions use `allow an edit to <file>` / `allow <tool>` wording from Task 2 in place of `<cmd>`.
- `.status`/`.usage`/`.recap` → those replies (state cleared). `.yes` with nothing pending → `say("Nothing to confirm.")`. `.none` or a lone `.name` with nothing pending → `say("Sorry, I didn't catch that.")`.

- [ ] **Step 1: Write the failing tests** (`@Suite struct VoiceConversationTests`; fixtures: `perm = VoiceWaiting(id: "a1", name: "claude-bar", prompt: .permission(tool: "Bash", input: "npm run build"))`, `perm2` id "b2" name "pnp-ufdms", `plan` id "c3" name "turborepo-lab" prompt `.plan("# Ship it")`):
  - `allowOneWaitingConfirmsThenSends`: allow → `.say("Allow npm run build for claude-bar? Say yes.")`; then yes → `.send(agentId: "a1", prompt: perm.prompt, button: 0, then: "Allowed.")`
  - `denyGoesAtOnce`: deny → `.send(agentId: "a1", prompt: perm.prompt, button: 2, then: "Denied for claude-bar.")`
  - `severalWaitingAsksWhichOne`: allow with [perm, perm2] → `.say("Two are waiting: claude-bar and pnp-ufdms. Which one?")`; then `.name` target "b2" → `.say("Allow npm run build for pnp-ufdms? Say yes.")`; yes → send to "b2"
  - `noDuringConfirmCancels`: allow, then `.deny` (from "no") → `.say("Okay.")`; then yes → `.say("Nothing to confirm.")`
  - `confirmExpires`: allow at t, yes at t+21 → `.say("Nothing to confirm.")`
  - `confirmKeepsItsPrompt`: allow, then yes with `waiting` now holding a different prompt for "a1" → the send carries the ORIGINAL prompt (the app's `answer` then refuses it as changed)
  - `wrongKind`: approve with [perm] → `.say("claude-bar is asking for permission, not a plan.")`
  - `noButtons`: allow with only a two-question prompt → `.say("Answer that one in Cat Office.")`
  - `nothingWaiting`: allow with [] → `.say("Nothing is waiting.")`
  - `planAndOption`: approve with [plan] → `.say("Approve turborepo-lab's plan? Say yes.")`; reject → `.send(..., button: 1, then: "Rejected turborepo-lab's plan.")`; option(1) on a one-question prompt with options ["PostgreSQL","SQLite"] → `.say("Answer 'SQLite' for <name>? Say yes.")`
  - `infoAndNoise`: status → `.status`; usage → `.usage`; recap → `.recap`; none → `.say("Sorry, I didn't catch that.")`
- [ ] **Step 2: Run** `swift test --filter VoiceConversationTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `VoiceConversation` as specified.
- [ ] **Step 4: Run** `swift test --filter VoiceConversationTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(voice): the voice conversation (which one, say yes, expiry)`.

### Task 5: Status, usage and recap sentences

**Files:**
- Create: `Sources/ClaudeBarCore/VoiceStatus.swift`
- Test: `Tests/ClaudeBarCoreTests/VoiceStatusTests.swift`

**Interfaces:**
- Consumes: `UsageSummary`, `UsageForecast.line(time:)`, `TodayRecap`.
- Produces:
  - `VoiceStatus.status(running: [String], needYou: [String], idle: [String]) -> String`
  - `VoiceStatus.usage(_ u: UsageSummary, forecast: UsageForecast?, time: (Date) -> String) -> String`
  - `VoiceStatus.recap(_ r: TodayRecap) -> String`
  - `VoiceStatus.failure(_ message: String) -> String` (AnswerState failure text spoken: `": "` → `"; "`, ends in `.`)

- [ ] **Step 1: Write the failing tests**:
  - `status`: running ["claude-bar","x"], needYou ["claude-bar"], idle ["pnp-ufdms"] → `"2 running, 1 needs you: claude-bar. pnp-ufdms idle."`; needYou 2 → `"… 2 need you: a and b. …"`; idle of 4+ names → `"4 others idle."`; all empty → `"Nothing is running."`; only idle ["a"] → `"a idle."`
  - `usage`: 5h 40, 7d 12, forecast whose `line` is "On pace for about 70% of the 5-hour limit by 6:00 PM" → `"5-hour at 40%, on pace for about 70% of the 5-hour limit by 6:00 PM. 7-day at 12%."`; no forecast → `"5-hour at 40%. 7-day at 12%."`; no 5h reading → `"I don't have your usage yet."`
  - `recap`: finished 4, working 2h10m, busiest "claude-bar" → `"4 sessions finished, 2 hours 10 minutes working, busiest: claude-bar."`; 1 finished, 45 min, no busiest → `"1 session finished, 45 minutes working."`; nothing → `"Nothing yet today."`
  - `failure`: `"That question changed: check it again"` → `"That question changed; check it again."`; `"Couldn't reach Cat Office"` → `"Couldn't reach Cat Office."`
  - Ruling (spec §2 "Sending"): failures are spoken from the existing `AnswerChoices` messages (same meaning, ClaudeBar's existing words: "Cat Office can't answer this session; answer it in its terminal.", "Couldn't reach Cat Office.") rather than new copies — one source of truth for answer errors.
- [ ] **Step 2: Run** `swift test --filter VoiceStatusTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `VoiceStatus`.
- [ ] **Step 4: Run** `swift test --filter VoiceStatusTests` — Expected: PASS; then `swift test` — Expected: all pass.
- [ ] **Step 5: Commit** `feat(voice): status, usage and recap sentences`.

### Task 6: Speaker and spoken alerts in the app

**Files:**
- Create: `Sources/ClaudeBar/Voice/Speech.swift` (`SpeechOutput` protocol, `SystemSpeaker`)
- Create: `Sources/ClaudeBar/Voice/VoiceController.swift` (alerts part)
- Modify: `Sources/ClaudeBar/AppState.swift` (`officeUpdated` finish/needs-you loop at ~580–593; settings setters), `Sources/ClaudeBar/Views/DropdownView.swift` (Settings → Alerts)

**Interfaces:**
- Consumes: `SpokenAlert` (Task 2), `VoiceSettings` (Task 1).
- Produces:
  - `@MainActor protocol SpeechOutput: AnyObject { func speak(_ text: String, done: @escaping () -> Void); func stop() }`; `SystemSpeaker: SpeechOutput` on `AVSpeechSynthesizer` with `AVSpeechUtterance(string:)` default voice and rate (no voice set).
  - `@MainActor final class VoiceController: ObservableObject { init(state: AppState, speaker: SpeechOutput); func alert(_ sentence: String, afterSound: Bool); var holding: Bool }` — queue; `afterSound` delays the first sentence by 1.2 s; while `holding` (key held or a conversation reply speaking) alerts wait in the queue; when the queue is flushed, `SpokenAlert.capped`.
  - `AppState.voice: VoiceController!` created in `init`/`start`; `AppState.setVoice(_ key: String, _ on: Bool)` writes `["voice", key]` (Bool keys) like `setSound`.
- Wiring: for each finished event (not quiet, `settings.sounds.on`, `settings.voice.speakAlerts`) → `voice.alert(SpokenAlert.finished(name: event.name, task: event.task, details: sayDetails), afterSound: sound != nil)`. For each `startedWaiting` key → find the agent by `key`, name `agent.label`, prompt `agent.pendingPrompt` → `voice.alert(SpokenAlert.needsYou(...), afterSound: <whether playSound played>)`. `playSound` returns `Bool` (played) for this. Repeats: the controller keeps its own `lastSpoken: [String: Date]` keyed `"needsYou|<key>"` / `"finished|<key>"` and speaks only when `SpokenAlert.shouldSpeak` says so (independent of the sound gate, so a skipped meow doesn't skip the voice).
- Settings → Alerts: toggle "Speak alerts" (`speakAlerts`), and indented under it, shown only when on, "Say what it asks" (`sayDetails`).

- [ ] **Step 1: Write the failing test** `repeatWindow` in `SpokenAlertTests`: `SpokenAlert.shouldSpeak(key: "needsYou|a", last: ["needsYou|a": t], now: t + 30) == false`; at `t + 61` true; an unknown key true. (New Core function `SpokenAlert.shouldSpeak(key: String, last: [String: Date], now: Date) -> Bool`, 60 s.)
- [ ] **Step 2: Run** `swift test --filter SpokenAlertTests` — Expected: FAIL (no `shouldSpeak`).
- [ ] **Step 3: Implement** `shouldSpeak`, `Speech.swift`, the alerts part of `VoiceController`, the AppState wiring and the two Settings toggles. Renders (side effects off) never speak: `VoiceController.alert` returns early when `!state.sideEffects`.
- [ ] **Step 4: Run** `swift test` — Expected: all pass. `scripts/build.sh` — Expected: "Built build/ClaudeBar.app". Render `CLAUDEBAR_SETTINGS_OPEN=1 … --render-dropdown /tmp/voice/settings.png settings` and look: the two toggles under Alerts, "Say what it asks" only while "Speak alerts" is on (render both with a temp config is not possible — check the off state and read the view code for the on state).
- [ ] **Step 5: Commit** `feat(voice): spoken alerts after the meow or purr`.

### Task 7: Push to talk: second hot key, listener, permissions

**Files:**
- Modify: `Sources/ClaudeBar/HotKeyCenter.swift`, `Sources/ClaudeBar/StatusItemController.swift`, `Resources/Info.plist`, `Sources/ClaudeBar/Views/DropdownView.swift` (Settings → General), `Sources/ClaudeBar/Views/UsageHistoryViews.swift` (`ShortcutField` reuse)
- Create: `Sources/ClaudeBar/Voice/Listener.swift` (`SpeechInput`, `SystemListener`)

**Interfaces:**
- Produces:
  - `HotKeyCenter.register(_ shortcut: Shortcut?, slot: HotKeySlot) -> Bool` with `enum HotKeySlot: UInt32 { case open = 1, talk = 2 }`, and `onPress: [HotKeySlot: () -> Void]`, `onRelease: [HotKeySlot: () -> Void]`. The Carbon handler listens to `kEventHotKeyPressed` and `kEventHotKeyReleased` and reads the `EventHotKeyID` (`GetEventParameter(kEventParamDirectObject, typeEventHotKeyID)`) to pick the slot. Existing open-shortcut callers move to `slot: .open`.
  - `@MainActor protocol SpeechInput: AnyObject { func start(hints: [String]) throws; func finish(_ done: @escaping (String?) -> Void); func cancel() }` and `enum ListenProblem: Error { case microphoneDenied, speechDenied, notOnDevice }`.
  - `SystemListener: SpeechInput`: `AVAudioEngine` input tap → `SFSpeechAudioBufferRecognitionRequest` with `requiresOnDeviceRecognition = true`, `contextualStrings = hints`, `shouldReportPartialResults = false`; `start` throws `.notOnDevice` when `SFSpeechRecognizer()?.supportsOnDeviceRecognition != true`, `.microphoneDenied` / `.speechDenied` from `AVCaptureDevice.authorizationStatus(for: .audio)` / `SFSpeechRecognizer.authorizationStatus()` (requesting when `.notDetermined`).
  - `AppState.setTalkShortcut(_ shortcut: Shortcut?)` (like `setShortcut`, writes `["voice","shortcut"]`, `talkShortcutTaken` flag), `AppState.voiceListening: Bool` (@Published).
  - `VoiceController.keyDown()` / `keyUp()`: press → note time, play tick (`NSSound(named: "Tink")`), `holding = true`, `voiceListening = true`, `listener.start(hints: waiting names + option labels)`; 15 s timer → `keyUp()`; release under 0.3 s → `cancel()`, nothing else; else `finish { transcript in self.heard(transcript ?? "") }`. A `ListenProblem` → speak its sentence (spec §2 "Problems") and, for denied ones, open `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone` / `?Privacy_SpeechRecognition`; also published as `AppState.voiceProblem: String?` shown under the Settings toggle.
- Info.plist: `NSMicrophoneUsageDescription` = "Hold your talk shortcut to answer or ask ClaudeBar by voice.", `NSSpeechRecognitionUsageDescription` = "ClaudeBar turns what you say into a command on this Mac; nothing is sent anywhere."
- Settings → General: toggle "Talk to ClaudeBar" (`talk`), and when on a `ShortcutField` for the talk shortcut (same look as the open shortcut; "Taken by another app" line when taken) and the `voiceProblem` line. Turning it on registers `.talk`; off unregisters.
- Menu bar: while `voiceListening`, the status item shows a small `mic.fill` SF Symbol beside the cat (StatusItemController observes `state.$voiceListening`).

- [ ] **Step 1: Write the failing test** `Tests/ClaudeBarCoreTests/ComfortTests.swift` `talkStandardShortcut`: `Shortcut.talkStandard.display == "⌃⌥V"` and `keyCode == 9` (already true after Task 1 → it passes; that's fine, it pins the default). Then extend the existing `--test-shortcut` click test (RenderPeek `TestShortcut`) to also record into the talk shortcut box (target `"talk-shortcut-field"`) with `CLAUDEBAR_RENDER_TALK=1` and expect `state.recordedTalkShortcut?.string == "ctrl+opt+K"`; add `AppState.recordedTalkShortcut` (side effects off) mirroring `recordedShortcut`.
- [ ] **Step 2: Run** the shortcut click test with `CLAUDEBAR_RENDER_TALK=1` — Expected: FAIL (no talk box).
- [ ] **Step 3: Implement** the hot key slots, listener, permissions, settings, menu bar mark, Info.plist keys.
- [ ] **Step 4: Run** `swift test`, `scripts/build.sh`, `--test-shortcut` with and without `CLAUDEBAR_RENDER_TALK=1` — Expected: both PASS (`recorded ⌃⌥K`). `plutil -lint build/ClaudeBar.app/Contents/Info.plist` — Expected: OK.
- [ ] **Step 5: Commit** `feat(voice): hold a shortcut to talk (listener, permissions, settings)`.

### Task 8: Conversation in the app, and the `--test-voice` click test

**Files:**
- Modify: `Sources/ClaudeBar/Voice/VoiceController.swift`, `Sources/ClaudeBar/RenderPeek.swift` (add `TestVoice` to `runIfRequested`)

**Interfaces:**
- Consumes: `VoiceConversation`, `VoiceCommand`, `VoiceStatus`, `AppState.answer(_:_:prompt:)`, `AppState.answerState`, `AppState.todayRecap`, `UsageForecast.headline(history:now:)`, `AppState.usageTime(_:)`.
- Produces: `VoiceController.heard(_ transcript: String)` — builds `[VoiceWaiting]` (agents `canBeAnswered`, `status == .waiting`, with `pendingPrompt`, name `label`) and `[VoiceTarget]` (same, options = button titles for one-question prompts), parses, calls `conversation.handle`, then: `.say(s)` → speak; `.send` → look up the agent, `answer(agent, AnswerChoices.of(prompt).buttons[button], prompt: prompt)`, then watch `answerState[agentId]`: `.sent` → speak `then`; `.failed(m)` → speak `VoiceStatus.failure(m)`; `.status` → speak `VoiceStatus.status(...)` from office agents (running = working, needYou = attention, idle = idle; names `label`); `.usage` → `VoiceStatus.usage(output.usage, forecast: headline, time: AppState.usageTime)`; `.recap` → `VoiceStatus.recap(todayRecap)`. While a reply speaks, `holding` stays true; queued alerts flush after.
- `VoiceController.init(state:speaker:listener:)`; the test passes a `RecordingSpeaker` (collects sentences, calls `done` at once) and no real listener.
- `--test-voice` (env `CLAUDEBAR_RENDER_WAITING=permission CLAUDEBAR_RENDER_WAITING_EXTERNAL=1`, side effects off so answers land in `lastAnswerRequest`): wait for the waiting agent; `heard("allow")` → `lastAnswerRequest == nil` and the last sentence ends with "Say yes."; `heard("yes")` → `lastAnswerRequest` body has `"choice":"yes"`, last sentence "Allowed."; reset `answerState[id] = nil` and `lastAnswerRequest`; `heard("deny")` → body `"choice":"no"` at once, last sentence "Denied for <label>."; `heard("allow")`, then change the render prompt (`state.renderReplacePrompt(id, .permission(tool: "Bash", input: "something else"))`, render-only helper) and `heard("yes")` → no new request, last sentence "That question changed; check it again."; print `PASS: …` and exit 0, else `FAIL: <why>` exit 1.

- [ ] **Step 1: Write the click test** `TestVoice` in RenderPeek.swift as above (the `heard` API not yet existing).
- [ ] **Step 2: Run** `scripts/build.sh` — Expected: build FAILS (no `heard`) — the red step for an app-only path.
- [ ] **Step 3: Implement** `heard` and the reply handling; `keyUp` (Task 7) calls it.
- [ ] **Step 4: Run** `scripts/build.sh`, then `CLAUDEBAR_RENDER_WAITING=permission CLAUDEBAR_RENDER_WAITING_EXTERNAL=1 build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-voice` (time-limited) — Expected: a line starting `PASS:`. Then all seven existing click tests and `swift test` — Expected: all pass.
- [ ] **Step 5: Commit** `feat(voice): answer, status, usage and recap by voice (+ --test-voice)`.

### Task 9: Stable signing, docs

**Files:**
- Create: `scripts/make-signing-cert.sh`
- Modify: `scripts/build.sh` (line 25 `codesign --force --sign - "$APP"`), `README.md`, `Sources/ClaudeBar/Views/HelpPanel.swift`

**Interfaces:**
- `make-signing-cert.sh`: refuses if an identity named "ClaudeBar Local" exists; else `openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -subj "/CN=ClaudeBar Local" -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature"` into a temp dir, `openssl pkcs12 -export` (with `-legacy` when the openssl supports it), `security import <p12> -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -P <pw>`, then removes the temp dir. Prints what it did. Never run by tests or by the agent — the user runs it.
- `build.sh`: `if security find-identity -p codesigning 2>/dev/null | grep -q '"ClaudeBar Local"'; then codesign --force --sign "ClaudeBar Local" "$APP"; else codesign --force --sign - "$APP"; fi` (no `-v`: a self-signed identity isn't "valid" for `-v` but signs fine).
- README: a "Voice" section (Speak alerts, Say what it asks, Talk to ClaudeBar ⌃⌥V, what to say, on-device only, permissions) and one line: run `scripts/make-signing-cert.sh` once so macOS keeps the microphone permission across updates. Help panel: one row "Talk" — "Hold ⌃⌥V and say allow, deny, what's running, how's my usage, or what did I do today."

- [ ] **Step 1: Check** `bash -n scripts/make-signing-cert.sh scripts/build.sh` — Expected: no output.
- [ ] **Step 2: Run** `scripts/build.sh` — Expected: "Built build/ClaudeBar.app" (ad hoc, since no identity exists); `codesign -dv build/ClaudeBar.app 2>&1 | grep Signature` — Expected: `Signature=adhoc`.
- [ ] **Step 3: Render** `--render-help /tmp/voice/help.png` and look at the Talk row.
- [ ] **Step 4: Run** `swift test` and all eight click tests — Expected: all pass.
- [ ] **Step 5: Commit** `feat(voice): stable local signing script, README and help`.
