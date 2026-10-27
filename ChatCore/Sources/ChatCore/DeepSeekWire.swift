import Foundation

// MARK: - Request

public struct ChatCompletionRequest: Encodable, Sendable, Hashable {
    public struct StreamOptions: Encodable, Sendable, Hashable {
        public var includeUsage: Bool
        enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
    }

    public struct Thinking: Encodable, Sendable, Hashable {
        public var type: String
    }

    public struct ResponseFormat: Encodable, Sendable, Hashable {
        public var type: String
    }

    public var model: String
    public var messages: [WireMessage]
    public var stream: Bool
    public var streamOptions: StreamOptions?
    public var thinking: Thinking?
    public var reasoningEffort: String?
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var responseFormat: ResponseFormat?
    public var stop: [String]?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, thinking, temperature, stop
        case streamOptions = "stream_options"
        case reasoningEffort = "reasoning_effort"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

public struct WireMessage: Encodable, Sendable, Hashable {
    public var role: String
    public var content: WireContent

    public init(role: String, content: WireContent) {
        self.role = role
        self.content = content
    }
}

/// A message body is either a plain string or, when images are involved, an array of parts.
public enum WireContent: Encodable, Sendable, Hashable {
    case text(String)
    case parts([WirePart])

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .parts(let p): try c.encode(p)
        }
    }

    public var textValue: String {
        switch self {
        case .text(let s): s
        case .parts(let parts):
            parts.compactMap { if case .text(let s) = $0 { s } else { nil } }.joined(separator: "\n\n")
        }
    }
}

public enum WirePart: Encodable, Sendable, Hashable {
    case text(String)
    case imageURL(String)

    private enum Keys: String, CodingKey { case type, text, imageURL = "image_url" }
    private enum URLKeys: String, CodingKey { case url }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .imageURL(let url):
            try c.encode("image_url", forKey: .type)
            var nested = c.nestedContainer(keyedBy: URLKeys.self, forKey: .imageURL)
            try nested.encode(url, forKey: .url)
        }
    }
}

// MARK: - Streaming response

public struct ChatCompletionChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public var delta: Delta?
        public var finishReason: String?
        enum CodingKeys: String, CodingKey { case delta, finishReason = "finish_reason" }
    }

    public struct Delta: Decodable, Sendable {
        public var content: String?
        public var reasoningContent: String?
        enum CodingKeys: String, CodingKey { case content, reasoningContent = "reasoning_content" }
    }

    public var model: String?
    public var choices: [Choice]
    public var usage: WireUsage?

    enum CodingKeys: String, CodingKey { case model, choices, usage }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        choices = try c.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        usage = try c.decodeIfPresent(WireUsage.self, forKey: .usage)
    }
}

public struct WireUsage: Decodable, Sendable {
    struct CompletionDetails: Decodable, Sendable {
        var reasoningTokens: Int?
        enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
    }

    var promptTokens: Int?
    var completionTokens: Int?
    var promptCacheHitTokens: Int?
    var completionTokensDetails: CompletionDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case promptCacheHitTokens = "prompt_cache_hit_tokens"
        case completionTokensDetails = "completion_tokens_details"
    }

    public var usage: Usage {
        Usage(
            promptTokens: promptTokens ?? 0,
            completionTokens: completionTokens ?? 0,
            cacheHitTokens: promptCacheHitTokens,
            reasoningTokens: completionTokensDetails?.reasoningTokens
        )
    }
}

/// Token counts for one reply. Stored with the message, so new fields must be optional.
public struct Usage: Codable, Hashable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var cacheHitTokens: Int?
    public var reasoningTokens: Int?

    public init(promptTokens: Int, completionTokens: Int, cacheHitTokens: Int? = nil, reasoningTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cacheHitTokens = cacheHitTokens
        self.reasoningTokens = reasoningTokens
    }
}

// MARK: - Other endpoints

public struct APIErrorEnvelope: Decodable, Sendable {
    public struct Body: Decodable, Sendable {
        public var message: String?
        public var type: String?
    }

    public var error: Body

    public static func message(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) else { return nil }
        return envelope.error.message
    }
}

public struct ModelList: Decodable, Sendable {
    public struct Model: Decodable, Sendable {
        public var id: String
    }

    public var data: [Model]
}

public struct Balance: Decodable, Sendable {
    public struct Info: Decodable, Sendable {
        public var currency: String
        public var totalBalance: String
        enum CodingKeys: String, CodingKey { case currency, totalBalance = "total_balance" }
    }

    public var isAvailable: Bool
    public var balanceInfos: [Info]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    /// e.g. "¥12.30" or "$4.10, ¥2.00".
    public var formatted: String {
        guard !balanceInfos.isEmpty else { return "—" }
        return balanceInfos.map { info in
            switch info.currency.uppercased() {
            case "CNY": "¥\(info.totalBalance)"
            case "USD": "$\(info.totalBalance)"
            default: "\(info.totalBalance) \(info.currency)"
            }
        }.joined(separator: ", ")
    }
}
