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

/// Single request per explicit action. No tools, retries, background calls or file access.
actor ClaudeService: ClaudeAdvising {
    private var cached: (key: String, result: AIAnalysis)?
    private var requesting = false
    private let transport: @Sendable (URLRequest) async throws -> Data
    init(transport: @escaping @Sendable (URLRequest) async throws -> Data = { try await ClaudeService.send($0) }) {
        self.transport = transport
    }
    func clearCache() { cached = nil }

    func analyze(_ packet: AIReviewPacket, model: ClaudeModel, apiKey: String) async throws -> AIAnalysis {
        let cacheKey = model.rawValue + ":" + packet.fingerprint
        if let cached, cached.key == cacheKey {
            var result = cached.result; result.cached = true; return result
        }
        guard !requesting else { throw SafetyError.refused("A Claude request is already running.") }
        requesting = true; defer { requesting = false }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try ClaudeMessages.body(packet: packet, model: model)
        let data = try await transport(request)
        try Task.checkCancellation()
        let result = try ClaudeMessages.decode(data, packet: packet)
        cached = (cacheKey, result)
        return result
    }

    static func send(_ request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (stream, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw SafetyError.refused("Claude returned an invalid HTTP response.") }
            guard response.statusCode == 200 else {
                let detail: String
                switch response.statusCode {
                case 401, 403: detail = "The API key was rejected or lacks access. Check it in Settings."
                case 429: detail = "Rate or credit limit reached. Check your Anthropic account before trying again."
                case 400, 404: detail = "The model or request is unavailable. Try another model or update the app."
                default: detail = "The service is unavailable (HTTP \(response.statusCode))."
                }
                throw SafetyError.refused("\(detail) No automatic retry was made.")
            }
            var data = Data()
            for try await byte in stream {
                try Task.checkCancellation()
                guard data.count < 64_000 else { throw SafetyError.refused("Claude's response exceeded the size limit.") }
                data.append(byte)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as SafetyError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw SafetyError.refused("Claude could not be reached. No automatic retry was made. A submitted request may still use credits.")
        }
    }
}
