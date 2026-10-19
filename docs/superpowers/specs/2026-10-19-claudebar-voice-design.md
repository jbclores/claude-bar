# ClaudeBar Voice: Spoken Alerts, Talk to Answer, Status and Recap — Design

**Date:** 2026-10-19
**Status:** Approved in chat, awaiting spec review

## Goal

ClaudeBar can talk and listen: it says out loud when a cat needs you or finishes, and you can hold a key to answer a
waiting session, ask what's running or how usage looks, or hear today's recap. Everything runs on the Mac.

**Success criteria**

- With **Speak alerts** on, a cat needing you or finishing plays its meow or purr, then a voice says
  "claude-bar needs you." / "claude-bar finished." (with **Say what it asks**: what it asks or what it finished).
- Holding ⌃⌥V and saying "allow", then "yes" when asked, allows the waiting permission through Cat Office; nothing is
  sent before the "yes".
- "What's running", "how's my usage" and "what did I do today" get a spoken answer.
- No audio or text leaves the Mac; tests never use the real microphone, real speech, or the real Cat Office.

## 1. Spoken alerts

- **When:** the same events as the sounds: a cat starts needing you (`.needsYou`), a cat finishes (`.finished`). The
  voice starts once the meow or purr has finished playing (if no sound plays — its switch off, or the 3 s sound
  spacing — the voice speaks at once).
- **Short sentences (default):** "<name> needs you." / "<name> finished." `<name>` is the name the session list
  shows for that session.
- **With "Say what it asks" on:**
  - permission: "<name> asks: allow <command>?" — the command cut to its first 6 words (Bash), or "allow an edit to
    <file name>?" for Edit/Write, or "allow <tool>?" otherwise;
  - question: "<name> asks: <first question's text>" (cut to 20 words);
  - plan: "<name> has a plan for you.";
  - finished: "<name> finished: <first line of the task>" (cut to 12 words); no task → the short sentence.
