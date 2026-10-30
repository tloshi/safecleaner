import Foundation
import CryptoKit

public enum ClaudeModel: String, CaseIterable, Sendable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    public var title: String { self == .haiku ? "Haiku 5.5 · Economy" : "Sonnet 5.5 · More capable" }
}

public struct AIReviewGroup: Encodable, Sendable {
    public let id: String
    public let kind: String
    public let items: Int
    public let allocatedMB: Int64
    public let scanOnly: Bool
    public let candidateIDs: [String]
    enum CodingKeys: String, CodingKey { case id, kind, items, allocatedMB, scanOnly }
}

public struct AIReviewPacket: Sendable {
    public static let maxGroups = 16
    public let groups: [AIReviewGroup]
    public let omittedGroups: Int
    public let skippedLocations: Int
    public let fingerprint: String
    public let json: String

    public init(candidates: [Candidate], skippedLocations: Int) {
        func kind(_ c: Candidate) -> String {
            if c.category == .projects {
                let name = c.url.lastPathComponent
                let known = BuildOutput.rules.contains { $0.directory == name }
                return known ? "Project \(name)" : "Other project output"
            }
            if c.category == .developer {
                // Per-project DerivedData folders carry project names; all of them share one
                // fixed label, so no name leaves the Mac.
                if c.url.deletingLastPathComponent().lastPathComponent == "DerivedData" { return "Xcode DerivedData" }
                let known = ["DerivedData": "Xcode DerivedData", "org.swift.swiftpm": "SwiftPM cache",
                    "_cacache": "npm cache", "build-cache-1": "Gradle build cache", "CocoaPods": "CocoaPods cache",
                    "downloads": "Tool downloads", "pip": "Python package cache"]
                return known[c.url.lastPathComponent] ?? "Other developer cache"
            }
            return c.category.title
        }
        let buckets = Dictionary(grouping: candidates) { kind($0) + ($0.canTrash ? "|review" : "|scan") }
        let sorted = buckets.sorted {
            let lhs = $0.value.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
            let rhs = $1.value.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
            return lhs == rhs ? $0.key < $1.key : lhs > rhs
        }
        groups = sorted.prefix(Self.maxGroups).enumerated().map { index, bucket in
            AIReviewGroup(id: "g\(index + 1)", kind: kind(bucket.value[0]), items: bucket.value.count,
                allocatedMB: bucket.value.reduce(Int64(0)) { $0 + max(0, $1.bytes) } / 1_000_000,
                scanOnly: !bucket.value[0].canTrash, candidateIDs: bucket.value.map(\.id).sorted())
        }
        omittedGroups = max(0, sorted.count - groups.count)
        self.skippedLocations = max(0, skippedLocations)
        struct Payload: Encodable {
            let groups: [AIReviewGroup]
            let omittedGroups: Int
            let skippedLocations: Int
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(Payload(groups: groups, omittedGroups: omittedGroups,
                                              skippedLocations: self.skippedLocations))) ?? Data()
        json = String(decoding: data, as: UTF8.self)
        var digest = SHA256(); digest.update(data: data)
        for c in candidates.sorted(by: { $0.id < $1.id }) {
            digest.update(data: Data("\(c.id)\u{0}\(c.stamp.digest)\u{0}\(c.canTrash)\n".utf8))
        }
        fingerprint = digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum AIDisposition: String, Codable, Sendable {
    case review, keep, inspect
    public var title: String {
        switch self { case .review: return "Review first"; case .keep: return "Keep for now"; case .inspect: return "Inspect manually" }
    }
}

public struct AIRecommendation: Codable, Sendable {
    public let groupID: String
    public let disposition: AIDisposition
    public let reason: String
    public let caution: String
    public init(groupID: String, disposition: AIDisposition, reason: String, caution: String) {
        self.groupID = groupID; self.disposition = disposition; self.reason = reason; self.caution = caution
    }
}

public struct AIAnalysis: Sendable {
    public let summary: String
    public let recommendations: [AIRecommendation]
    public let inputTokens: Int
    public let outputTokens: Int
    public var cached: Bool
    public init(summary: String, recommendations: [AIRecommendation], inputTokens: Int, outputTokens: Int, cached: Bool = false) {
        self.summary = summary; self.recommendations = recommendations
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.cached = cached
    }
}

/// Outcome of the free key check against the Models endpoint: Anthropic accepted the key and the
/// chosen model exists for that account. It says nothing about the credit balance.
public struct ClaudeKeyCheck: Sendable, Equatable {
    public let modelID: String
    public let modelName: String
    public init(modelID: String, modelName: String) { self.modelID = modelID; self.modelName = modelName }
}

/// A failed Anthropic exchange, classified so the ViewModel can mark the key status without
/// parsing message text. `message` is already safe to show: bounded, control characters removed,
/// never containing the key.
public struct ClaudeFailure: LocalizedError, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case authentication, billing, model, rateLimit, service, network, invalidResponse, busy }
    public let kind: Kind
    public let message: String
    public init(kind: Kind, message: String) { self.kind = kind; self.message = message }
    public var errorDescription: String? { message }
}

