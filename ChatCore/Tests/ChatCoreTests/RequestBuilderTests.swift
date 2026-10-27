import Foundation
import Testing
@testable import ChatCore

@Suite struct RequestBuilderTests {
    private func json(_ request: ChatCompletionRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func thinkingRequestOmitsTemperature() throws {
        let settings = GenerationSettings(model: "deepseek-flash", thinking: true, reasoningEffort: .max, temperature: 0.3, topP: 0.97)
        let req = RequestBuilder.request(settings: settings, systemPrompt: "Be brief.", turns: [ChatTurn(role: .user, text: "Hi")], allowImages: true)
        let body = try json(req)

        #expect(body["model"] as? String == "deepseek-flash")
        #expect((body["thinking"] as? [String: Any])?["type"] as? String == "enabled")
        #expect(body["reasoning_effort"] as? String == "max")
        #expect(body["temperature"] == nil)
        #expect(body["top_p"] as? Double == 0.97)
        #expect(body["stream"] as? Bool == true)
        #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
        #expect(body["max_tokens"] == nil)
        #expect(body["response_format"] == nil)
        #expect(body["stop"] == nil)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "Be brief.")
        #expect(messages[1]["content"] as? String == "Hi")
    }

    @Test func nonThinkingRequestSendsTemperatureAndClamps() throws {
        let settings = GenerationSettings(thinking: false, temperature: 5, maxTokens: 999_999_999, stopSequences: ["", "END"])
        let body = try json(RequestBuilder.request(settings: settings, systemPrompt: "", turns: [ChatTurn(role: .user, text: "Hi")], allowImages: true))

        #expect((body["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        #expect(body["reasoning_effort"] == nil)
        #expect(body["temperature"] as? Double == 2)
        #expect(body["max_tokens"] as? Int == GenerationSettings.maxTokensRange.upperBound)
        #expect(body["stop"] as? [String] == ["END"])
        // Empty system prompt is left out entirely.
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
    }

    @Test func imagesBecomeContentParts() throws {
        let image = ChatTurn.Image(mimeType: "image/png", data: Data([1, 2, 3]))
        let turn = ChatTurn(role: .user, text: "What is this?", images: [image])
        let body = try json(RequestBuilder.request(settings: .init(), systemPrompt: "", turns: [turn], allowImages: true))

        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "What is this?")
        #expect(parts[1]["type"] as? String == "image_url")
        #expect((parts[1]["image_url"] as? [String: Any])?["url"] as? String == "data:image/png;base64,AQID")
    }

    @Test func imagesFallBackToNoteWhenModelCantSee() throws {
        let image = ChatTurn.Image(mimeType: "image/jpeg", data: Data([9]))
        let turn = ChatTurn(role: .user, text: "Look", images: [image, image])
        let msgs = RequestBuilder.messages(systemPrompt: "", turns: [turn], allowImages: false)

        #expect(msgs.count == 1)
        guard case .text(let text) = msgs[0].content else {
            Issue.record("expected plain text")
            return
        }
        #expect(text.contains("2 images attached"))
        #expect(text.hasSuffix("Look"))
    }

    @Test func documentsComeBeforeTheQuestion() {
        let doc = ChatTurn.Document(name: "notes \"v2\".txt", text: "alpha")
        let msgs = RequestBuilder.messages(systemPrompt: "", turns: [ChatTurn(role: .user, text: "Summarise", documents: [doc])], allowImages: true)
        #expect(msgs[0].content == .text("<document name=\"notes 'v2'.txt\">\nalpha\n</document>\n\nSummarise"))
    }

    @Test func consecutiveTurnsAreMergedAndEmptyAssistantDropped() {
        let turns = [
            ChatTurn(role: .user, text: "First"),
            ChatTurn(role: .assistant, text: ""), // failed reply
            ChatTurn(role: .user, text: "Second"),
            ChatTurn(role: .assistant, text: "Answer"),
        ]
        let msgs = RequestBuilder.messages(systemPrompt: "sys", turns: turns, allowImages: true)
        #expect(msgs.map(\.role) == ["system", "user", "assistant"])
        #expect(msgs[1].content == .text("First\n\nSecond"))
    }

    @Test func jsonModeAddsInstructionWhenMissing() throws {
        let settings = GenerationSettings(jsonMode: true)
        let req = RequestBuilder.request(settings: settings, systemPrompt: "You list fruit.", turns: [ChatTurn(role: .user, text: "Three fruit")], allowImages: true)
        #expect(req.responseFormat?.type == "json_object")
        #expect(req.messages[0].content.textValue.hasSuffix("Respond only with valid JSON."))

        let already = RequestBuilder.request(settings: settings, systemPrompt: "", turns: [ChatTurn(role: .user, text: "Give me JSON")], allowImages: true)
        #expect(already.messages.count == 1)
    }

    @Test func settingsDecodeLeniently() throws {
        let data = Data(#"{"model":"deepseek-v4-pro","temperature":0.5}"#.utf8)
        let s = try JSONDecoder().decode(GenerationSettings.self, from: data)
        #expect(s.model == "deepseek-v4-pro")
        #expect(s.temperature == 0.5)
        #expect(s.thinking == true)
        #expect(s.reasoningEffort == .high)
    }

    @Test func titles() {
        #expect(ChatTitle.make(from: "\n  # Healthy eating tips  \nmore") == "Healthy eating tips")
        let long = ChatTitle.make(from: "Describe to me the basic principles of healthy eating briefly please")
        #expect(long.hasSuffix("…"))
        #expect(long.count <= 49)
    }
}
