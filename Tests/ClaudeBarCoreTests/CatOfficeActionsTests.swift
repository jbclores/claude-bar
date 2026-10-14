import Foundation
import Network
import Testing
@testable import ClaudeBarCore

/// A one-request HTTP server on 127.0.0.1: records what it got, answers `status` with `body`.
final class OneShotServer: @unchecked Sendable {
    let listener: NWListener
    private let box = LockedBox<String>("")
    var received: String { box.get() }
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(status: Int, body: String) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [unowned self] conn in
            conn.start(queue: .global())
            self.receiveAll(conn, buffer: Data()) {
                let reply = "HTTP/1.1 \(status) X\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                conn.send(content: Data(reply.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.start(queue: .global())
    }

    /// Receives until the headers and the whole body (per Content-Length) have arrived.
    private func receiveAll(_ conn: NWConnection, buffer: Data, done: @escaping @Sendable () -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var buffer = buffer
            buffer.append(data ?? Data())
            let text = String(decoding: buffer, as: UTF8.self)
            if let split = text.range(of: "\r\n\r\n") {
                let head = text[..<split.lowerBound].lowercased()
                let length = head.components(separatedBy: "\r\n")
                    .first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                if text[split.upperBound...].utf8.count >= length {
                    self.box.set(text)
                    done()
                    return
                }
            }
            if isComplete || error != nil { self.box.set(text); done(); return }
            self.receiveAll(conn, buffer: buffer, done: done)
        }
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
