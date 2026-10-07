import Foundation
import Testing
/// A fresh empty directory under the temp folder, with symlinks resolved.
func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("claudebar-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

func write(_ text: String, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(text.utf8).write(to: url)
}

/// A file under Tests/ClaudeBarCoreTests/Fixtures.
func fixture(_ path: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/" + path, withExtension: nil))
    return try Data(contentsOf: url)
}
