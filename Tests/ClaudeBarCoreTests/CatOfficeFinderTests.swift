import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct CatOfficeFinderTests {
    func makeCatOffice(_ dir: URL, modified: Date) throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("server/agent-bridge"), withIntermediateDirectories: true)
        let pkg = dir.appendingPathComponent("package.json")
        try Data("{}".utf8).write(to: pkg)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: pkg.path)
    }

    @Test func recognisesOnlyCatOffice() throws {
        let root = makeTempDir()
        try makeCatOffice(root.appendingPathComponent("co"), modified: Date())
        try FileManager.default.createDirectory(at: root.appendingPathComponent("web/server"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("web/package.json"))
        #expect(CatOfficeFinder.isCatOffice(root.appendingPathComponent("co").path))
        #expect(!CatOfficeFinder.isCatOffice(root.appendingPathComponent("web").path), "a package.json alone isn't Cat Office")
    }

    @Test func searchesTwoLevelsDeep() throws {
        let root = makeTempDir()
        try makeCatOffice(root.appendingPathComponent("a/cat-office"), modified: Date())
        try makeCatOffice(root.appendingPathComponent("a/b/c/too-deep"), modified: Date())
        let found = CatOfficeFinder.search(roots: [root.path])
        #expect(found.map { URL(fileURLWithPath: $0).lastPathComponent } == ["cat-office"])
    }

    @Test func eachCopyOnceNewestFirst() throws {
        let root = makeTempDir()
        let old = root.appendingPathComponent("old-zip"), new = root.appendingPathComponent("new-zip")
        try makeCatOffice(old, modified: Date(timeIntervalSince1970: 1_700_000_000))
        try makeCatOffice(new, modified: Date(timeIntervalSince1970: 1_790_000_000))
        try makeCatOffice(new.appendingPathComponent("examples/copy"), modified: Date())   // inside another: not searched
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: new)
        let c = CatOfficeFinder.candidates(running: nil, saved: nil, roots: [root.path])
        #expect(c.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["new-zip", "old-zip"])
    }

    @Test func runningThenSavedThenSearched() throws {
        let root = makeTempDir()
        let a = root.appendingPathComponent("x/a"), b = root.appendingPathComponent("x/b"), r = root.appendingPathComponent("elsewhere/r")
        try makeCatOffice(a, modified: Date(timeIntervalSince1970: 1_790_000_000))
        try makeCatOffice(b, modified: Date(timeIntervalSince1970: 1_700_000_000))
        try makeCatOffice(r, modified: Date(timeIntervalSince1970: 1_600_000_000))
        let c = CatOfficeFinder.candidates(running: r.path, saved: b.path, roots: [root.appendingPathComponent("x").path])
        #expect(c.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["r", "b", "a"])
        #expect(c.first?.running == true && c.dropFirst().allSatisfy { !$0.running })
    }

    @Test func aStaleSavedFolderIsIgnored() throws {
        let root = makeTempDir()
        #expect(CatOfficeFinder.candidates(running: nil, saved: root.appendingPathComponent("gone").path, roots: [root.path]).isEmpty)
    }

    @Test func usualPlaces() {
        #expect(CatOfficeFinder.defaultRoots(home: "/Users/x") == ["/Users/x/Documents", "/Users/x/Documents/projects", "/Users/x/Downloads",
                                                                   "/Users/x/Desktop", "/Users/x/Developer", "/Users/x/Projects"])
    }
}
