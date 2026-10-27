import Foundation

public enum StreamEvent: Sendable, Equatable {
    case reasoning(String)
    case content(String)
    case finished(reason: String)
    case usage(Usage)
    case done
}

public struct StreamError: Error, LocalizedError, Sendable, Equatable {
    public var message: String
    public var errorDescription: String? { message }
}

/// Turns server-sent-event lines from `/chat/completions` into events.
/// Feed it one line at a time, without the trailing newline.
public struct StreamParser: Sendable {
    private let decoder = JSONDecoder()

    public init() {}

    public func parse(line: String) throws -> [StreamEvent] {
        guard line.hasPrefix("data:") else { return [] } // blank lines, ": keep-alive" comments, event names
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }
        let data = Data(payload.utf8)

        if let message = APIErrorEnvelope.message(from: data) { throw StreamError(message: message) }
        guard let chunk = try? decoder.decode(ChatCompletionChunk.self, from: data) else { return [] }

        var events: [StreamEvent] = []
        for choice in chunk.choices {
            if let r = choice.delta?.reasoningContent, !r.isEmpty { events.append(.reasoning(r)) }
            if let c = choice.delta?.content, !c.isEmpty { events.append(.content(c)) }
            if let reason = choice.finishReason { events.append(.finished(reason: reason)) }
        }
        if let usage = chunk.usage { events.append(.usage(usage.usage)) }
        return events
    }
}
