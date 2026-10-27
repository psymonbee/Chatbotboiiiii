import Foundation

public enum ReasoningEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, high, max

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .low: "Low"
        case .high: "High"
        case .max: "Max"
        }
    }
}

/// Everything about a request except the conversation itself.
///
/// Stored inside encrypted chat and persona payloads, so decoding is lenient:
/// a missing key falls back to its default. Add new fields the same way.
public struct GenerationSettings: Codable, Hashable, Sendable {
    public static let defaultModel = "deepseek-flash"
    public static let temperatureRange: ClosedRange<Double> = 0...2
    public static let topPRange: ClosedRange<Double> = 0...1
    public static let maxTokensRange: ClosedRange<Int> = 1...393_216
    public static let maxStopSequences = 16

    public var model: String
    public var thinking: Bool
    public var reasoningEffort: ReasoningEffort
    /// `nil` means "let the API decide".
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var jsonMode: Bool
    public var stopSequences: [String]

    public init(
        model: String = GenerationSettings.defaultModel,
        thinking: Bool = true,
        reasoningEffort: ReasoningEffort = .high,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        jsonMode: Bool = false,
        stopSequences: [String] = []
    ) {
        self.model = model
        self.thinking = thinking
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.jsonMode = jsonMode
        self.stopSequences = stopSequences
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GenerationSettings()
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        thinking = try c.decodeIfPresent(Bool.self, forKey: .thinking) ?? d.thinking
        reasoningEffort = (try? c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)) ?? d.reasoningEffort
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try c.decodeIfPresent(Double.self, forKey: .topP)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        jsonMode = try c.decodeIfPresent(Bool.self, forKey: .jsonMode) ?? d.jsonMode
        stopSequences = try c.decodeIfPresent([String].self, forKey: .stopSequences) ?? d.stopSequences
    }

    /// Clamps every value into the range the API accepts.
    public var sanitized: GenerationSettings {
        var s = self
        s.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.model.isEmpty { s.model = Self.defaultModel }
        s.temperature = temperature.map { min(max($0, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound) }
        s.topP = topP.map { min(max($0, Self.topPRange.lowerBound), Self.topPRange.upperBound) }
        s.maxTokens = maxTokens.map { min(max($0, Self.maxTokensRange.lowerBound), Self.maxTokensRange.upperBound) }
        s.stopSequences = Array(stopSequences.filter { !$0.isEmpty }.prefix(Self.maxStopSequences))
        return s
    }
}
