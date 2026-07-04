import Foundation

/// Optional LLM polish via the local Ollama server. Any failure (server down,
/// timeout, empty output) falls back to the input text — dictation must never
/// block on Ollama.
struct OllamaClient {
    var baseURL = URL(string: "http://localhost:11434")!
    var timeout: TimeInterval = 6

    private static let systemPrompt = """
    You clean up dictated text. Fix punctuation and capitalization, remove filler \
    words like "um", "uh", "you know", and fix obvious grammar slips. Preserve the \
    speaker's wording, sentence structure, and meaning. Do not add, summarize, or \
    comment on content. Output ONLY the cleaned text with no preamble or quotes.
    """

    private struct GenerateRequest: Encodable {
        let model: String
        let system: String
        let prompt: String
        let stream: Bool
        let options: Options
        let keep_alive: String

        struct Options: Encodable {
            let temperature: Double
        }
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    func cleanup(_ text: String, model: String) async -> String {
        do {
            var request = URLRequest(url: baseURL.appending(path: "api/generate"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = timeout
            request.httpBody = try JSONEncoder().encode(GenerateRequest(
                model: model,
                system: Self.systemPrompt,
                prompt: text,
                stream: false,
                options: .init(temperature: 0.2),
                keep_alive: "5m"
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                NSLog("rbFlow: Ollama returned non-200, using rule-based cleanup")
                return text
            }
            let cleaned = try JSONDecoder().decode(GenerateResponse.self, from: data)
                .response.trimmingCharacters(in: .whitespacesAndNewlines)

            // Guard against a chatty/broken model: reject empty output or
            // output wildly longer than the input (hallucinated additions).
            guard !cleaned.isEmpty, cleaned.count < text.count * 3 + 80 else { return text }
            return cleaned
        } catch {
            NSLog("rbFlow: Ollama cleanup failed (%@), using rule-based cleanup",
                  error.localizedDescription)
            return text
        }
    }
}
