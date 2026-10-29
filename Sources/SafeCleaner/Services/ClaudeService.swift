import Foundation
import Security
import LocalAuthentication
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

@MainActor final class KeychainAPIKeyStore: APIKeyStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.loshi.safecleaner.claude",
         kSecAttrAccount as String: "anthropic-api-key",
         kSecAttrSynchronizable as String: false]
    }
    func hasKey() throws -> Bool {
        var q = query
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        try check(status); return true
    }
    func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw SafetyError.refused("The saved API key could not be read. Save it again.")
        }
        return key
    }
    func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(q as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw SafetyError.refused("Keychain access failed (\(status)). Your API key was not changed in the app. Check macOS Keychain access and try again.")
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Status and body together, so a non-200 reply keeps the error body Anthropic sent with it.
struct HTTPReply: Sendable {
    let status: Int
    let body: Data
}

actor ClaudeService: ClaudeAdvising {
    static let analysisTimeout: TimeInterval = 60
    static let keyCheckTimeout: TimeInterval = 20
    private var cached: (key: String, result: AIAnalysis)?
    private var requesting = false
    private let transport: @Sendable (URLRequest) async throws -> HTTPReply
    init(transport: @escaping @Sendable (URLRequest) async throws -> HTTPReply = { try await ClaudeService.send($0) }) {
        self.transport = transport
    }
    func clearCache() { cached = nil }

    func analyze(_ packet: AIReviewPacket, model: ClaudeModel, apiKey: String) async throws -> AIAnalysis {
        let cacheKey = model.rawValue + ":" + packet.fingerprint
        if let cached, cached.key == cacheKey {
            var result = cached.result; result.cached = true; return result
        }
        var request = Self.request(ClaudeMessages.messagesEndpoint, method: "POST", apiKey: apiKey, timeout: Self.analysisTimeout)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try ClaudeMessages.body(packet: packet, model: model)
        let reply = try await exchange(request)
        guard reply.status == 200 else { throw ClaudeMessages.failure(status: reply.status, body: reply.body) }
        let result = try ClaudeMessages.decode(reply.body, packet: packet)
        cached = (cacheKey, result)
        return result
    }

    func verify(apiKey: String, model: ClaudeModel) async throws -> ClaudeKeyCheck {
        let request = Self.request(ClaudeMessages.modelEndpoint(model), method: "GET", apiKey: apiKey, timeout: Self.keyCheckTimeout)
        let reply = try await exchange(request)
        guard reply.status == 200 else { throw ClaudeMessages.failure(status: reply.status, body: reply.body) }
        return try ClaudeMessages.decodeModel(reply.body, expected: model)
    }

    private func exchange(_ request: URLRequest) async throws -> HTTPReply {
        guard !requesting else { throw ClaudeFailure(kind: .busy, message: "A Claude request is already running.") }
        requesting = true; defer { requesting = false }
        let reply = try await transport(request)
        try Task.checkCancellation()
        return reply
    }

    private static func request(_ url: URL, method: String, apiKey: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeMessages.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
    }

    static func send(_ request: URLRequest) async throws -> HTTPReply {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval * 1.5
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (stream, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ClaudeFailure(kind: .invalidResponse, message: "Claude returned an invalid HTTP response.")
            }
            var data = Data()
            for try await byte in stream {
                try Task.checkCancellation()
                if data.count >= ClaudeMessages.maxResponseBytes {
                    // A successful reply this large is rejected; an error body is simply cut.
                    guard response.statusCode != 200 else {
                        throw ClaudeFailure(kind: .invalidResponse, message: "Claude's response exceeded the size limit.")
                    }
                    break
                }
                data.append(byte)
            }
            return HTTPReply(status: response.statusCode, body: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClaudeFailure { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // URLError descriptions name the cause (offline, DNS, timeout) and never carry headers.
            throw ClaudeFailure(kind: .network,
                message: "Claude could not be reached: \(error.localizedDescription) No automatic retry was made. A submitted request may still use credits.")
        }
    }
}
