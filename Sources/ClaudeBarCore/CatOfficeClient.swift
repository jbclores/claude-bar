import Foundation

/// Follows Cat Office's live feed (`GET /__agents/stream`), reconnecting with backoff.
/// `onUpdate` gets each snapshot, and nil whenever Cat Office can't be reached.
public final class CatOfficeClient: @unchecked Sendable {
    private let settings: LockedBox<CatOfficeSettings>
    private let onUpdate: @Sendable (OfficeSnapshot?) -> Void
    private let session: URLSession
    private let current = LockedBox<URL?>(nil)
    private var task: Task<Void, Never>?

    /// The address Cat Office was last reached at (bridge.json may name a different port than the settings).
    public var baseURL: URL { current.get() ?? settings.get().url }

    public init(settings: LockedBox<CatOfficeSettings>, onUpdate: @escaping @Sendable (OfficeSnapshot?) -> Void) {
        self.settings = settings
        self.onUpdate = onUpdate
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60 // the feed pings every 15s; silence this long means it's gone
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    public func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .utility) { [weak self] in await self?.run() }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Tries again right away instead of waiting out the backoff (e.g. just after starting Cat Office).
    public func reconnectNow() {
        stop()
        start()
    }

    private func run() async {
        var delay: UInt64 = 2
        while !Task.isCancelled {
            if let info = await resolve(), await follow(info) { delay = 2 }
            onUpdate(nil)
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 30)
        }
    }

    /// Where Cat Office is and its token: bridge.json first, else the token in its page.
    func resolve() async -> BridgeInfo? {
        let s = settings.get()
        if let dir = s.dir, let info = CatOfficeDiscovery.bridgeInfo(catOfficeDir: dir, isAlive: processIsAlive) {
            return info
        }
        guard let result = try? await session.data(from: s.url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let token = CatOfficeDiscovery.token(inPage: String(decoding: result.0, as: UTF8.self)) else { return nil }
        return BridgeInfo(url: s.url, token: token)
    }

    /// Follows the feed until it ends or fails. True when at least one snapshot arrived.
    func follow(_ info: BridgeInfo) async -> Bool {
        var request = URLRequest(url: info.url.appendingPathComponent("__agents/stream"))
        request.setValue(info.token, forHTTPHeaderField: "x-cat-office-token")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        guard let result = try? await session.bytes(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return false }
        current.set(info.url)
        var parser = SSEParser()
        var received = false
        do {
            for try await byte in result.0 {
                if let data = parser.feed(byte), case .snapshot(let snapshot)? = CatOfficeEvent.decode(data) {
                    received = true
                    onUpdate(snapshot)
                }
            }
        } catch {}
        return received
    }
}