public protocol ClaudeAdvising: Sendable {
    func analyze(_ packet: AIReviewPacket, model: ClaudeModel, apiKey: String) async throws -> AIAnalysis
    /// One free GET against the Models endpoint. No scan data, no tokens.
    func verify(apiKey: String, model: ClaudeModel) async throws -> ClaudeKeyCheck
    func clearCache() async
}

@MainActor public protocol APIKeyStoring {
    func hasKey() throws -> Bool
    func read() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

public enum ClaudeMessages {
    /// Claude 5.5 models think before answering and that reasoning counts toward `max_tokens`.
    /// The plan itself stays bounded by the length checks in `decode`; this leaves room for both.
    public static let maxOutputTokens = 4000
    public static let maxRequestBytes = 12_000
    public static let maxResponseBytes = 64_000
    public static let maxErrorDetailCharacters = 240
    public static let apiVersion = "2026-10-21"
    public static let messagesEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static func modelEndpoint(_ model: ClaudeModel) -> URL {
        URL(string: "https://api.anthropic.com/v1/models/\(model.rawValue)")!
    }
    public static let systemPrompt = """
    You advise on a macOS cleanup scan. Return a concise English review plan, never commands or deletion instructions.
    Only the supplied aggregate groups exist. Their size is an allocated estimate, not guaranteed recoverable space.
    No file contents, paths, project names, last-use dates or running-process information are available.
    Do not invent age, disuse, safety, exact savings or evidence. A build-folder name is not proof it contains only generated data.
    Prefer keep or inspect when evidence is insufficient. scanOnly groups must be inspect or keep.
    Explain rebuild/download costs and the need to close owning apps and stop builds. Trash does not itself free space.
    Rank up to 6 supplied groups by useful review priority. summary <= 500 characters; each reason and caution <= 180 characters.
    Skipped locations and omitted groups are unassessed, not empty. Your output cannot authorize cleanup or override local protections.
    """

