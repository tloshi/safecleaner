import XCTest
import SafeCleanerCore
@testable import SafeCleaner

final class ClaudeServiceTests: XCTestCase {
    private func packet(digest: String = "one") -> AIReviewPacket {
        .init(candidates: [.init(url: URL(fileURLWithPath: "/fixture/DerivedData"), title: "Fixture", category: .developer,
            reason: "Fixture", consequence: "Rebuild", stamp: .init(digest: digest, logicalBytes: 500, allocatedBytes: 500, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: nil)], skippedLocations: 0)
    }
    func testCachedAnalysisDoesNotMakeAnotherRequestButChangedSnapshotOrModelDoes() async throws {
        let transport = StubTransport()
        let service = ClaudeService { try await transport.send($0) }
        let first = try await service.analyze(packet(), model: .haiku, apiKey: "synthetic")
        let second = try await service.analyze(packet(), model: .haiku, apiKey: "synthetic")
        XCTAssertFalse(first.cached); XCTAssertTrue(second.cached)
        var count = await transport.calls
        XCTAssertEqual(count, 1)
        _ = try await service.analyze(packet(digest: "changed"), model: .haiku, apiKey: "synthetic")
        _ = try await service.analyze(packet(digest: "changed"), model: .sonnet, apiKey: "synthetic")
        count = await transport.calls; XCTAssertEqual(count, 3)
        await service.clearCache()
        _ = try await service.analyze(packet(digest: "changed"), model: .sonnet, apiKey: "synthetic")
        count = await transport.calls; XCTAssertEqual(count, 4)
    }
    func testFailureIsNotRetriedAndRequestIsBoundToAnthropic() async throws {
        let transport = StubTransport(fail: true)
        let service = ClaudeService { try await transport.send($0) }
        do { _ = try await service.analyze(packet(), model: .haiku, apiKey: "synthetic"); XCTFail("Expected failure") } catch {}
        let calls = await transport.calls, request = await transport.lastRequest
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "synthetic")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), ClaudeMessages.apiVersion)
        XCTAssertEqual(request?.timeoutInterval, ClaudeService.analysisTimeout)
        let body = try XCTUnwrap(request?.httpBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("synthetic"))
    }
    /// The key check is the answer to “is my key actually working?” It must cost nothing and carry no scan data.
    func testKeyCheckUsesModelsEndpointWithoutScanDataAndNamesTheModel() async throws {
        let transport = StubTransport()
        let service = ClaudeService { try await transport.send($0) }
        let check = try await service.verify(apiKey: "synthetic", model: .haiku)
        XCTAssertEqual(check.modelName, "Claude Haiku 5.5")
        let request = await transport.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/v1/models/claude-haiku-5-5")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertNil(request?.httpBody)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "synthetic")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), ClaudeMessages.apiVersion)
        XCTAssertEqual(request?.timeoutInterval, ClaudeService.keyCheckTimeout)
    }
    func testRejectedKeySurfacesAnthropicsReasonForBothRequests() async throws {
        let transport = StubTransport(status: 401)
        let service = ClaudeService { try await transport.send($0) }
        for run in 0..<2 {
            do {
                if run == 0 { _ = try await service.verify(apiKey: "synthetic", model: .haiku) }
                else { _ = try await service.analyze(packet(), model: .haiku, apiKey: "synthetic") }
                XCTFail("Expected rejection")
            } catch let failure as ClaudeFailure {
                XCTAssertEqual(failure.kind, .authentication)
                XCTAssertTrue(failure.message.contains("authentication_error: invalid x-api-key"), failure.message)
                XCTAssertFalse(failure.message.contains("synthetic"))
            }
        }
        let calls = await transport.calls
        XCTAssertEqual(calls, 2, "a rejected request is never retried")
    }
}

private actor StubTransport {
    var calls = 0
    var lastRequest: URLRequest?
    let fail: Bool
    let status: Int
    init(fail: Bool = false, status: Int = 200) { self.fail = fail; self.status = status }
    func send(_ request: URLRequest) throws -> HTTPReply {
        calls += 1; lastRequest = request
        if fail { throw URLError(.notConnectedToInternet) }
        guard status == 200 else {
            let body = try JSONSerialization.data(withJSONObject: ["type": "error",
                "error": ["type": "authentication_error", "message": "invalid x-api-key"]])
            return HTTPReply(status: status, body: body)
        }
        if request.httpMethod == "GET" {
            return HTTPReply(status: 200, body: try JSONSerialization.data(withJSONObject:
                ["type": "model", "id": "claude-haiku-5-5", "display_name": "Claude Haiku 5.5"]))
        }
        let plan = "{\"summary\":\"Review manually.\",\"recommendations\":[]}"
        // Claude 5.5 models think first; the empty thinking block is what the API returns by default.
        return HTTPReply(status: 200, body: try JSONSerialization.data(withJSONObject: ["stop_reason": "end_turn",
            "content": [["type": "thinking", "thinking": "", "signature": "sig"], ["type": "text", "text": plan]],
            "usage": ["input_tokens": 100, "output_tokens": 20]]))
    }
}
