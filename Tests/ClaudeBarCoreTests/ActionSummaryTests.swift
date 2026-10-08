import Testing
@testable import ClaudeBarCore

@Suite struct ActionSummaryTests {
    func calm(_ label: String, working: Bool = false) -> String { ActionSummary.calm(label, working: working) }

    @Test func commandsShowOnlyTheProgram() {
        #expect(calm("Bash: echo '- [Preferred name](preferred-name.md) — call the user \"Msys\"'") == "Ran a command · echo")
        #expect(calm("Bash: cd ~/Documents/projects/claude-bar && grep -n 'enum DropdownTab' -A3", working: true)
                == "Running a command · grep")
        #expect(calm("Bash: cd ~/Documents/projects/turborepo-lab/apps/web && npm run build") == "Ran a command · npm")
        #expect(calm("Bash: FOO=1 BAR=2 /usr/bin/git status") == "Ran a command · git")
        #expect(calm("Bash: sudo launchctl list") == "Ran a command · launchctl")
        #expect(calm("Bash: cd ~/somewhere") == "Ran a command")
        #expect(calm("Bash: …") == "Ran a command")
        #expect(calm("Bash: (cd x; make test)") == "Ran a command · make")
    }

    @Test func filesShowOnlyTheirName() {
        #expect(calm("Read Documents/projects/cat-ai-office-with-art/README.md") == "Read a file · README.md")
        #expect(calm("Read src/a.ts", working: true) == "Reading a file · a.ts")
        #expect(calm("Edit Documents/project-docs/pnp-ufdms-base-admin/tasks/task-doc.md") == "Edited task-doc.md")
        #expect(calm("Edit x/y.swift", working: true) == "Editing y.swift")
        #expect(calm("Write /tmp/out.json") == "Wrote out.json")
        #expect(calm("NotebookEdit nb/analysis.ipynb") == "Edited analysis.ipynb")
        #expect(calm("Read") == "Read a file")
    }

    @Test func searchesAndOtherToolsHideTheirInput() {
        #expect(calm("Grep \"api_key=sk-123\"") == "Searched the code")
        #expect(calm("Grep: walkFrame", working: true) == "Searching the code")
        #expect(calm("Glob src/**/*.ts") == "Looked for files")
        #expect(calm("WebSearch \"my private question\"") == "Searched the web")
        #expect(calm("WebFetch https://github.com/org/repo/pull/12?token=abc") == "Opened a web page · github.com")
        #expect(calm("Agent: review the payment code", working: true) == "Starting a helper")
        #expect(calm("Skill: superpowers:brainstorming") == "Used a skill · superpowers:brainstorming")
        #expect(calm("SendMessage → a7845f") == "Sent a message")
        #expect(calm("claude_ai_Slack · send_message") == "Used a tool · claude_ai_Slack")
        #expect(calm("Asked a question") == "Asked a question")
        #expect(calm("Proposed a plan") == "Proposed a plan")
        #expect(calm("TodoWrite") == "TodoWrite")
        #expect(calm("") == "")
    }
}
