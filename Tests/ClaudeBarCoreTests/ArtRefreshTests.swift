import Foundation
import ImageIO
import Testing
@testable import ClaudeBarCore

/// A stand-in Cat Office per host: each file has a version; it sends an ETag and answers 304 to a matching
/// If-None-Match, as Cat Office's Vite server does. Requests are counted per host (tests run in parallel).
final class VersionedArtProtocol: URLProtocol {
    struct Site { var version = 1; var cats = ["orange"]; var requests: [String] = []; var down = false }
    static let sites = LockedBox<[String: Site]>([:])

    static func site(_ host: String) -> Site { sites.get()[host] ?? Site() }
    static func update(_ host: String, _ change: (inout Site) -> Void) {
        sites.update { var s = $0[host] ?? Site(); change(&s); $0[host] = s }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!, host = url.host ?? ""
        Self.update(host) { $0.requests.append(url.path) }
        let site = Self.site(host)
        if site.down { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
        let tag = url.path.hasSuffix("cats.json") ? "W/\"cats-\(site.cats.joined(separator: "+"))\"" : "W/\"v\(site.version)\""
        if request.value(forHTTPHeaderField: "If-None-Match") == tag {
            let r = HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: ["ETag": tag])!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let body: Data = url.path.hasSuffix("cats.json")
            ? try! JSONSerialization.data(withJSONObject: ["cats": site.cats.map { ["id": $0] }])
            : ArtCacheTests.png(width: 10 * site.version, height: 10)!
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": tag])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite struct ArtRefreshTests {
    let path = "assets/cats/orange/sleep.png"

    /// A cache on its own host and temp folder, with a clock the test moves.
    func make(_ host: String, clock: LockedBox<Date>) -> ArtCache {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VersionedArtProtocol.self]
        return ArtCache(dir: makeTempDir(), baseURL: { URL(string: "http://\(host)")! },
                        session: URLSession(configuration: config), now: { clock.get() })
    }
    func width(_ png: Data?) -> Int? {
        png.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width
    }

    @Test func aFreshCopyIsNotCheckedAgainWithinAMinute() async {
        let clock = LockedBox(Date(timeIntervalSince1970: 0)), host = "fresh.test"
        let cache = make(host, clock: clock)
        _ = await cache.image(path: path)
        clock.set(Date(timeIntervalSince1970: 30))
        _ = await cache.image(path: path)
        #expect(VersionedArtProtocol.site(host).requests.count == 1)
    }

    @Test func anUnchangedPictureIsReCheckedCheaplyAndKept() async {
        let clock = LockedBox(Date(timeIntervalSince1970: 0)), host = "same.test"
        let cache = make(host, clock: clock)
        let first = await cache.image(path: path)
        clock.set(Date(timeIntervalSince1970: 61))
        let changed = await cache.revalidate()
        #expect(changed == false)
        #expect(await cache.image(path: path) == first)
        #expect(VersionedArtProtocol.site(host).requests.count == 2, "one first load, one 304 check")
    }

    @Test func anEditedCharacterIsPickedUp() async {
        let clock = LockedBox(Date(timeIntervalSince1970: 0)), host = "edited.test"
        let cache = make(host, clock: clock)
        #expect(width(await cache.image(path: path)) == 10)
        VersionedArtProtocol.update(host) { $0.version = 2 }    // the character was edited in Cat Office
        clock.set(Date(timeIntervalSince1970: 61))
        #expect(await cache.revalidate() == true)
        #expect(width(await cache.image(path: path)) == 20)
    }

    @Test func refreshNowChecksEvenAFreshCopy() async {
        let clock = LockedBox(Date(timeIntervalSince1970: 0)), host = "now.test"
        let cache = make(host, clock: clock)
        _ = await cache.image(path: path)
        VersionedArtProtocol.update(host) { $0.version = 3 }
        #expect(await cache.revalidate(force: true) == true)
        #expect(width(await cache.image(path: path)) == 30)
    }

    @Test func catOfficeOffKeepsTheSavedPictures() async {
        let clock = LockedBox(Date(timeIntervalSince1970: 0)), host = "off.test"
        let cache = make(host, clock: clock)
        let first = await cache.image(path: path)
        VersionedArtProtocol.update(host) { $0.down = true }
        clock.set(Date(timeIntervalSince1970: 61))
        #expect(await cache.revalidate() == false)
        #expect(await cache.image(path: path) == first)
    }

    @Test func aNewCharacterInTheCatListIsPickedUp() async {
        let clock = LockedBox(Date(timeIntervalSince1970: 0)), host = "list.test"
        let cache = make(host, clock: clock)
        #expect(await cache.catalog()?.catIds == ["orange"])
        VersionedArtProtocol.update(host) { $0.cats = ["orange", "my-cat"] }
        #expect(await cache.catalog(refresh: true)?.catIds == ["orange", "my-cat"])
        // Unchanged: a cheap check, the same list.
        #expect(await cache.catalog(refresh: true)?.catIds == ["orange", "my-cat"])
    }
}
