import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct ClaudeBarRemovalTests {
    /// A temp home with all four folders, plus things that must stay.
    func home() -> URL {
        let h = makeTempDir()
        for f in [".config/claude-bar/projects.json", ".claude/claude-bar/sessions/a.json", "Library/Caches/ClaudeBar/art/x.png",
                  "Library/Logs/ClaudeBar/cat-office.log", ".claude/settings.json", ".claude/statusline-command.sh",
                  ".claude/claude-bar-statusline.sh", ".config/other/keep.json", "Library/Caches/Other/keep"] {
            write("x", to: h.appendingPathComponent(f))
        }
        return h
    }

    /// Moves into a temp "Trash" instead of the real one.
    func fakeTrash() -> (URL, @Sendable (URL) throws -> Void) {
        let bin = makeTempDir()
        return (bin, { url in try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(UUID().uuidString)) })
    }

    func exists(_ h: URL, _ p: String) -> Bool { FileManager.default.fileExists(atPath: h.appendingPathComponent(p).path) }

    @Test func movesExactlyClaudeBarsFourFolders() {
        let h = home(); let (_, trash) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: trash).remove()
        #expect(result.failures.isEmpty)
        #expect(result.trashed.count == 4)
        for p in [".config/claude-bar", ".claude/claude-bar", "Library/Caches/ClaudeBar", "Library/Logs/ClaudeBar"] { #expect(!exists(h, p)) }
        // Claude Code's status line keeps working, and nothing else is touched.
        for p in [".claude/settings.json", ".claude/statusline-command.sh", ".claude/claude-bar-statusline.sh",
                  ".config/other/keep.json", "Library/Caches/Other/keep"] { #expect(exists(h, p)) }
    }

    @Test func skipsMissingFolders() {
        let h = makeTempDir(); write("x", to: h.appendingPathComponent(".config/claude-bar/projects.json"))
        let (_, trash) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: trash).remove()
        #expect(result.trashed.map { $0.standardizedFileURL.path } == [h.appendingPathComponent(".config/claude-bar", isDirectory: true).standardizedFileURL.path])
        #expect(result.failures.isEmpty)
    }

    @Test func oneFailureDoesNotStopTheOthers() {
        let h = home(); let (bin, _) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: { url in
            if url.lastPathComponent == "Logs" || url.path.hasSuffix("Logs/ClaudeBar") { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(UUID().uuidString))
        }).remove()
        #expect(result.trashed.count == 3)
        #expect(result.failures.count == 1 && result.failures[0].contains("Library/Logs/ClaudeBar"))
        #expect(exists(h, "Library/Logs/ClaudeBar"))
    }
}