    public static func body(packet: AIReviewPacket, model: ClaudeModel) throws -> Data {
        guard !packet.groups.isEmpty else { throw SafetyError.refused("Run a scan with candidates before asking Claude.") }
        let string: [String: Any] = ["type": "string"]
        let recommendation: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["groupID": string, "disposition": ["type": "string", "enum": ["review", "keep", "inspect"]],
                           "reason": string, "caution": string],
            "required": ["groupID", "disposition", "reason", "caution"]]
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["summary": string, "recommendations": ["type": "array", "items": recommendation]],
            "required": ["summary", "recommendations"]]
        let data = try JSONSerialization.data(withJSONObject: [
            "model": model.rawValue, "max_tokens": maxOutputTokens, "system": systemPrompt,
            "messages": [["role": "user", "content": packet.json]],
            // Low effort: a short ranking does not need deep reasoning, and it keeps the
            // reasoning tokens that count toward max_tokens small on both 5.5 models.
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]]
        ], options: [.sortedKeys])
        guard data.count <= maxRequestBytes else { throw SafetyError.refused("The AI summary exceeds the request limit.") }
        return data
    }

    public static func decode(_ data: Data, packet: AIReviewPacket) throws -> AIAnalysis {
        struct Envelope: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            struct Usage: Decodable { let input_tokens: Int; let output_tokens: Int }
            let stop_reason: String
            let content: [Block]
            let usage: Usage
        }
        struct Plan: Decodable { let summary: String; let recommendations: [AIRecommendation] }
        do {
            guard data.count <= maxResponseBytes else { throw SafetyError.refused("Oversized response") }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            // Claude 5.5 models may answer with thinking blocks before the text. Read blocks by
            // type, never by position, and accept exactly one text block.
            let reasoning: Set<String> = ["thinking", "redacted_thinking"]
            let texts = envelope.content.filter { $0.type == "text" }
            guard envelope.stop_reason == "end_turn", texts.count == 1, let text = texts[0].text,
                  envelope.content.allSatisfy({ $0.type == "text" || reasoning.contains($0.type) }),
                  envelope.usage.input_tokens >= 0, envelope.usage.output_tokens >= 0 else {
                throw SafetyError.refused("Incomplete response")
            }
            let plan = try JSONDecoder().decode(Plan.self, from: Data(text.utf8))
            guard !plan.summary.isEmpty, plan.summary.count <= 600, plan.recommendations.count <= 6,
                  Set(plan.recommendations.map(\.groupID)).count == plan.recommendations.count else {
                throw SafetyError.refused("Invalid plan")
            }
            for r in plan.recommendations {
                guard let group = packet.groups.first(where: { $0.id == r.groupID }),
                      !r.reason.isEmpty, r.reason.count <= 240, !r.caution.isEmpty, r.caution.count <= 240,
                      !(group.scanOnly && r.disposition == .review) else { throw SafetyError.refused("Invalid group") }
            }
            return AIAnalysis(summary: plan.summary, recommendations: plan.recommendations,
                              inputTokens: envelope.usage.input_tokens, outputTokens: envelope.usage.output_tokens)
        } catch {
            throw ClaudeFailure(kind: .invalidResponse,
                message: "Claude returned an incomplete or invalid plan. No selection or files were changed. A request may still have used credits.")
        }
    }

    /// Maps a non-200 reply to a user-facing failure. Anthropic's error body names the exact
    /// cause (`authentication_error: invalid x-api-key`, a credit balance that is too low, an
    /// unknown model), so it is surfaced in sanitized form instead of being discarded.
    public static func failure(status: Int, body: Data) -> ClaudeFailure {
        struct Envelope: Decodable {
            struct Detail: Decodable { let type: String?; let message: String? }
            let error: Detail?
        }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        let type = sanitize(detail?.type ?? "")
        let message = sanitize(detail?.message ?? "")
        let kind: ClaudeFailure.Kind
        let hint: String
        let action: String
        switch status {
        case 401:
            kind = .authentication; hint = "Anthropic rejected the API key."; action = "Check the key in Settings."
        case 403:
            kind = .authentication; hint = "This API key is not allowed to use the service."; action = "Check the key's permissions in the Anthropic Console."
        case 402:
            kind = .billing; hint = "Anthropic reported a billing problem."; action = "Check Plans & Billing in the Anthropic Console."
        case 400 where message.localizedCaseInsensitiveContains("credit"):
            kind = .billing; hint = "The key works, but the account has no credits."; action = "Add credits in the Anthropic Console."
        case 404:
            kind = .model; hint = "The model is not available to this API key."; action = "Try the other model or update the app."
        case 400, 413, 422:
            kind = .model; hint = "Anthropic refused the request."; action = "Try the other model or update the app."
        case 429:
            kind = .rateLimit; hint = "Rate or spending limit reached."; action = "Check your Anthropic account before trying again."
        case 529:
            kind = .service; hint = "Anthropic is overloaded right now."; action = "Try again later."
        default:
            kind = .service; hint = "Anthropic returned HTTP \(status)."; action = "Try again later."
        }
        let cause = [type, message].filter { !$0.isEmpty }.joined(separator: ": ")
        let lead = cause.isEmpty ? hint : "\(hint) (\(cause))."
        return ClaudeFailure(kind: kind, message: "\(lead) \(action) No automatic retry was made.")
    }

    public static func decodeModel(_ data: Data, expected: ClaudeModel) throws -> ClaudeKeyCheck {
        struct Model: Decodable { let id: String; let display_name: String? }
        guard data.count <= maxResponseBytes, let model = try? JSONDecoder().decode(Model.self, from: data),
              model.id == expected.rawValue else {
            throw ClaudeFailure(kind: .invalidResponse, message: "Anthropic answered the key check with something unexpected. Try again later.")
        }
        let name = sanitize(model.display_name ?? "")
        return ClaudeKeyCheck(modelID: model.id, modelName: name.isEmpty ? model.id : name)
    }

    /// Untrusted provider text: drop control characters and bound the length before display.
    static func sanitize(_ text: String) -> String {
        let flat = text.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(maxErrorDetailCharacters))
    }
}
