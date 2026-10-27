import ChatCore
import Foundation

struct DeepSeekClient {
    enum ClientError: LocalizedError {
        case http(status: Int, message: String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(_, let message): message
            case .badResponse: "DeepSeek sent a response the app couldn't read."
            }
        }

        var status: Int? {
            if case .http(let status, _) = self { status } else { nil }
        }
    }

    static let baseURL = URL(string: "https://api.deepseek.com")!

    let apiKey: String

    func models() async throws -> [String] {
        let (data, response) = try await URLSession.shared.data(for: request("models"))
        try Self.check(response, data)
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
    }

    func balance() async throws -> Balance {
        let (data, response) = try await URLSession.shared.data(for: request("user/balance"))
        try Self.check(response, data)
        return try JSONDecoder().decode(Balance.self, from: data)
    }

    /// Streams a chat completion. Cancelling the consuming task cancels the request.
    func stream(_ body: ChatCompletionRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let urlRequest: URLRequest
        do {
            var r = request("chat/completions", method: "POST")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            // Idle timeout between bytes; DeepSeek sends keep-alives while it thinks.
            r.timeoutInterval = 600
            r.httpBody = try JSONEncoder().encode(body)
            urlRequest = r
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 65_536 { break }
                        }
                        throw Self.httpError(http.statusCode, data)
                    }
                    let parser = StreamParser()
                    for try await line in bytes.lines {
                        for event in try parser.parse(line: line) {
                            if event == .done {
                                continuation.finish()
                                return
                            }
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw httpError(http.statusCode, data) }
    }

    private static func httpError(_ status: Int, _ data: Data) -> ClientError {
        let server = APIErrorEnvelope.message(from: data)
        let message: String = switch status {
        case 401: "DeepSeek rejected the API key. Check it in Settings."
        case 402: "Your DeepSeek balance has run out. Top up at platform.deepseek.com."
        case 429: "DeepSeek is rate-limiting requests. Wait a moment and try again."
        case 500, 502, 503: "DeepSeek's servers are busy (\(status)). Try again shortly."
        default: server ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        }
        return .http(status: status, message: message)
    }
}