- **Rules:**
  - Silent during quiet hours and when the **Cat sounds** switch is off (same gate as the sounds).
  - The same alert for the same cat is not spoken again within 60 s (the sounds' rule).
  - Several at once are queued and spoken in order, at most 3; then "and <n> more."
  - Not spoken while ⌃⌥V is held or a voice conversation is speaking; queued until it ends.
- **Voice:** the Mac's default system voice and rate (`AVSpeechSynthesizer`, `AVSpeechSynthesisVoice` default).
- **Settings → Alerts:** **Speak alerts** (off at first) and, under it, **Say what it asks** (off at first).

## 2. Talking to ClaudeBar (push to talk)

- **The key:** a second global shortcut, default ⌃⌥V, set in Settings → General like the open shortcut (the same
  `ShortcutField`), registered through the existing Carbon hot key code, which also handles key release
  (`kEventHotKeyReleased`). A press under 0.3 s does nothing. Listening stops on release or after 15 s.
- **Feedback:** a short tick when listening starts; the menu bar cat shows a small listening mark while it listens.
- **Recognition:** `SFSpeechRecognizer` (the Mac's dictation language, English), `requiresOnDeviceRecognition =
  true`; the waiting sessions' names and option labels are passed as `contextualStrings`. The final transcript goes
  to `VoiceCommand`.
- **Commands** (matched loosely: lowercase, punctuation dropped, number words read as numbers, a few phrasings each):

  | Said | Command |
  |---|---|
  | "allow", "yes allow", "allow it" | allow |
  | "always allow" | always allow |
  | "deny", "no", "don't allow" | deny |
  | "approve", "approve the plan" | approve |
  | "reject", "reject the plan" | reject |
  | "option two", "number two", "the second one", or an option's label | pick option n |
  | "yes", "yeah", "confirm" | yes (only while a confirm is pending) |
  | "cancel", "never mind" | cancel |
  | "what's running", "status" | status |
  | "how's my usage", "usage" | usage |
  | "what did I do today", "recap" | recap |
  | a waiting session's name (alone, or after a command: "allow claude-bar") | target |

  Names match loosely: dashes and spaces ignored, "pnp ufdms" matches `pnp-ufdms-base-admin`, a unique prefix
  matches. Nothing recognised → "Sorry, I didn't catch that."
- **The conversation** (`VoiceConversation`):
  - An answer command with one waiting session (answerable: an external session with a pending prompt that fits the
    command) targets it; with several and no name → "Two are waiting: claude-bar and pnp-ufdms. Which one?"
    (three or more: "Three are waiting: a, b and c. Which one?"), and the next utterance's name picks it.
  - allow, always allow, approve, pick option → a confirm: "Allow npm run build for claude-bar? Say yes." /
    "Always allow npm run build for claude-bar? Say yes." / "Approve claude-bar's plan? Say yes." /
    "Answer '<option label>' for claude-bar? Say yes." The next "yes" sends it and says "Allowed." / "Always
    allowed." / "Approved." / "Answered."
  - deny, reject → sent at once: "Denied for claude-bar." / "Rejected claude-bar's plan."
  - A pending "which one?" or "say yes" expires after 20 s; any other utterance in the meantime cancels it and is
    handled as new. "cancel" → "Okay."
  - A command that doesn't fit what is waiting ("approve" with only a permission waiting) → "claude-bar is asking
    for permission, not a plan."
  - Nothing waiting → "Nothing is waiting."
- **Sending:** through the existing answer path (`AppState.answer(agent, button, prompt:)`: Cat Office `/answer`,
  the bridge token, and the `expect` check). Its failures are spoken in plain words: the prompt changed → "That
  question changed; check it again."; 409 → "Cat Office can't answer this one; answer it in its terminal.";
  unreachable → "Cat Office isn't reachable."
- **Status:** "<n> running, <m> need you: <names>. <others> idle." (only the parts that apply; nothing live →
  "Nothing is running.")
- **Usage:** "5-hour at 40%, <forecast line in words>. 7-day at 12%." (no reading → "I don't have your usage yet.")
- **Recap:** today's recap line in words ("4 sessions finished, 2 hours 10 minutes working, busiest: claude-bar.");
  nothing today → "Nothing yet today."
- **Problems, spoken and shown in Settings:** microphone denied → "I need microphone access; I've opened Settings."
  (opens Privacy → Microphone); speech recognition denied → the same for Speech Recognition; on-device recognition
  unavailable → "Turn on dictation in System Settings to talk to ClaudeBar."
- **Settings → General:** **Talk to ClaudeBar** (off at first) and its shortcut field. Turning it on asks for
  microphone and speech recognition permission (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`
  in Info.plist).
- Quiet hours do not block talking: you started it, so its answers are spoken.

## 3. Stable signing

- `scripts/make-signing-cert.sh`: creates a self-signed code-signing certificate "ClaudeBar Local" in the login
  keychain, once. Run by the user, never by tests.
- `scripts/build.sh`: signs with "ClaudeBar Local" when it exists, else ad hoc as today. With it, macOS keeps the
  microphone and speech recognition permissions across reinstalls.
- README: one line on the script.

## Units

| Unit | Where | Role |
|---|---|---|
| `SpokenAlert` | Core | Event + prompt + settings → the sentence |
| `VoiceCommand` | Core | Transcript + waiting sessions → command (with target) or nothing |
| `VoiceConversation` | Core | State (pending pick / confirm, expiry) + command → what to say and what to send |
| `VoiceStatus` | Core | Status, usage and recap sentences |
| `Speaker` | App | AVSpeechSynthesizer queue, after the sound, cap 3 |
| `Listener` | App | Microphone + on-device recognition while the key is held; permissions |
| `HotKeyCenter` | App | A second hot key, with press and release |
| Settings | App | Speak alerts, Say what it asks, Talk to ClaudeBar + shortcut |

## Testing

- **Core:** each alert sentence (short, detailed, each prompt kind, long command and task cut); matching (each
  command in several phrasings, number words, option labels, dashed project names, a unique prefix, noise → nothing);
  the conversation (one waiting, several → which one, confirm then yes, deny at once, expiry, cancel, a command that
  doesn't fit, nothing waiting); the status, usage and recap sentences.
- **Click test `--test-voice`:** recognition and speech replaced by fakes; with a fake Cat Office (local, never the
  real one) and a waiting permission: feed "allow" → nothing sent and the confirm sentence spoken; feed "yes" → the
  permission `yes` answer sent; feed "deny" for a second prompt → sent at once.
- All existing tests and click tests pass.

## Out of scope

- Dictating new prompts to sessions; a voice picker; languages other than English; a wake word or always listening;
  a scheduled recap.
