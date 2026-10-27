import Foundation
import Testing
@testable import ChatCore

@Suite struct StreamParserTests {
    let parser = StreamParser()

    @Test func reasoningAndContentDeltas() throws {
        let reasoning = #"data: {"id":"1","object":"chat.completion.chunk","model":"deepseek-flash","choices":[{"index":0,"delta":{"role":"assistant","content":null,"reasoning_content":"Let me think"},"finish_reason":null}]}"#
        #expect(try parser.parse(line: reasoning) == [.reasoning("Let me think")])

        let content = #"data: {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}"#
        #expect(try parser.parse(line: content) == [.content("Hello")])
    }

    @Test func finishUsageAndDone() throws {
        let finish = #"data: {"choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}]}"#
        #expect(try parser.parse(line: finish) == [.finished(reason: "stop")])

        let usage = #"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":30,"total_tokens":42,"prompt_cache_hit_tokens":8,"completion_tokens_details":{"reasoning_tokens":20}}}"#
        #expect(try parser.parse(line: usage) == [.usage(Usage(promptTokens: 12, completionTokens: 30, cacheHitTokens: 8, reasoningTokens: 20))])

        #expect(try parser.parse(line: "data: [DONE]") == [.done])
    }

    @Test func ignoresKeepAlivesAndNoise() throws {
        #expect(try parser.parse(line: ": keep-alive") == [])
        #expect(try parser.parse(line: "") == [])
        #expect(try parser.parse(line: "event: ping") == [])
        #expect(try parser.parse(line: "data: not json") == [])
    }

    @Test func midStreamErrorThrows() {
        let line = #"data: {"error":{"message":"Server overloaded","type":"server_error"}}"#
        #expect(throws: StreamError(message: "Server overloaded")) {
            try parser.parse(line: line)
        }
    }

    @Test func otherEndpoints() throws {
        let models = try JSONDecoder().decode(ModelList.self, from: Data(#"{"object":"list","data":[{"id":"deepseek-flash","object":"model","owned_by":"deepseek"},{"id":"deepseek-v4-pro","object":"model","owned_by":"deepseek"}]}"#.utf8))
        #expect(models.data.map(\.id) == ["deepseek-flash", "deepseek-v4-pro"])

        let balance = try JSONDecoder().decode(Balance.self, from: Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#.utf8))
        #expect(balance.formatted == "¥110.00")

        #expect(APIErrorEnvelope.message(from: Data(#"{"error":{"message":"Authentication Fails","type":"authentication_error"}}"#.utf8)) == "Authentication Fails")
    }
}
