import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct ConfigStoreTests {
    @Test func createsEmptyFileWhenMissing() throws {
        let file = makeTempDir().appendingPathComponent("sub/projects.json")
        let store = ConfigStore(file: file)
        store.reload()
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.config == .empty)
        #expect(store.error == nil)
    }

    @Test func parsesProjectsWithDefaultsAndTilde() throws {
        let dir = makeTempDir()
        let proj = dir.appendingPathComponent("alpha")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("projects.json")
        write("""
        {"projects":[{"path":"\(proj.path)/"},{"path":"~/elsewhere","name":"Else"}],
         "catOffice":{"dir":"~/co","url":"http://localhost:6000","autoStart":false},"notifications":false}
        """, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        let c = store.config
        #expect(c.projects.map(\.name) == ["alpha", "Else"])
        #expect(c.projects[0].path == Paths.normalize(proj.path))
        #expect(c.projects[1].path == Paths.normalize(NSHomeDirectory() + "/elsewhere"))
        #expect(c.catOffice.dir == Paths.normalize(NSHomeDirectory() + "/co"))
        #expect(c.catOffice.url == URL(string: "http://localhost:6000"))
        #expect(c.catOffice.autoStart == false)
        #expect(c.notifications == false)
        #expect(Config.empty.catOffice.autoStart)
    }

    @Test func invalidFileKeepsLastGoodConfig() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write(#"{"projects":[{"path":"/a"}]}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        #expect(store.config.projects.count == 1)
        write(#"{"projects": [ oops"#, to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        #expect(store.reload())
        #expect(store.config.projects.count == 1)
        #expect(store.error != nil)
        write(#"{"projects":[{"name":"no path"}]}"#, to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(20)], ofItemAtPath: file.path)
        store.reload()
        #expect(store.error != nil)
        #expect(store.config.projects.count == 1)
    }

    @Test func reloadOnlyWhenFileChanges() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write(#"{"projects":[]}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        #expect(store.reload() == false)
        write(#"{"projects":[{"path":"/b"}]}"#, to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        #expect(store.reload())
        #expect(store.config.projects.map(\.path) == ["/b"])
    }

    @Test func addDedupesKeepsOrderAndOtherKeys() throws {
        let dir = makeTempDir()
        let file = dir.appendingPathComponent("projects.json")
        write(#"{"projects":[{"path":"/x","name":"X"}],"notifications":false,"extra":{"keep":1}}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        try store.add(paths: ["/y", "/x/", "/y", "/z"])
        #expect(store.config.projects.map(\.path) == ["/x", "/y", "/z"])
        #expect(store.config.projects[0].name == "X")
        #expect(store.config.notifications == false)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect((raw["extra"] as? [String: Any])?["keep"] as? Int == 1)
    }

    @Test func removeByAnySpelling() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write(#"{"projects":[{"path":"/x"},{"path":"/y"}]}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        try store.remove(path: "/x/")
        #expect(store.config.projects.map(\.path) == ["/y"])
    }

    @Test func editingABrokenFileThrowsAndLeavesItAlone() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write("{ broken", to: file)
        let store = ConfigStore(file: file)
        store.reload()
        #expect(throws: ConfigError.self) { try store.add(paths: ["/a"]) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ broken")
    }
}

@Suite struct ConfigSettingsTests {
    @Test func hoverPeekDefaultsOnAndParses() throws {
        #expect(Config.empty.hoverPeek)
        #expect(try Config.parse(Data(#"{"hoverPeek":false}"#.utf8)).hoverPeek == false)
    }

    @Test func setWritesOneSettingAndKeepsEverythingElse() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write(#"{"projects":[{"path":"/x","name":"X"}],"catOffice":{"url":"http://localhost:6000"},"extra":1}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        try store.set(false, at: ["notifications"])
        try store.set(false, at: ["catOffice", "autoStart"])
        try store.set(false, at: ["hoverPeek"])
        #expect(store.config.notifications == false)
        #expect(store.config.catOffice.autoStart == false)
        #expect(store.config.catOffice.url == URL(string: "http://localhost:6000"))
        #expect(store.config.hoverPeek == false)
        #expect(store.config.projects.map(\.name) == ["X"])
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(raw["extra"] as? Int == 1)
        try store.set(true, at: ["hoverPeek"])
        #expect(store.config.hoverPeek)
    }

    @Test func setCreatesTheFileAndNestedObjects() throws {
        let file = makeTempDir().appendingPathComponent("sub/projects.json")
        let store = ConfigStore(file: file)
        try store.set(false, at: ["catOffice", "autoStart"])
        #expect(store.config.catOffice.autoStart == false)
    }

    @Test func setRefusesABrokenFile() {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write("{ broken", to: file)
        let store = ConfigStore(file: file)
        #expect(throws: ConfigError.self) { try store.set(false, at: ["hoverPeek"]) }
    }
}
