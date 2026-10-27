import Foundation

/// One message of a conversation, in the shape the request builder needs.
public struct ChatTurn: Sendable, Hashable {
    public enum Role: String, Sendable { case user, assistant }

    public struct Image: Sendable, Hashable {
        public var mimeType: String
        public var data: Data
        public init(mimeType: String, data: Data) {
            self.mimeType = mimeType
            self.data = data
        }
    }

    public struct Document: Sendable, Hashable {
        public var name: String
        public var text: String
        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public var role: Role
    public var text: String
    public var images: [Image]
    public var documents: [Document]

    public init(role: Role, text: String, images: [Image] = [], documents: [Document] = []) {
        self.role = role
        self.text = text
        self.images = images
        self.documents = documents
    }
}

public enum RequestBuilder {
    /// The API only sees what is in this request: the system prompt and this chat's turns. Nothing else.
    public static func request(
        settings: GenerationSettings,
        systemPrompt: String,
        turns: [ChatTurn],
        allowImages: Bool,
        stream: Bool = true
    ) -> ChatCompletionRequest {
        let s = settings.sanitized
        var msgs = messages(systemPrompt: systemPrompt, turns: turns, allowImages: allowImages)

        if s.jsonMode, !msgs.contains(where: { $0.content.textValue.localizedCaseInsensitiveContains("json") }) {
            // JSON mode requires the prompt itself to ask for JSON.
            let instruction = "Respond only with valid JSON."
            if let first = msgs.first, first.role == "system", case .text(let prompt) = first.content {
                msgs[0].content = .text(prompt + "\n\n" + instruction)
            } else {
                msgs.insert(WireMessage(role: "system", content: .text(instruction)), at: 0)
            }
        }

        return ChatCompletionRequest(
            model: s.model,
            messages: msgs,
            stream: stream,
            streamOptions: stream ? .init(includeUsage: true) : nil,
            thinking: .init(type: s.thinking ? "enabled" : "disabled"),
            reasoningEffort: s.thinking ? s.reasoningEffort.rawValue : nil,
            // Thinking mode ignores temperature, so only send it when it does something.
            temperature: s.thinking ? nil : s.temperature,
            topP: s.topP,
            maxTokens: s.maxTokens,
            responseFormat: s.jsonMode ? .init(type: "json_object") : nil,
            stop: s.stopSequences.isEmpty ? nil : s.stopSequences
        )
    }

    public static func messages(systemPrompt: String, turns: [ChatTurn], allowImages: Bool) -> [WireMessage] {
        var result: [WireMessage] = []
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            result.append(WireMessage(role: "system", content: .text(prompt)))
        }
        for turn in merged(turns) {
            switch turn.role {
            case .assistant:
                guard !turn.text.isEmpty else { continue }
                result.append(WireMessage(role: "assistant", content: .text(turn.text)))
            case .user:
                result.append(WireMessage(role: "user", content: userContent(turn, allowImages: allowImages)))
            }
        }
        return result
    }

    /// Joins back-to-back turns from the same role (e.g. a user message whose reply failed,
    /// followed by another user message). The API expects roles to alternate.
    static func merged(_ turns: [ChatTurn]) -> [ChatTurn] {
        var out: [ChatTurn] = []
        for turn in turns {
            if turn.role == .assistant, turn.text.isEmpty { continue }
            if let last = out.last, last.role == turn.role {
                var combined = last
                combined.text = [last.text, turn.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                combined.images += turn.images
                combined.documents += turn.documents
                out[out.count - 1] = combined
            } else {
                out.append(turn)
            }
        }
        return out
    }

    static func userContent(_ turn: ChatTurn, allowImages: Bool) -> WireContent {
        var sections = turn.documents.map(DocumentText.wrap)
        if !turn.images.isEmpty, !allowImages {
            let n = turn.images.count
            sections.append("[\(n) image\(n == 1 ? "" : "s") attached, but the selected model can't view images.]")
        }
        if !turn.text.isEmpty { sections.append(turn.text) }
        let body = sections.joined(separator: "\n\n")

        guard allowImages, !turn.images.isEmpty else { return .text(body) }
        var parts: [WirePart] = []
        if !body.isEmpty { parts.append(.text(body)) }
        for image in turn.images {
            parts.append(.imageURL("data:\(image.mimeType);base64,\(image.data.base64EncodedString())"))
        }
        return .parts(parts)
    }
}

public enum DocumentText {
    /// Longer documents are cut to this many characters before sending.
    public static let characterLimit = 600_000

    public static func wrap(_ doc: ChatTurn.Document) -> String {
        let name = doc.name.replacingOccurrences(of: "\"", with: "'")
        return "<document name=\"\(name)\">\n\(doc.text)\n</document>"
    }

    /// Returns the text cut to `characterLimit`, and whether it was cut.
    public static func truncated(_ text: String) -> (String, Bool) {
        guard text.count > characterLimit else { return (text, false) }
        return (String(text.prefix(characterLimit)) + "\n[… truncated]", true)
    }
}

public enum ChatTitle {
    /// A short title from the first line of the first message.
    public static func make(from text: String, maxLength: Int = 48) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let cleaned = firstLine.replacingOccurrences(of: #"[#*_`>]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.count > maxLength else { return cleaned }
        let cut = cleaned.prefix(maxLength)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxLength / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
